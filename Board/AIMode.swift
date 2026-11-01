import AppKit
import Carbon

/// One synthetic key transition. AI mode turns these into PhysicalInputEvents for Board's own sound and visualizer;
/// it never creates or posts a CGEvent, so it can't type into other apps (BoardTests checks the binary's imports).
struct AIStroke: Equatable {
    var key: Int
    var down: Bool
    var modifiers: UInt64 = 0
    var delay: TimeInterval   // after the previous stroke
}

enum AITyping {
    static let shiftKey = 56, commandKey = 55, returnKey = 36, tabKey = 48, deleteKey = 51
    // US ANSI virtual key codes 0–50 by index, unshifted and shifted; "§" stands in for ISO-only code 10.
    static let keys: [Character: (key: Int, shift: Bool)] = {
        var map: [Character: (key: Int, shift: Bool)] = [:]
        for (shift,row) in [(false,"asdfhgzxcv§bqweryt123465=97-80]ou[ip\nlj'k;\\,/nm.\t `"),(true,"ASDFHGZXCV§BQWERYT!@#$^%+(&_*)}OU{IP\nLJ\"K:|<?NM>\t ~")] {
            for (code,character) in row.enumerated() where character != "§" && map[character] == nil { map[character] = (code,shift) }
        }
        return map
    }()
    /// Seconds between keys: "Human" (0) about 9 a second, "Machine gun" (1) about 36.
    static func gap(_ speed: Double) -> TimeInterval { 0.11 * pow(0.25,min(1,max(0,speed))) }
    /// Leading spaces become one Tab per four, like an editor's indent; the rest of each line is typed as is.
    static func keyText(_ text: String) -> String {
        text.replacingOccurrences(of:"\r\n",with:"\n").components(separatedBy:"\n").map { line in
            let spaces = line.prefix { $0 == " " }.count
            return String(repeating:"\t",count:spaces/4) + String(repeating:" ",count:spaces%4) + line.dropFirst(spaces)
        }.joined(separator:"\n")
    }
    /// Keystrokes for `text`: bursts inside words, pauses after spaces, punctuation and line ends, at most `cap` seconds
    /// in all. With `typos`, it makes the odd typo and backspaces over it.
    static func plan(_ text: String, speed: Double, cap: TimeInterval = 10, typos: Bool = false) -> [AIStroke] {
        var rng = SystemRandomNumberGenerator()
        return plan(text,speed:speed,cap:cap,typos:typos,using:&rng)
    }
    static func plan<R: RandomNumberGenerator>(_ text: String, speed: Double, cap: TimeInterval = 10, typos: Bool = false, using rng: inout R) -> [AIStroke] {
        let gap = gap(speed), shiftFlag = CGEventFlags.maskShift.rawValue
        var strokes: [AIStroke] = [], total = 0.0, previous: Character = "x"
        func press(_ key: Int, shift: Bool, after delay: TimeInterval) -> [AIStroke] {
            let hold = gap*0.5
            guard shift else { return [.init(key:key,down:true,delay:delay),.init(key:key,down:false,delay:hold)] }
            return [.init(key:shiftKey,down:true,modifiers:shiftFlag,delay:delay),.init(key:key,down:true,modifiers:shiftFlag,delay:gap*0.3),
                    .init(key:key,down:false,modifiers:shiftFlag,delay:hold),.init(key:shiftKey,down:false,delay:gap*0.2)]
        }
        for character in keyText(text) {
            guard let (key,shift) = keys[character] else { continue }
            var factor = Double.random(in:0.6...1,using:&rng)
            if previous == " " { factor = 1.6 } else if ".,;:!?".contains(previous) { factor = 3 } else if previous == "\n" { factor = 5 }
            if factor >= 1.6 { factor *= Double.random(in:0.9...1.1,using:&rng) }
            var next = press(key,shift:shift,after:gap*factor)
            if typos, character.isLetter, Int.random(in:0..<35,using:&rng) == 0, let wrong = keys["asdfghjkl".randomElement(using:&rng)!] {
                next = press(wrong.key,shift:false,after:gap*factor) + press(deleteKey,shift:false,after:gap*3) + press(key,shift:shift,after:gap*1.5)
            }
            let duration = next.reduce(0) { $0+$1.delay }
            guard total+duration <= cap else { break }
            strokes += next; total += duration; previous = character
        }
        return strokes
    }
}

