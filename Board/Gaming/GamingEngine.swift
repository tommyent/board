enum GamingInput: Hashable, Codable {
    case key(UInt16)
    case mouse(UInt8)

    static let a = Self.key(0), s = Self.key(1), d = Self.key(2), w = Self.key(13)
    static let space = Self.key(49), shift = Self.key(56)
    static let wasd: [Self] = [.w, .a, .s, .d]
}

enum GamingDrill: String, Codable, CaseIterable {
    case reaction, strafeRhythm, keyReversal, holdTap
}

struct GamingConfiguration: Equatable {
    enum Invalid: Error { case duration, tempo, window, keys }
    let drill: GamingDrill
    let duration: Double
    let tempo: Double
    let window: Double
    let keys: [GamingInput]

    init(drill: GamingDrill, duration: Double = 30, tempo: Double = 100,
         window: Double = 0.06, keys: [GamingInput] = GamingInput.wasd) throws {
        guard duration.isFinite, (3...600).contains(duration) else { throw Invalid.duration }
        guard tempo.isFinite, (30...300).contains(tempo) else { throw Invalid.tempo }
        guard window.isFinite, window > 0, window < 30/tempo else { throw Invalid.window }
        guard !keys.isEmpty, keys.count <= 64, Set(keys).count == keys.count else { throw Invalid.keys }
        self.drill = drill; self.duration = duration; self.tempo = tempo; self.window = window
        self.keys = drill == .reaction ? keys : []
    }
}

struct GamingCue: Equatable {
    let id: Int
    let startsAt: Double
    let targetAt: Double
    let deadline: Double
    let input: GamingInput
    let requiredHold: GamingInput?
    let requiredRelease: GamingInput?
}

enum GamingVerdict: Equatable {
    case hit, early, late, wrongKey, missingHold, wrongOrder, timeout, extra, interrupted
}

struct GamingTrialResult: Equatable {
    let cueID: Int
    let verdict: GamingVerdict
    // Reaction: cue-to-press; reversal: release-to-press; other drills: signed target error.
    let milliseconds: Double?
}

struct GamingScore: Equatable {
    let completedTrials: Int
    let hits: Int
    let extraPresses: Int
    let medianMilliseconds: Double?
    let madMilliseconds: Double?
    let accuracyPercent: Double?
    let onTimePercent: Double?
    let actionsPerMinute: Double?
}

struct GamingSession {
    enum Phase: Equatable { case ready, running, paused, finished }
    static let scoringVersion = 1
    let configuration: GamingConfiguration
    let cues: [GamingCue]
    private(set) var phase = Phase.ready
    private(set) var elapsed = 0.0
    private(set) var results: [GamingTrialResult] = []
    private(set) var actions = 0
    private(set) var extraPresses = 0
    private(set) var lastFeedback: GamingVerdict?
    private var held: [GamingInput: Double] = [:]
    private var lastWallTime: Double?
    private var nextIndex = 0
    private var reversalRelease: Double?
    // Subtracting an uptime origin loses precision; use its representable spacing at cue boundaries.
    private var clockTolerance: Double { max(1e-9, (lastWallTime ?? 0).ulp*2) }

    init(configuration: GamingConfiguration) {
        var random = SystemRandomNumberGenerator()
        self.init(configuration: configuration, using: &random)
    }

    init<R: RandomNumberGenerator>(configuration: GamingConfiguration, using random: inout R) {
        self.configuration = configuration
        var planned: [GamingCue] = []
        switch configuration.drill {
        case .reaction:
            var start = 0.0
            while true {
                let target = start + Double.random(in: 0.5...1.25, using: &random)
                let deadline = target + 1.25
                guard deadline <= configuration.duration else { break }
                let input = configuration.keys.randomElement(using: &random)!
                planned.append(GamingCue(id: planned.count, startsAt: start, targetAt: target,
                                         deadline: deadline, input: input, requiredHold: nil, requiredRelease: nil))
                start = deadline
            }
        case .strafeRhythm, .keyReversal, .holdTap:
            let beat = 60/configuration.tempo
            for index in 0..<Int((configuration.duration/beat).rounded(.down)) {
                let target: GamingInput = configuration.drill == .holdTap ? .space : (index.isMultiple(of: 2) ? .d : .a)
                planned.append(GamingCue(id: index, startsAt: Double(index)*beat, targetAt: (Double(index)+0.5)*beat,
                                         deadline: Double(index+1)*beat, input: target,
                                         requiredHold: configuration.drill == .holdTap ? .shift : nil,
                                         requiredRelease: configuration.drill == .keyReversal ? (target == .d ? .a : .d) : nil))
            }
        }
        cues = planned
    }

    var currentCue: GamingCue? {
        guard phase == .running, nextIndex < cues.count, cues[nextIndex].startsAt <= elapsed+clockTolerance else { return nil }
        return cues[nextIndex]
    }

