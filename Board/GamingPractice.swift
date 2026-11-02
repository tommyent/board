import Foundation
import Combine

extension GamingDrill {
    var title: String {
        switch self {
        case .reaction: return "Reaction"
        case .strafeRhythm: return "Strafe rhythm"
        case .keyReversal: return "Key reversal"
        case .holdTap: return "Hold + tap"
        }
    }
}

extension GamingInput {
    var label: String {
        switch self {
        case .mouse(let button): return button == 0 ? "LMB" : "RMB"
        case .key(let code):
            return [0:"A", 1:"S", 2:"D", 13:"W", 12:"Q", 14:"E", 15:"R", 3:"F",
                    18:"1", 19:"2", 20:"3", 21:"4", 23:"5", 49:"Space", 56:"L Shift", 59:"L Ctrl"][code] ?? "Key \(code)"
        }
    }
}

struct GamingResult: Codable, Identifiable {
    let id: UUID
    let date: Date
    let drill: GamingDrill
    let duration: Double
    let tempo: Double
    let window: Double
    let keys: [GamingInput]
    let version: Int
    let median: Double?
    let mad: Double?
    let accuracy: Double
    let apm: Double
    let trials: Int
    let interruptions: Int

    var category: String {
        "\(drill.title) · \(Int(duration))s" + (drill == .reaction ? " · \(keys.map(\.label).joined(separator: "/"))" : " · \(Int(tempo)) BPM · \(drill == .keyReversal ? "≤" : "±")\(Int(window*1000)) ms")
    }
    var isValid: Bool {
        (try? GamingConfiguration(drill: drill, duration: duration, tempo: tempo, window: window,
                                 keys: drill == .reaction ? keys : GamingInput.wasd)) != nil
            && [accuracy, apm, median ?? 0, mad ?? 0].allSatisfy { $0.isFinite && $0 >= 0 }
            && accuracy <= 100 && apm <= 100_000 && trials >= 0 && trials <= 10_000 && interruptions >= 0
    }
    func matches(_ config: GamingConfiguration) -> Bool {
        version == GamingSession.scoringVersion && drill == config.drill && duration == config.duration
            && keys == config.keys && (drill == .reaction || (tempo == config.tempo && window == config.window))
    }
}

@MainActor final class GamingPractice: ObservableObject {
    @Published var selected = false
    @Published var drill = GamingDrill.reaction
    @Published var duration = 30.0
    @Published var tempo = 100.0
    @Published var timingWindow = 0.06
    @Published var keySet = 0
    @Published private(set) var engine: GamingSession?
    @Published private(set) var countdown: Int?
    @Published private(set) var unavailableReason: String?
    @Published private(set) var history: [GamingResult] = []
    @Published private(set) var historyError: String?
    @Published var focusRequest = 0
    private let clock: () -> Double
    private let defaults: UserDefaults
    private let automaticallyTicks: Bool
    private var timer: Timer?
    private var startsAt: Double?
    private var saved = false
    private var historyReadable = true
    private static let historyKey = "gaming.history.v1"

    init(defaults: UserDefaults = .standard, automaticallyTicks: Bool = true, clock: @escaping () -> Double = { ProcessInfo.processInfo.systemUptime }) {
        self.defaults = defaults; self.clock = clock; self.automaticallyTicks = automaticallyTicks
        if let data = defaults.data(forKey: Self.historyKey) {
            if let decoded = try? JSONDecoder().decode([GamingResult].self, from: data), decoded.count <= 200, decoded.allSatisfy(\.isValid) {
                history = decoded
            } else {
                historyReadable = false; historyError = "Gaming history could not be read. It has been preserved. Clear history to save new results."
            }
        }
    }
    deinit { timer?.invalidate() }
    private func runTimer() {
        guard automaticallyTicks, timer == nil else { return }
        let timer = Timer(timeInterval: 1.0/60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        self.timer = timer; RunLoop.main.add(timer, forMode: .common)
    }
    var configuration: GamingConfiguration? {
        let extended = GamingInput.wasd + [12,14,15,3,49,56,18,19,20,21,23].map { GamingInput.key(UInt16($0)) }
        let keys = keySet == 0 ? GamingInput.wasd : extended + (keySet == 2 ? [.mouse(0), .mouse(1)] : [])
        return try? GamingConfiguration(drill: drill, duration: duration, tempo: tempo, window: timingWindow, keys: keys)
    }
    var active: Bool { countdown != nil || engine?.phase == .running || engine?.phase == .paused }
    var acceptsInput: Bool { selected && unavailableReason == nil && engine?.phase == .running }
    var best: GamingResult? {
        guard let config = configuration else { return nil }
        return history.filter { $0.matches(config) && $0.accuracy >= 90 && $0.interruptions == 0 && $0.median != nil }
            .min { $0.median! < $1.median! }
    }
    func start() {
        guard selected, unavailableReason == nil, !active, let config = configuration else { return }
        engine = GamingSession(configuration: config); saved = false
        startsAt = clock()+3; countdown = 3; focusRequest += 1
        runTimer()
    }
    func tick() {
        let now = clock()
        if let deadline = startsAt {
            if now >= deadline {
                startsAt = nil; countdown = nil
                // Start when the first cue can actually be presented, after a delayed run-loop wakeup.
                engine?.start(at: now)
            } else { countdown = Int(ceil(deadline-now)) }
        }
        if engine?.phase == .running { engine?.advance(to: now) }
        saveFinished()
    }
    func pause() {
        if countdown != nil { startsAt = nil; countdown = nil; engine = nil }
        if engine?.phase == .running { engine?.pause(at: clock()) }
        saveFinished()
        timer?.invalidate(); timer = nil
    }
    func resume() {
        guard selected, unavailableReason == nil else { return }
        if engine?.resume(at: clock()) == true { focusRequest += 1; runTimer() }
    }
    func reset() { timer?.invalidate(); timer = nil; startsAt = nil; countdown = nil; engine = nil; saved = false }
    func updateAvailability(active: Bool, secureInput: Bool) {
        let reason: String? = secureInput ? "Paused for Secure Input" : (active ? nil : "Practice is not focused")
        if reason != nil { pause() }
        if unavailableReason != reason { unavailableReason = reason }
    }
    func press(_ input: GamingInput, isRepeat: Bool = false) {
        guard acceptsInput else { return }
        engine?.press(input, at: clock(), isRepeat: isRepeat); saveFinished()
    }
    func release(_ input: GamingInput) {
        guard acceptsInput else { return }
        engine?.release(input, at: clock()); saveFinished()
    }
    private func saveFinished() {
        guard let engine, engine.phase == .finished, !saved else { return }
        timer?.invalidate(); timer = nil
        saved = true
        guard historyReadable else { return }
        let config = engine.configuration, score = engine.score
        history.insert(GamingResult(id: UUID(), date: Date(), drill: config.drill, duration: config.duration,
                                    tempo: config.tempo, window: config.window, keys: config.keys,
                                    version: GamingSession.scoringVersion, median: score.medianMilliseconds,
                                    mad: score.madMilliseconds, accuracy: score.accuracyPercent ?? 0,
                                    apm: score.actionsPerMinute ?? 0, trials: score.completedTrials,
                                    interruptions: engine.results.filter { $0.verdict == .interrupted }.count), at: 0)
        history = Array(history.prefix(200))
        do { defaults.set(try JSONEncoder().encode(history), forKey: Self.historyKey) }
        catch { historyError = "Gaming history could not be saved: \(error.localizedDescription)" }
    }
    func clearHistory() {
        defaults.removeObject(forKey: Self.historyKey); history = []; historyReadable = true; historyError = nil
    }
}