/// AI mode: while a Rex agent is working, Board codes along from real source files (joke mode). 0.4.1's agent hooks were
/// dropped: they only got an edit after it was written, so they couldn't follow the agent. Code text lives only in memory.
@MainActor final class AIMode {
    var onEvent: ((PhysicalInputEvent) -> Void)?
    var onStatus: ((String) -> Void)?
    var canPlay: () -> Bool = { true }   // Board's own pause rules (off, muted, inactive session); Secure Input is checked here too
    private var active = false, speed = 0.35, folder: String?, jokeFiles: [URL]?
    private var strokes: [AIStroke] = [], index = 0, token = 0, playing = false, paused = false
    private var held = Set<Int>()
    let agents = AgentWatch()
    private let watchAgents: Bool
    static let codeExtensions: Set<String> = ["swift","m","h","c","cc","cpp","rs","go","py","rb","js","ts","tsx","jsx","java","kt","cs","php","sh","zig","lua","css","html"]
    // Tests pass watchAgents: false so a working agent on the test Mac can't start joke typing mid-test.
    init(watchAgents: Bool = true) {
        self.watchAgents = watchAgents
        agents.onChange = { [weak self] in self?.next() }
    }
    func configure(enabled: Bool, speed: Double, folder: String?) {
        self.speed = speed
        if folder != self.folder { self.folder = folder; jokeFiles = nil }
        guard enabled != active else { return }
        enabled ? start() : stop()
    }
    private func start() {
        active = true
        if watchAgents { agents.start() }
        next()
    }
    func stop() {
        guard active else { return }
        active = false
        agents.stop()
        cancel()
        onStatus?("Off")
    }
    private func next() {
        guard active, !playing else { return }
        if agents.working, let chunk = jokeChunk() {
            var plan = AITyping.plan(chunk,speed:speed,typos:true)
            if !plan.isEmpty { plan[0].delay += Double.random(in:1...3); play(plan) }
        } else if agents.working {
            onStatus?("An agent is working, but there's no source to code along from")
        } else {
            onStatus?(agents.rexReachable ? "Waiting for a coding agent to work in Rex" : "Needs Rex to see when your agents are working")
        }
    }
    private func play(_ plan: [AIStroke]) {
        strokes = plan; index = 0; playing = true; paused = false
        onStatus?("Coding along from source files while an agent works")
        schedule(plan[0].delay)
    }
    private func schedule(_ delay: TimeInterval) {
        let mine = token
        DispatchQueue.main.asyncAfter(deadline:.now()+delay) { [weak self] in MainActor.assumeIsolated { if let self, self.token == mine { self.step() } } }
    }
    private func step() {
        guard canPlay(), !IsSecureEventInputEnabled() else {
            if !paused { paused = true; releaseHeld(); onStatus?("Paused while Board's sounds are paused") }
            schedule(0.5); return
        }
        if paused { paused = false; onStatus?("Coding along from source files while an agent works") }
        let stroke = strokes[index]; index += 1
        if stroke.down { held.insert(stroke.key) } else { held.remove(stroke.key) }
        emit(stroke.key,down:stroke.down,modifiers:stroke.modifiers)
        if index < strokes.count { schedule(strokes[index].delay) } else { playing = false; next() }
    }
    private func emit(_ key: Int, down: Bool, modifiers: UInt64) {
        onEvent?(PhysicalInputEvent(key:key,transition:down ? .press : .release,modifiers:modifiers,timestamp:ProcessInfo.processInfo.systemUptime))
    }
    private func releaseHeld() {
        let modifiers: Set = [AITyping.shiftKey,AITyping.commandKey]
        for key in held.subtracting(modifiers).sorted() + held.intersection(modifiers).sorted() { emit(key,down:false,modifiers:0) }
        held = []
    }
    private func cancel() { token += 1; releaseHeld(); playing = false; strokes = []; index = 0 }
    /// A few lines from a random source file: the chosen folder's code, or Board's own sources bundled in the app.
    private func jokeChunk() -> String? {
        if jokeFiles == nil {
            if let folder {
                var found: [URL] = []
                let walk = FileManager.default.enumerator(at:URL(fileURLWithPath:folder),includingPropertiesForKeys:nil,options:[.skipsHiddenFiles,.skipsPackageDescendants])
                while let url = walk?.nextObject() as? URL, found.count < 500 {
                    if ["build","dist","node_modules","DerivedData","Pods","vendor"].contains(url.lastPathComponent) { walk?.skipDescendants() }
                    else if Self.codeExtensions.contains(url.pathExtension.lowercased()) { found.append(url) }
                }
                jokeFiles = found
            } else { jokeFiles = Bundle.main.urls(forResourcesWithExtension:"swift",subdirectory:"Code") ?? [] }
        }
        guard let url = jokeFiles?.randomElement(), let handle = try? FileHandle(forReadingFrom:url) else { return nil }
        defer { try? handle.close() }
        let lines = String(decoding:(try? handle.read(upToCount:65536)) ?? Data(),as:UTF8.self).components(separatedBy:"\n")
        var line = Int.random(in:0..<lines.count), chunk = ""
        while line < lines.count, chunk.count < 600 { chunk += lines[line]+"\n"; line += 1 }
        return chunk.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty ? nil : chunk
    }
}