    @discardableResult mutating func start(at time: Double) -> Bool {
        guard phase == .ready, time.isFinite, time >= 0 else { return false }
        lastWallTime = time; phase = .running
        return true
    }

    @discardableResult mutating func advance(to time: Double) -> Bool {
        guard phase == .running || phase == .paused,
              let previous = lastWallTime, time.isFinite, time >= previous else { return false }
        lastWallTime = time
        guard phase == .running else { return true }
        elapsed = min(configuration.duration, elapsed + (time-previous))
        while nextIndex < cues.count, cues[nextIndex].deadline <= elapsed+clockTolerance {
            resolve(.timeout)
        }
        if elapsed+clockTolerance >= configuration.duration {
            elapsed = configuration.duration; phase = .finished; held.removeAll(); reversalRelease = nil
        }
        return true
    }

    @discardableResult mutating func pause(at time: Double) -> Bool {
        guard phase == .running, advance(to: time), phase == .running else { return false }
        // Restart with a fresh cue after a focus/security pause; interrupted trials never enter scores.
        if currentCue != nil { resolve(.interrupted) }
        held.removeAll(); reversalRelease = nil; phase = .paused
        return true
    }

    @discardableResult mutating func resume(at time: Double) -> Bool {
        guard phase == .paused, advance(to: time) else { return false }
        phase = .running
        return true
    }

    @discardableResult mutating func press(_ input: GamingInput, at time: Double, isRepeat: Bool = false) -> GamingVerdict? {
        guard phase == .running, advance(to: time), phase == .running,
              !isRepeat, held[input] == nil else { return nil }
        if case .mouse = input, !configuration.keys.contains(input) { return nil }
        held[input] = elapsed; actions += 1
        if configuration.drill == .holdTap, input == .shift { return nil }
        guard let cue = currentCue else {
            extraPresses += 1; lastFeedback = .extra
            return .extra
        }
        if input == cue.requiredRelease, elapsed+clockTolerance < cue.targetAt { return nil }
        if configuration.drill == .reaction, elapsed+clockTolerance < cue.targetAt {
            return resolve(.early)
        }
        guard input == cue.input else { return resolve(.wrongKey) }
        if let required = cue.requiredHold, held[required] == nil { return resolve(.missingHold) }
        if let required = cue.requiredRelease {
            guard let released = reversalRelease, held[required] == nil else { return resolve(.wrongOrder) }
            let gap = elapsed-released
            return resolve(gap <= configuration.window+clockTolerance ? .hit : .late, milliseconds: gap*1000)
        }
        let error = elapsed-cue.targetAt
        if configuration.drill == .reaction { return resolve(.hit, milliseconds: max(0, error)*1000) }
        let verdict: GamingVerdict = abs(error) <= configuration.window+clockTolerance ? .hit : (error < 0 ? .early : .late)
        return resolve(verdict, milliseconds: error*1000)
    }

    mutating func release(_ input: GamingInput, at time: Double) {
        guard phase == .running, advance(to: time), phase == .running,
              let pressed = held.removeValue(forKey: input) else { return }
        if let cue = currentCue, cue.requiredRelease == input,
           pressed+clockTolerance < cue.targetAt, elapsed+clockTolerance >= cue.targetAt, held[cue.input] == nil {
            reversalRelease = elapsed
        }
    }

    @discardableResult private mutating func resolve(_ verdict: GamingVerdict, milliseconds: Double? = nil) -> GamingVerdict {
        results.append(GamingTrialResult(cueID: cues[nextIndex].id, verdict: verdict, milliseconds: milliseconds))
        nextIndex += 1; reversalRelease = nil; lastFeedback = verdict
        return verdict
    }

    var score: GamingScore {
        let scored = results.filter { $0.verdict != .interrupted }
        let hits = scored.filter { $0.verdict == .hit }.count
        let samples = scored.compactMap(\.milliseconds)
        let timed = configuration.drill == .strafeRhythm || configuration.drill == .holdTap
        let center = Self.median(samples)
        let denominator = scored.count+extraPresses
        let accuracy = denominator > 0 ? 100*Double(hits)/Double(denominator) : nil
        return GamingScore(completedTrials: scored.count, hits: hits, extraPresses: extraPresses,
                           medianMilliseconds: Self.median(timed ? samples.map { abs($0) } : samples),
                           madMilliseconds: center.flatMap { median in Self.median(samples.map { abs($0-median) }) },
                           accuracyPercent: accuracy,
                           onTimePercent: configuration.drill == .reaction ? nil : accuracy,
                           actionsPerMinute: elapsed > 0 ? Double(actions)*60/elapsed : nil)
    }

    private static func median(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted(), middle = sorted.count/2
        return sorted.count.isMultiple(of: 2) ? (sorted[middle-1]+sorted[middle])/2 : sorted[middle]
    }
}
