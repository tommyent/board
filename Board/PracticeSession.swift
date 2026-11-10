import Foundation
import Combine

enum PracticeMode: String, CaseIterable, Codable, Identifiable {
    case english = "English", code = "Code", custom = "Your text"
    var id: Self { self }
}

struct PracticeResult: Codable, Identifiable {
    let id: UUID
    let date: Date
    let mode: PracticeMode
    let language: String
    let duration: Int
    let elapsed: Double
    let correct: Int
    let attempts: Int
    let correctAttempts: Int
    var wpm: Double { elapsed > 0 ? Double(correct) * 12 / elapsed : 0 }
    var accuracy: Double { attempts > 0 ? Double(correctAttempts) / Double(attempts) * 100 : 100 }
    var category: String { "\(mode.rawValue)\(mode == .code ? " · " + language : "") · \(duration)s" }
    var isValid: Bool {
        [30, 60, 120].contains(duration) && elapsed.isFinite && elapsed > 0 && elapsed <= Double(duration)
            && correct >= 0 && correct <= 10_000 && attempts >= correct && attempts <= 1_000_000
            && correctAttempts >= 0 && correctAttempts <= attempts
            && PracticePassages.languages.contains(language)
    }
}

struct PracticeStroke: Identifiable {
    let id = UUID()
    let label: String
    let time: TimeInterval
}

@MainActor final class PracticeSession: ObservableObject {
    enum Phase { case ready, running, paused, finished }
    static let durations = [30, 60, 120]
    static let textLimit = 10_000
    @Published var mode: PracticeMode = .english
    @Published var language = "Swift"
    @Published var duration = 60
    @Published var customText = ""
    @Published private(set) var target: [Character] = []
    @Published private(set) var typed = ""
    @Published private(set) var phase: Phase = .ready
    @Published private(set) var elapsed: TimeInterval = 0
    @Published private(set) var pauseReason = ""
    @Published private(set) var unavailableReason: String?
    @Published private(set) var attempts = 0
    @Published private(set) var correctAttempts = 0
    @Published private(set) var correct = 0
    @Published private(set) var strokes: [PracticeStroke] = []
    @Published private(set) var history: [PracticeResult] = []
    @Published private(set) var result: PracticeResult?
    @Published private(set) var historyError: String?
    @Published var showTrail = true
    @Published var focusRequest = 0
    private let defaults: UserDefaults
    private let clock: () -> TimeInterval
    private var segmentStart: TimeInterval?
    private var accumulated: TimeInterval = 0
    private var historyReadable = true
    private static let historyKey = "practice.history.v1"