/// Whether a coding agent is working, as Rex reports it: the approach of Pulse's RexAgents (one snapshot, then Rex's event
/// stream). Every call passes --autostart=false, so Board never starts Rex; without Rex, no agent is working.
/// `defaults write com.tommyent.Board simulateWorkingAgent -bool YES` stands in for a working agent when testing without Rex.
@MainActor final class AgentWatch {
    var onChange: (() -> Void)?
    // Both are set only here, and by tests with watchAgents: false.
    var working = false { didSet { if working != oldValue { onChange?() } } }
    /// False while Rex isn't installed, doesn't answer, or its event stream has ended (until the next try, 30 s later).
    var rexReachable = true { didSet { if rexReachable != oldValue { onChange?() } } }
    private var blocks = Set<String>()
    private var stream: Process?
    private var generation = 0
    nonisolated static let apps: Set<String> = ["claude-code","codex","antigravity","grok"]
    func start() {
        stop()
        if UserDefaults.standard.bool(forKey:"simulateWorkingAgent") { working = true; return }
        guard let rex = Self.executable() else { rexReachable = false; return }
        generation += 1
        let mine = generation
        Task.detached(priority:.utility) {
            let found = Self.snapshot(rex)
            await MainActor.run {
                guard self.generation == mine else { return }
                self.rexReachable = found != nil
                self.blocks = found ?? []; self.working = !self.blocks.isEmpty
                self.follow(rex)
            }
        }
    }
    func stop() { generation += 1; stream?.terminate(); stream = nil; blocks = []; working = false }
    private func follow(_ rex: URL) {
        let process = Process(), out = Pipe()
        process.executableURL = rex; process.arguments = ["--autostart=false","events","--all","--json"]
        process.standardOutput = out; process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return }
        stream = process
        let mine = generation
        Task.detached(priority:.utility) { [self] in
            do {
                for try await line in out.fileHandleForReading.bytes.lines {
                    guard let (block,working) = Self.update(fromEvent:Data(line.utf8)) else { continue }
                    await MainActor.run { guard generation == mine else { return }; if working { blocks.insert(block) } else { blocks.remove(block) }; self.working = !blocks.isEmpty }
                }
            } catch {}
            // The stream ended (Rex quit or isn't running): nothing is working; look again in 30 s.
            await MainActor.run { guard generation == mine else { return }; blocks = []; working = false; rexReachable = false }
            try? await Task.sleep(nanoseconds:30_000_000_000)
            await MainActor.run { guard generation == mine else { return }; start() }
        }
    }
    nonisolated static func executable(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL? {
        [home.appendingPathComponent(".local/bin/rex"),URL(fileURLWithPath:"/opt/homebrew/bin/rex"),URL(fileURLWithPath:"/usr/local/bin/rex"),
         home.appendingPathComponent("Library/Application Support/com.superlogical.rex/RexServer/Versions/Current/Rex Server.app/Contents/MacOS/rex")]
            .first { FileManager.default.isExecutableFile(atPath:$0.path) }
    }
    /// Terminal panes whose agent reports "working" right now; nil when Rex doesn't answer (with --autostart=false, `rex`
    /// exits non-zero when no server is running).
    nonisolated static func snapshot(_ rex: URL) -> Set<String>? {
        guard let list = run(rex,["api","call","session.list"]),
              let sessions = (try? JSONSerialization.jsonObject(with:list) as? [String:Any])?["sessions"] as? [[String:Any]] else { return nil }
        var found = Set<String>()
        for session in sessions.compactMap({ $0["session_id"] as? String }) {
            guard let ls = run(rex,["block","ls","-s",session,"--json"]),
                  let blocks = (try? JSONSerialization.jsonObject(with:ls) as? [String:Any])?["blocks"] as? [[String:Any]] else { continue }
            for block in blocks {
                guard let id = block["block_id"] as? String, (block["flavor"] as? String)?.hasPrefix("com.superlogical.terminal") == true,
                      let status = run(rex,["block","call","-s",session,"-b",id,"program_status"]),
                      let records = (try? JSONSerialization.jsonObject(with:status) as? [String:Any])?["records"] as? [[String:Any]],
                      let root = records.first(where:{ ($0["id"] as? String ?? "").isEmpty }), isWorking(root) else { continue }
                found.insert(id)
            }
        }
        return found
    }
    nonisolated static func isWorking(_ record: [String:Any]) -> Bool {
        guard let app = record["app"] as? String ?? record["effective_app"] as? String else { return false }
        return apps.contains(app) && record["state"] as? String == "working"
    }
    /// A line of `rex events --all --json`: (pane, whether its agent is working now). nil for every other event.
    nonisolated static func update(fromEvent line: Data) -> (String,Bool)? {
        guard let top = try? JSONSerialization.jsonObject(with:line) as? [String:Any], top["type"] as? String == "session_event",
              let event = (top["payload"] as? [String:Any])?["event"] as? [String:Any], event["type"] as? String == "block_event",
              let blockEvent = event["payload"] as? [String:Any], let block = blockEvent["block_id"] as? String,
              let payload = blockEvent["payload"] as? [String:Any] else { return nil }
        switch blockEvent["name"] as? String {
        case "program_status_changed":
            guard (payload["id"] as? String ?? "").isEmpty, let record = payload["record"] as? [String:Any] else { return nil }
            return (block,isWorking(record))
        case "program_status_removed":
            guard (payload["ids"] as? [String])?.contains("") ?? true else { return nil }
            return (block,false)
        default: return nil
        }
    }
    /// One short `rex` call: its output, or nil on failure or after 5 s.
    nonisolated private static func run(_ rex: URL, _ args: [String]) -> Data? {
        let process = Process(), out = Pipe()
        process.executableURL = rex; process.arguments = ["--autostart=false","--timeout","3s"]+args
        process.standardOutput = out; process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return nil }
        let killer = DispatchWorkItem { process.terminate() }
        DispatchQueue.global().asyncAfter(deadline:.now()+5,execute:killer)
        let data = out.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit(); killer.cancel()
        return process.terminationStatus == 0 ? data : nil
    }
}
