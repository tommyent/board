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
    /// in all. A real edit ends with ⌘S; joke typing makes the odd typo and backspaces over it.
    static func plan(_ text: String, speed: Double, cap: TimeInterval = 10, flourish: Bool = true, typos: Bool = false) -> [AIStroke] {
        var rng = SystemRandomNumberGenerator()
        return plan(text,speed:speed,cap:cap,flourish:flourish,typos:typos,using:&rng)
    }
    static func plan<R: RandomNumberGenerator>(_ text: String, speed: Double, cap: TimeInterval = 10, flourish: Bool = true, typos: Bool = false, using rng: inout R) -> [AIStroke] {
        let gap = gap(speed), shiftFlag = CGEventFlags.maskShift.rawValue, ending = flourish ? 0.5 : 0
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
            guard total+duration <= cap-ending else { break }
            strokes += next; total += duration; previous = character
        }
        if flourish {
            let command = CGEventFlags.maskCommand.rawValue, s = keys["s"]!.key
            strokes += [.init(key:commandKey,down:true,modifiers:command,delay:0.25),.init(key:s,down:true,modifiers:command,delay:0.08),
                        .init(key:s,down:false,modifiers:command,delay:0.07),.init(key:commandKey,down:false,delay:0.05)]
        }
        return strokes
    }
}

/// Board's hook in a coding agent's user settings: a PostToolUse entry for Write|Edit running the board-ai-hook script bundled
/// in Board.app (Codex matches its apply_patch edits to Write|Edit). Only that entry is ever added or removed.
enum AIHook {
    enum Agent: String, CaseIterable { case claude = "Claude Code", codex = "Codex" }
    struct Problem: LocalizedError { var message: String; var errorDescription: String? { message } }
    static let name = "board-ai-hook"
    static var script: URL? { Bundle.main.url(forResource:name,withExtension:nil) }
    static func settingsURL(_ agent: Agent) -> URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(agent == .claude ? ".claude/settings.json" : ".codex/hooks.json")
    }
    /// Claude Code runs exec form (args) with no shell; Codex runs the command through a shell, so the path is quoted there.
    static func entry(_ script: String, for agent: Agent) -> [String:Any] {
        let hook: [String:Any] = agent == .claude ? ["type":"command","command":script,"args":[String](),"async":true]
                                                  : ["type":"command","command":quoted(script),"async":true,"timeout":10]
        return ["matcher":"Write|Edit","hooks":[hook]]
    }
    static func quoted(_ path: String) -> String { "'" + path.replacingOccurrences(of:"'",with:"'\\''") + "'" }
    /// Whether an installed command runs this copy's script.
    static func runs(_ command: String?, _ script: String?) -> Bool { command != nil && script != nil && (command == script || command == quoted(script!)) }
    private static func isBoards(_ hook: Any) -> Bool { ((hook as? [String:Any])?["command"] as? String)?.contains("/"+name) == true }
    /// PostToolUse entries, refusing shapes Board doesn't recognise rather than overwriting them.
    private static func entries(_ settings: [String:Any]) throws -> ([String:Any],[[String:Any]]) {
        let unrecognised = Problem(message:"Its hooks setting has a shape Board doesn't recognise, so Board left the file alone.")
        var hooks: [String:Any] = [:]
        if let value = settings["hooks"] { guard let found = value as? [String:Any] else { throw unrecognised }; hooks = found }
        guard let value = hooks["PostToolUse"] else { return (hooks,[]) }
        guard let post = value as? [[String:Any]] else { throw unrecognised }
        return (hooks,post)
    }
    /// The command of Board's installed hook, if there is one.
    static func installed(in settings: [String:Any]) -> String? {
        let post = (try? entries(settings))?.1 ?? []
        return post.flatMap { ($0["hooks"] as? [Any]) ?? [] }.first(where:isBoards).flatMap { ($0 as? [String:Any])?["command"] as? String }
    }
    static func removing(from settings: [String:Any]) throws -> [String:Any] {
        var (hooks,post) = try entries(settings), settings = settings
        post = post.compactMap { entry in
            guard let list = entry["hooks"] as? [Any], list.contains(where:isBoards) else { return entry }
            let rest = list.filter { !isBoards($0) }   // keep anyone else's hook that shares the entry
            if rest.isEmpty { return nil }
            var entry = entry; entry["hooks"] = rest; return entry
        }
        hooks["PostToolUse"] = post.isEmpty ? nil : post
        settings["hooks"] = hooks.isEmpty ? nil : hooks
        return settings
    }
    static func installing(_ script: String, for agent: Agent, into settings: [String:Any]) throws -> [String:Any] {
        var settings = try removing(from:settings), (hooks,post) = try entries(settings)
        post.append(entry(script,for:agent))
        hooks["PostToolUse"] = post; settings["hooks"] = hooks
        return settings
    }
    static func read(_ url: URL) throws -> [String:Any] {
        guard FileManager.default.fileExists(atPath:url.path) else { return [:] }
        guard let settings = try JSONSerialization.jsonObject(with:Data(contentsOf:url)) as? [String:Any] else { throw Problem(message:"It isn't a JSON object, so Board left it alone.") }
        return settings
    }
    /// Rewrites the file with `change` applied, keeping the previous version as <name>.bak-board and the file's permissions.
    static func update(_ url: URL, _ change: ([String:Any]) throws -> [String:Any]) throws {
        let manager = FileManager.default, existing = manager.fileExists(atPath:url.path)
        let updated = try JSONSerialization.data(withJSONObject:change(read(url)),options:[.prettyPrinted,.sortedKeys,.withoutEscapingSlashes])
        let permissions = (try? manager.attributesOfItem(atPath:url.path))?[.posixPermissions] as? NSNumber ?? 0o600
        if existing { try Data(contentsOf:url).write(to:url.appendingPathExtension("bak-board"),options:.atomic) }
        else { try manager.createDirectory(at:url.deletingLastPathComponent(),withIntermediateDirectories:true) }
        try updated.write(to:url,options:.atomic)
        try manager.setAttributes([.posixPermissions:permissions],ofItemAtPath:url.path)
    }
}