    init(defaults: UserDefaults = .standard, clock: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }) {
        self.defaults = defaults
        self.clock = clock
        if let data = defaults.data(forKey: Self.historyKey) {
            if data.count <= 1_000_000, let saved = try? JSONDecoder().decode([PracticeResult].self, from: data), saved.allSatisfy(\.isValid) {
                history = Array(saved.prefix(200))
            } else {
                historyReadable = false
                historyError = "Saved practice history could not be read. It has been left unchanged. Clear History to start a new history."
            }
        }
        reset()
    }

    var remaining: Int { max(0, duration - Int(elapsed)) }
    var wpm: Double { elapsed > 0 ? Double(correct) * 12 / elapsed : 0 }
    var accuracy: Double { attempts == 0 ? 100 : Double(correctAttempts) / Double(attempts) * 100 }
    var acceptsInput: Bool { unavailableReason == nil && !target.isEmpty && (phase == .ready || phase == .running) }
    var best: Double? {
        guard mode != .custom else { return nil }
        return history.filter { $0.mode == mode && $0.duration == duration && (mode != .code || $0.language == language) }.map(\.wpm).max()
    }

    func reset() {
        if !Self.durations.contains(duration) { duration = 60 }
        if !PracticePassages.languages.contains(language) { language = "Swift" }
        let source = mode == .custom ? customText : PracticePassages.text(mode: mode, language: language)
        target = Array(Self.normalized(source).prefix(Self.textLimit))
        if target.allSatisfy(\.isWhitespace) { target = [] }
        typed = ""; attempts = 0; correctAttempts = 0; correct = 0
        elapsed = 0; accumulated = 0; segmentStart = nil
        result = nil; phase = .ready; pauseReason = ""; strokes = []
        focusRequest += 1
    }

    static func normalized(_ text: String) -> String {
        text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n").replacingOccurrences(of: "\t", with: "    ")
    }

    // Score committed text, including IME commits, never global key events or marked text.
    @discardableResult func replaceTyped(_ value: String) -> Bool {
        tick()
        guard acceptsInput else { return false }
        let next = Array(Self.normalized(value))
        guard next.count <= target.count else { return false }
        let previous = Array(typed)
        let shared = zip(previous, next).prefix { $0 == $1 }.count
        let unchangedTail = zip(previous.dropFirst(shared).reversed(), next.dropFirst(shared).reversed()).prefix { $0 == $1 }.count
        guard next != previous else { return true }
        if phase == .ready {
            guard !next.isEmpty else { return false }
            phase = .running; segmentStart = clock()
        }
        for index in shared..<(next.count - unchangedTail) {
            attempts += 1
            if next[index] == target[index] { correctAttempts += 1 }
        }
        typed = String(next)
        correct = zip(next, target).filter { $0 == $1 }.count
        if next.count == target.count { finish() }
        return true
    }

    func recordKey(_ label: String) {
        guard acceptsInput else { return }
        strokes.append(PracticeStroke(label: label, time: clock()))
        strokes = Array(strokes.suffix(7))
    }

    func tick() {
        let now = clock()
        if let first = strokes.first, now - first.time > 2 { strokes.removeAll { now - $0.time > 2 } }
        guard phase == .running, let segmentStart else { return }
        elapsed = min(Double(duration), accumulated + max(0, now - segmentStart))
        if elapsed >= Double(duration) { finish() }
    }

    func pause(_ reason: String = "Paused") {
        tick()
        guard phase == .running else { return }
        accumulated = elapsed; segmentStart = nil; phase = .paused; pauseReason = reason; strokes = []
    }

    func resume() {
        guard phase == .paused, unavailableReason == nil else { return }
        segmentStart = clock(); phase = .running; pauseReason = ""; focusRequest += 1
    }

    func updateAvailability(active: Bool, secureInput: Bool) {
        let reason = secureInput ? "Paused for Secure Input" : (active ? nil : "Paused while Practice is inactive")
        if unavailableReason != reason { unavailableReason = reason }
        if let reason { pause(reason); if !strokes.isEmpty { strokes = [] } }
    }

    func close() {
        pause("Practice closed")
        customText = ""
        reset()
        updateAvailability(active: false, secureInput: false)
    }

    private func finish() {
        guard phase == .running else { return }
        if let segmentStart { elapsed = min(Double(duration), accumulated + max(0, clock() - segmentStart)) }
        phase = .finished; segmentStart = nil; strokes = []
        guard attempts > 0, elapsed > 0 else { return }
        let entry = PracticeResult(id: UUID(), date: Date(), mode: mode, language: language, duration: duration,
                                   elapsed: elapsed, correct: correct, attempts: attempts, correctAttempts: correctAttempts)
        result = entry
        guard historyReadable, entry.isValid else { return }
        history.insert(entry, at: 0); history = Array(history.prefix(200))
        saveHistory()
    }

    func clearHistory() {
        history = []; historyReadable = true; historyError = nil
        defaults.removeObject(forKey: Self.historyKey)
    }

    private func saveHistory() {
        do { defaults.set(try JSONEncoder().encode(history), forKey: Self.historyKey) }
        catch { historyError = "Practice history could not be saved: \(error.localizedDescription)" }
    }
}