/// Edits waiting to be typed, oldest first. Only the newest few are kept so a burst of edits can't build a long backlog.
struct AIQueue {
    private(set) var items: [String] = []
    var limit = 3
    mutating func push(_ text: String) { items.append(text); if items.count > limit { items.removeFirst(items.count-limit) } }
    mutating func pop() -> String? { items.isEmpty ? nil : items.removeFirst() }
}

/// AI mode: types edits that Scripts/board-ai-hook queues from Claude Code, and codes along from real source files while
/// a Rex agent is working. Code text lives only in memory and in the queue folder until it is read.
@MainActor final class AIMode {
    var onEvent: ((PhysicalInputEvent) -> Void)?
    var onStatus: ((String) -> Void)?
    var canPlay: () -> Bool = { true }   // Board's own pause rules (off, muted, inactive session); Secure Input is checked here too
    let directory: URL
    private var marker: URL { directory.appendingPathComponent("listening") }
    private var active = false, speed = 0.35, folder: String?, jokeFiles: [URL]?
    private var watcher: DispatchSourceFileSystemObject?
    private var queue = AIQueue()
    private var strokes: [AIStroke] = [], index = 0, token = 0, playing = false, typingEdit = false, paused = false
    private var held = Set<Int>()
    private let agents = AgentWatch(), watchAgents: Bool
    static let codeExtensions: Set<String> = ["swift","m","h","c","cc","cpp","rs","go","py","rb","js","ts","tsx","jsx","java","kt","cs","php","sh","zig","lua","css","html"]
    // Tests pass watchAgents: false so a working agent on the test Mac can't start joke typing mid-test.
    init(directory: URL = FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0].appendingPathComponent("Board/AI Queue"), watchAgents: Bool = true) {
        self.directory = directory; self.watchAgents = watchAgents
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
        do {
            try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true,attributes:[.posixPermissions:0o700])
            purge()
            try String(getpid()).write(to:marker,atomically:true,encoding:.utf8)
        } catch { onStatus?("AI mode can't use its folder: \(error.localizedDescription)"); return }
        let fd = open(directory.path,O_EVTONLY)
        guard fd >= 0 else { onStatus?("AI mode can't watch its folder."); return }
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor:fd,eventMask:.write,queue:.main)
        source.setEventHandler { [weak self] in MainActor.assumeIsolated { self?.collect() } }
        source.setCancelHandler { close(fd) }
        source.resume(); watcher = source
        if watchAgents { agents.start() }
        onStatus?("Waiting for an edit from Claude Code")
    }
    func stop() {
        guard active else { return }
        active = false
        watcher?.cancel(); watcher = nil
        agents.stop()
        try? FileManager.default.removeItem(at:marker)
        purge(); queue = AIQueue(); cancel()
        onStatus?("Off")
    }
    private func purge() {
        for url in (try? FileManager.default.contentsOfDirectory(at:directory,includingPropertiesForKeys:nil)) ?? [] where url.lastPathComponent != "listening" { try? FileManager.default.removeItem(at:url) }
    }
    /// Reads each queued edit once and deletes it straight away. Files older than 30 s are stale and only deleted.
    private func collect() {
        guard active else { return }
        let files = ((try? FileManager.default.contentsOfDirectory(at:directory,includingPropertiesForKeys:[.creationDateKey],options:.skipsHiddenFiles)) ?? [])
            .filter { $0.pathExtension == "txt" }
            .map { ($0,(try? $0.resourceValues(forKeys:[.creationDateKey]).creationDate) ?? .distantPast) }
            .sorted { $0.1 < $1.1 }
        guard !files.isEmpty else { return }
        for (url,created) in files {
            defer { try? FileManager.default.removeItem(at:url) }
            guard created.timeIntervalSinceNow > -30, let handle = try? FileHandle(forReadingFrom:url) else { continue }
            let data = (try? handle.read(upToCount:8192)) ?? Data()
            try? handle.close()
            if !data.isEmpty { queue.push(String(decoding:data,as:UTF8.self)) }
        }
        if playing, !typingEdit { cancel() }   // real code wins over joke typing
        next()
    }
    private func next() {
        guard active, !playing else { return }
        if let text = queue.pop() {
            play(AITyping.plan(text,speed:speed),edit:true)
        } else if agents.working, let chunk = jokeChunk() {
            var plan = AITyping.plan(chunk,speed:speed,flourish:false,typos:true)
            if !plan.isEmpty { plan[0].delay += Double.random(in:1...3); play(plan,edit:false) }
        } else {
            onStatus?(agents.working ? "An agent is working, but there's no source to code along from" : "Waiting for an edit from Claude Code")
        }
    }
    private func play(_ plan: [AIStroke], edit: Bool) {
        guard !plan.isEmpty else { next(); return }
        strokes = plan; index = 0; playing = true; typingEdit = edit; paused = false
        onStatus?(edit ? "Typing an edit from Claude Code" : "Coding along from source files while an agent works")
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
        if paused { paused = false; onStatus?(typingEdit ? "Typing an edit from Claude Code" : "Coding along from source files while an agent works") }
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
    private(set) var working = false { didSet { if working != oldValue { onChange?() } } }
    private var blocks = Set<String>()
    private var stream: Process?
    private var generation = 0
    nonisolated static let apps: Set<String> = ["claude-code","codex","antigravity","grok"]
    func start() {
        stop()
        if UserDefaults.standard.bool(forKey:"simulateWorkingAgent") { working = true; return }
        guard let rex = Self.executable() else { return }
        generation += 1
        let mine = generation
        Task.detached(priority:.utility) {
            let found = Self.snapshot(rex)
            await MainActor.run {
                guard self.generation == mine else { return }
                self.blocks = found; self.working = !found.isEmpty
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
            await MainActor.run { guard generation == mine else { return }; blocks = []; working = false }
            try? await Task.sleep(nanoseconds:30_000_000_000)
            await MainActor.run { guard generation == mine else { return }; start() }
        }
    }
    nonisolated static func executable(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL? {
        [home.appendingPathComponent(".local/bin/rex"),URL(fileURLWithPath:"/opt/homebrew/bin/rex"),URL(fileURLWithPath:"/usr/local/bin/rex"),
         home.appendingPathComponent("Library/Application Support/com.superlogical.rex/RexServer/Versions/Current/Rex Server.app/Contents/MacOS/rex")]
            .first { FileManager.default.isExecutableFile(atPath:$0.path) }
    }
    /// Terminal panes whose agent reports "working" right now. Empty when Rex isn't running.
    nonisolated static func snapshot(_ rex: URL) -> Set<String> {
        guard let list = run(rex,["api","call","session.list"]),
              let sessions = (try? JSONSerialization.jsonObject(with:list) as? [String:Any])?["sessions"] as? [[String:Any]] else { return [] }
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
