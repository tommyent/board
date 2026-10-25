import XCTest
import AppKit
import AVFoundation
import AudioToolbox
@testable import Board

final class BoardTests: XCTestCase {
    func testPhysicalTransitionsAndShortcut() {
        var normalizer = InputNormalizer()
        XCTAssertNotNil(normalizer.accept(key:0,down:true,time:0))
        XCTAssertNil(normalizer.accept(key:0,down:true,repeatEvent:true,time:0.1))
        XCTAssertNil(normalizer.accept(key:0,down:true,time:0.2))
        XCTAssertNotNil(normalizer.accept(key:0,down:false,time:0.3))
        XCTAssertNil(normalizer.accept(key:0,down:false,time:0.4))
        for key in [55,54,56,60,1000,2000] { XCTAssertNotNil(normalizer.accept(key:key,down:true,time:1)); XCTAssertNotNil(normalizer.accept(key:key,down:false,time:2)) }
        _ = normalizer.accept(key:1,down:true,time:3); normalizer.clear(); XCTAssertTrue(normalizer.held.isEmpty)
        var settings = AppSettings(), shortcut = ShortcutState(); settings.gestureTaps = 3
        for i in 0..<3 { XCTAssertEqual(shortcut.matches(.init(key:40,transition:.press,modifiers:settings.shortcutModifiers,timestamp:Double(i)*0.1),settings:settings),i == 2) }
        XCTAssertFalse(shortcut.matches(.init(key:40,transition:.press,modifiers:0,timestamp:0.4),settings:settings))
    }
    func testGeometryMappingsAndTiming() {
        for layout in ["ANSI","ISO","JIS"] {
            let keys = KeyGeometry.keys(layout)
            XCTAssertEqual(Set(keys.map(\.id)).count,keys.count)
            XCTAssertTrue(keys.allSatisfy { $0.x >= 0 && $0.x+$0.width <= 15 && $0.width > 0 })
            for (index,key) in keys.enumerated() {
                let rect = CGRect(x:key.x,y:Double(key.row),width:key.width,height:key.height).insetBy(dx:0.001,dy:0.001)
                for other in keys.dropFirst(index+1) {
                    XCTAssertFalse(rect.intersects(CGRect(x:other.x,y:Double(other.row),width:other.width,height:other.height).insetBy(dx:0.001,dy:0.001)),"Overlapping \(layout) keys \(key.id) and \(other.id)")
                }
            }
        }
        XCTAssertEqual(KeyGeometry.sampleName(49,down:true),"SPACE")
        XCTAssertEqual(KeyGeometry.sampleName(0,down:true),"GENERIC_R2")
        XCTAssertEqual(KeyGeometry.sampleName(0,down:false),"GENERIC")
        XCTAssertLessThan(KeyGeometry.position(0,layout:"ANSI"),0)
        XCTAssertGreaterThan(KeyGeometry.position(37,layout:"ANSI"),0)
        let chord = PhysicalInputEvent(key:1,transition:.press,modifiers:CGEventFlags.maskCommand.rawValue,timestamp:0)
        XCTAssertEqual(KeyGeometry.chord(chord),"⌘ S")
        var settings = VisualizerSettings(), combo = ComboState()
        XCTAssertTrue(combo.press(at:0,settings:settings))
        for i in 1..<5 { XCTAssertEqual(combo.press(at:Double(i)*0.1,settings:settings),i == 4) }
        XCTAssertEqual(combo.count,5); XCTAssertFalse(combo.visible(at:2,settings:settings))
        _ = combo.press(at:3,settings:settings); XCTAssertEqual(combo.count,1)
        settings.preserveCombo = true; _ = combo.press(at:6,settings:settings); XCTAssertEqual(combo.count,2)
        settings.style = "Combo"; settings.keepComboVisible = true; XCTAssertTrue(combo.visible(at:100,settings:settings))
        combo.expire(at:100,settings:settings); XCTAssertEqual(combo.count,2)
        settings.preserveCombo = false; combo.expire(at:100,settings:settings); XCTAssertEqual(combo.count,0)
        XCTAssertTrue(combo.visible(at:100,settings:settings))
        combo.clear(); XCTAssertFalse(combo.visible(at:100,settings:settings))
    }
    func testPersistenceAndValidation() throws {
        var settings = AppSettings(); settings.sound.overrides[0] = KeyOverride(profile:"cream",tone:-0.3,pitch:2,volume:0.4)
        settings.presets.append(SoundPreset(name:"Quiet",sound:settings.sound))
        let data = try JSONEncoder().encode(settings)
        XCTAssertEqual(settings,try JSONDecoder().decode(AppSettings.self,from:data))
        settings.sound.volume = .nan; settings.visualizer.dismiss = -50; settings.gestureTaps = 99; settings.validate()
        XCTAssertEqual(settings.sound.volume,0); XCTAssertEqual(settings.visualizer.dismiss,0.3); XCTAssertEqual(settings.gestureTaps,5)
        settings.sound.profile = "k2red"
        settings.sound.overrides[0]?.profile = "lizard"
        settings.presets[0].sound.profile = "mq80"
        settings.presets[0].sound.overrides[0]?.profile = "surfer"
        settings.validate()
        XCTAssertEqual(settings.sound.profile,"alpaca")
        XCTAssertNil(settings.sound.overrides[0]?.profile)
        XCTAssertEqual(settings.sound.overrides[0]?.volume,0.4)
        XCTAssertEqual(settings.presets[0].sound.profile,"alpaca")
        XCTAssertNil(settings.presets[0].sound.overrides[0]?.profile)
        XCTAssertThrowsError(try AudioFiles.managedURL("../../secret.wav",root:URL(fileURLWithPath:"/tmp")))
    }
    @MainActor func testInvalidSavedPresetIsClampedOnLoad() throws {
        // An older or hand-edited preference: choosing this favorite must not bring back out-of-range values.
        var broken = SoundConfiguration(); broken.volume = 40; broken.pitch = -99; broken.tone = 3; broken.width = 9
        broken.overrides[0] = KeyOverride(tone:3,pitch:50,volume:-2)
        var saved = AppSettings(); saved.presets = [SoundPreset(name:"Broken",sound:broken)]
        // One fixed suite: removePersistentDomain empties it but leaves its plist, so a per-run name would leave one file per run.
        let suite = "com.tommyent.Board.tests", defaults = try XCTUnwrap(UserDefaults(suiteName:suite))
        defaults.removePersistentDomain(forName:suite)
        defer { defaults.removePersistentDomain(forName:suite) }
        defaults.set(try JSONEncoder().encode(saved),forKey:"appSettings.v1")
        let app = AppState(defaults:defaults)
        app.settings.sound = app.settings.presets[0].sound // what choosing the favorite does
        XCTAssertEqual(app.settings.sound.volume,1); XCTAssertEqual(app.settings.sound.pitch,-12); XCTAssertEqual(app.settings.sound.tone,1); XCTAssertEqual(app.settings.sound.width,2)
        XCTAssertEqual(app.settings.sound.overrides[0],KeyOverride(tone:1,pitch:12,volume:0))
    }
    @MainActor func testSpaceChangeClearsKeystrokeLabels() {
        let app = AppState(defaults:UserDefaults(suiteName:"com.tommyent.Board.tests.space")!), overlay = OverlayController(app:app)
        app.pills = ["⌘ S"]
        NSWorkspace.shared.notificationCenter.post(name:NSWorkspace.activeSpaceDidChangeNotification,object:nil)
        RunLoop.main.run(until:Date()+0.1)
        XCTAssertEqual(app.pills,[])
        withExtendedLifetime(overlay) {}
    }
    func testAppIconColors() throws {
        var settings = AppSettings(); settings.iconColor = "Sage"
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with:JSONEncoder().encode(settings)) as? [String:Any])
        XCTAssertEqual(try JSONDecoder().decode(AppSettings.self,from:JSONEncoder().encode(settings)).iconColor,"Sage")
        json["iconColor"] = nil // Settings saved before the icon picker existed must still load.
        XCTAssertNil(try JSONDecoder().decode(AppSettings.self,from:JSONSerialization.data(withJSONObject:json)).iconColor)
        settings.validate(); XCTAssertEqual(settings.iconColor,"Sage")
        settings.iconColor = "Mauve"; settings.validate(); XCTAssertNil(settings.iconColor)
        settings.iconColor = "Porcelain"; settings.validate(); XCTAssertNil(settings.iconColor)
        for color in AppSettings.iconColors { XCTAssertNotNil(NSImage(contentsOf:root.appendingPathComponent("AppIcons/Board-\(color).icns")),color) }
        // A misspelled accent key would silently fall back to Porcelain's Ink.
        let ink = NSColor(Accent(nil).strong).usingColorSpace(.sRGB)!.redComponent
        for color in AppSettings.iconColors.dropFirst() { XCTAssertNotEqual(NSColor(Accent(color).strong).usingColorSpace(.sRGB)!.redComponent,ink,color) }
    }
    var root: URL { Bundle.main.resourceURL!.appendingPathComponent("Resources") }
    func testEveryAcquiredBankAndTone() throws {
        let processor = try ToneProcessor()
        XCTAssertEqual(SoundProfile.catalog.count,11)
        for profile in SoundProfile.catalog {
            let bank = try PreparedBank.load(profile:profile.id,tone:0,root:root,processor:processor)
            XCTAssertTrue(bank.normalization.isFinite)
            for key in KeyGeometry.keys().map(\.id) {
                XCTAssertNotNil(bank.sample(key:key,down:true))
                XCTAssertEqual(bank.sample(key:key,down:false) != nil,profile.hasReleaseSamples)
            }
            if profile.id == "typewriter" {
                let variants = PreparedBank.options(in:bank.samples,key:0,down:true)
                XCTAssertEqual(variants.count,4)
                for clip in variants {
                    let values = UnsafeBufferPointer(start:clip.floatChannelData![0],count:Int(clip.frameLength))
                    XCTAssertGreaterThan(values.map { abs($0) }.max() ?? 0,0.01)
                    XCTAssertLessThan(Double(clip.frameLength)/clip.format.sampleRate,1)
                }
            }
        }
        let bank = try PreparedBank.load(profile:"alpaca",tone:0.8,root:root,processor:processor)
        for buffer in bank.samples.values { for i in 0..<Int(buffer.frameLength) { XCTAssertTrue(buffer.floatChannelData![0][i].isFinite) } }
        var association = PressReleaseStore<PreparedBank>()
        association.remember(bank,key:49)
        let heldBank = bank
        let anotherBank = try PreparedBank.load(profile:"cream",tone:0,root:root,processor:processor)
        XCTAssertEqual(heldBank.profile,"alpaca"); XCTAssertEqual(anotherBank.profile,"cream")
        XCTAssertTrue(association.release(key:49) === heldBank)
        XCTAssertNil(association.release(key:49))
        association.remember(anotherBank,key:0); association.clear(); XCTAssertNil(association.release(key:0))
    }
    func testDecodedSizeIsBoundedBeforeAllocation() throws {
        // 29 s of eight-channel 96 kHz Apple Lossless silence: about 120 KB on disk, 85 MB once decoded.
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString+".caf")
        defer { try? FileManager.default.removeItem(at:url) }
        let layout = AVAudioChannelLayout(layoutTag:kAudioChannelLayoutTag_DiscreteInOrder | 8)!
        let file = try AVAudioFile(forWriting:url,settings:[AVFormatIDKey:kAudioFormatAppleLossless,AVSampleRateKey:96000,AVNumberOfChannelsKey:8,AVEncoderBitDepthHintKey:16,AVChannelLayoutKey:Data(bytes:layout.layout,count:MemoryLayout<AudioChannelLayout>.size)])
        let second = AVAudioPCMBuffer(pcmFormat:AVAudioFormat(standardFormatWithSampleRate:96000,channelLayout:layout),frameCapacity:96000)!
        second.frameLength = second.frameCapacity
        for _ in 0..<29 { try file.write(from:second) }
        file.close()
        XCTAssertLessThan(try XCTUnwrap(url.resourceValues(forKeys:[.fileSizeKey]).fileSize),AudioFiles.maxFileSize)
        XCTAssertThrowsError(try AudioFiles.decode(url,imported:true)) { XCTAssertEqual(($0 as? AudioValidationError)?.message,"Audio is too large once decoded (64 MB limit).") }
    }
    func testImportsAreValidatedBeforeReplacement() throws {
        let temp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at:temp,withIntermediateDirectories:true)
        let invalid = temp.appendingPathComponent("invalid.wav"); try Data("not audio".utf8).write(to:invalid)
        let source = root.appendingPathComponent("Audio/alpaca/press/SPACE.mp3")
        XCTAssertThrowsError(try AudioFiles.importPair(press:source,release:invalid,name:"bad",root:temp.appendingPathComponent("imports")))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath:temp.appendingPathComponent("imports").path),[])
        let result = try AudioFiles.importPair(press:source,release:nil,name:"Space",root:temp)
        XCTAssertNotNil(try AudioFiles.decode(temp.appendingPathComponent(result.press)))
        let imported = try PreparedBank.imported(result,root:temp)
        XCTAssertNotNil(imported.sample(key:1000,down:true))
        XCTAssertNil(imported.sample(key:1000,down:false))
        let generic = imported.sample(key:0,down:true)!
        let special = try AudioFiles.decode(root.appendingPathComponent("Audio/alpaca/press/ENTER.mp3"))
        let grouped = PreparedBank(profile:"recording-fixture",samples:["press/GENERIC_1":generic,"press/TAB_1":special,"release/GENERIC_1":generic],normalization:1)
        XCTAssertTrue(grouped.sample(key:48,down:true) === special)
        XCTAssertTrue(grouped.sample(key:56,down:false) === generic)
        let tooLong = temp.appendingPathComponent("long.wav")
        let file = try AVAudioFile(forWriting:tooLong,settings:AudioFiles.format.settings)
        let buffer = AVAudioPCMBuffer(pcmFormat:AudioFiles.format,frameCapacity:48000*31)!
        buffer.frameLength = buffer.frameCapacity
        try file.write(from:buffer)
        XCTAssertThrowsError(try AudioFiles.decode(tooLong,imported:true))
    }
    func testImportKeepsOnlyTheValidatedCopies() throws {
        let temp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString), imports = temp.appendingPathComponent("imports")
        try FileManager.default.createDirectory(at:temp,withIntermediateDirectories:true)
        defer { try? FileManager.default.removeItem(at:temp) }
        let valid = root.appendingPathComponent("Audio/alpaca/press/SPACE.mp3"), source = temp.appendingPathComponent("swapped.mp3")
        // Swapped for junk after the copy: the import keeps the valid bytes it checked.
        try FileManager.default.copyItem(at:valid,to:source)
        let kept = try AudioFiles.importPair(press:source,release:nil,name:"Swapped",root:imports) { try Data("not audio".utf8).write(to:source) }
        XCTAssertEqual(try Data(contentsOf:imports.appendingPathComponent(kept.press)),try Data(contentsOf:valid))
        // Swapped back to valid audio after the copy: the junk copy is what gets checked, so the import fails.
        XCTAssertThrowsError(try AudioFiles.importPair(press:source,release:nil,name:"Swapped",root:imports) { try FileManager.default.removeItem(at:source); try FileManager.default.copyItem(at:valid,to:source) })
        // The second copy fails (missing, then over 25 MB): the press copy goes too.
        XCTAssertThrowsError(try AudioFiles.importPair(press:valid,release:temp.appendingPathComponent("missing.wav"),name:"Pair",root:imports))
        let huge = temp.appendingPathComponent("huge.wav")
        XCTAssertTrue(FileManager.default.createFile(atPath:huge.path,contents:nil))
        let handle = try FileHandle(forWritingTo:huge); try handle.truncate(atOffset:UInt64(AudioFiles.maxFileSize+1)); try handle.close()
        XCTAssertThrowsError(try AudioFiles.importPair(press:valid,release:huge,name:"Pair",root:imports))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath:imports.path),[kept.press])
    }
    func testAIKeyMappingShiftReturnAndIndent() {
        // Capitals and symbols hold Shift; a new line is Return; four leading spaces are one Tab.
        let downs = AITyping.plan("Hi(\n    x)",speed:1,flourish:false).filter(\.down)
        XCTAssertEqual(downs.map(\.key),[56,4,34,56,25,36,48,7,56,29])
        XCTAssertEqual(downs.map { $0.modifiers & CGEventFlags.maskShift.rawValue != 0 },[true,true,false,true,true,false,false,false,true,true])
        XCTAssertEqual(AITyping.keyText("      a\r\n\tb"),"\t  a\n\tb")
        let printable = String((32...126).map { Character(UnicodeScalar($0)!) })
        XCTAssertTrue(printable.allSatisfy { AITyping.keys[$0] != nil })
        let all = AITyping.plan(printable,speed:1,cap:100,flourish:false)
        XCTAssertEqual(all.filter(\.down).count,all.filter { !$0.down }.count) // every press is released
    }
    func testAIPacingAndEditCap() {
        var rng = SeededRandom(state:7)
        let text = "word next, more.\nline", gap = AITyping.gap(0.5)
        let downs = AITyping.plan(text,speed:0.5,flourish:false,using:&rng).filter(\.down)
        XCTAssertEqual(downs.count,text.count)
        let previous = [Character("x")] + Array(text.dropLast())
        func leads(_ after: (Character) -> Bool) -> [Double] { zip(previous,downs).filter { after($0.0) }.map { $0.1.delay/gap } }
        let inWord = leads { $0.isLetter }, word = leads { $0 == " " }, punctuation = leads { ",.".contains($0) }, line = leads { $0 == "\n" }
        XCTAssertGreaterThanOrEqual(inWord.min()!,0.6)
        XCTAssertLessThan(inWord.max()!,word.min()!); XCTAssertLessThan(word.max()!,punctuation.min()!); XCTAssertLessThan(punctuation.max()!,line.min()!)
        // A long edit stops inside the 10 s cap and still ends with ⌘S; a faster speed types more of it.
        let long = String(repeating:"let value = compute(input) // keep going\n",count:200)
        for speed in [0.0,0.5,1.0] {
            let strokes = AITyping.plan(long,speed:speed,using:&rng), total = strokes.reduce(0) { $0+$1.delay }
            XCTAssertLessThanOrEqual(total,10); XCTAssertGreaterThan(total,8.5)
            XCTAssertEqual(strokes.suffix(4).map(\.key),[55,1,1,55])
        }
        XCTAssertGreaterThan(AITyping.plan(long,speed:1,using:&rng).filter(\.down).count,AITyping.plan(long,speed:0,using:&rng).filter(\.down).count*3)
        XCTAssertEqual(AITyping.plan("ok",speed:0.5,using:&rng).filter(\.down).map(\.key),[31,40,55,1]) // a short edit is typed whole
    }
    func testAIQueueKeepsOrderAndOnlyTheNewest() {
        var queue = AIQueue()
        for text in ["one","two","three","four"] { queue.push(text) }
        XCTAssertEqual([queue.pop(),queue.pop(),queue.pop(),queue.pop()],["two","three","four",nil])
    }
    func testAIModeCannotPostEvents() throws {
        // AI mode only feeds Board's own pipeline. The image holding its code (the app, Debug's Board.debug.dylib, or a
        // logic-test bundle) must import no API that posts events into other apps.
        let image = try XCTUnwrap(class_getImageName(AIMode.self).map { String(cString:$0) })
        let nm = Process(), out = Pipe()
        nm.executableURL = URL(fileURLWithPath:"/usr/bin/nm"); nm.arguments = ["-u",image]; nm.standardOutput = out
        try nm.run()
        let symbols = String(decoding:out.fileHandleForReading.readDataToEndOfFile(),as:UTF8.self).split(separator:"\n").map(String.init)
        nm.waitUntilExit()
        XCTAssertTrue(symbols.contains("_CGEventTapCreate"),"nm listed no imports for \(image)") // Board's listen-only tap
        let posting: Set = ["_CGEventPost","_CGEventPostToPid","_CGEventPostToPSN","_CGEventTapPostEvent","_CGPostKeyboardEvent","_CGPostMouseEvent","_AXUIElementPostKeyboardEvent"]
        XCTAssertEqual(symbols.filter(posting.contains),[])
    }
    @MainActor func testAIModeTypesAQueuedEditOnce() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString), marker = directory.appendingPathComponent("listening")
        defer { try? FileManager.default.removeItem(at:directory) }
        let ai = AIMode(directory:directory,watchAgents:false), saved = expectation(description:"the edit ends with ⌘S")
        var downs: [Int] = []
        ai.onEvent = { event in
            guard event.transition == .press else { return }
            downs.append(event.key)
            if event.key == 1, event.modifiers & CGEventFlags.maskCommand.rawValue != 0 { saved.fulfill() }
        }
        ai.configure(enabled:true,speed:1,folder:nil)
        XCTAssertEqual(try String(contentsOf:marker,encoding:.utf8),String(getpid()))
        try Data("ok".utf8).write(to:directory.appendingPathComponent("1-1.txt")) // what board-ai-hook drops in
        wait(for:[saved],timeout:5)
        XCTAssertEqual(downs,[31,40,55,1])
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath:directory.path),["listening"]) // read once, then deleted
        ai.stop()
        XCTAssertFalse(FileManager.default.fileExists(atPath:marker.path))
    }
    func testAIHookInstallAndRemoveKeepEverythingElse() throws {
        let temp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString), url = temp.appendingPathComponent(".claude/settings.json")
        defer { try? FileManager.default.removeItem(at:temp) }
        let script = "/Applications/Board.app/Contents/Resources/board-ai-hook"
        let board: [String:Any] = ["matcher":"Write|Edit","hooks":[["type":"command","command":script,"args":[String](),"async":true]]]
        // No settings file yet: installing creates one.
        try AIHook.update(url) { try AIHook.installing(script,for:.claude,into:$0) }
        XCTAssertEqual(AIHook.installed(in:try AIHook.read(url)),script)
        // Settings with other hooks and keys: installing twice adds one entry and keeps the rest, the file's permissions, and a backup.
        let other: [String:Any] = ["permissions":["allow":["Bash(ls)"]],"hooks":["PostToolUse":[["matcher":"","hooks":[["type":"command","command":"echo other","timeout":5]]]],"SessionEnd":[["hooks":[["type":"command","command":"echo end"]]]]]]
        try JSONSerialization.data(withJSONObject:other).write(to:url)
        try FileManager.default.setAttributes([.posixPermissions:0o600],ofItemAtPath:url.path)
        for _ in 0..<2 { try AIHook.update(url) { try AIHook.installing(script,for:.claude,into:$0) } }
        let post = try XCTUnwrap((try AIHook.read(url)["hooks"] as? [String:Any])?["PostToolUse"] as? [[String:Any]])
        XCTAssertEqual(post.map { NSDictionary(dictionary:$0) },[NSDictionary(dictionary:((other["hooks"] as! [String:Any])["PostToolUse"] as! [[String:Any]])[0]),NSDictionary(dictionary:board)])
        XCTAssertEqual(try FileManager.default.attributesOfItem(atPath:url.path)[.posixPermissions] as? NSNumber,0o600)
        XCTAssertEqual(AIHook.installed(in:try AIHook.read(url.appendingPathExtension("bak-board"))),script)
        // Removing gives back the original settings exactly.
        try AIHook.update(url) { try AIHook.removing(from:$0) }
        XCTAssertEqual(NSDictionary(dictionary:try AIHook.read(url)),NSDictionary(dictionary:other))
        // A hook someone added to Board's entry by hand survives removal.
        var shared = try AIHook.installing(script,for:.claude,into:other), hooks = shared["hooks"] as! [String:Any], entries = hooks["PostToolUse"] as! [[String:Any]]
        entries[1]["hooks"] = (entries[1]["hooks"] as! [Any]) + [["type":"command","command":"echo also"]]
        hooks["PostToolUse"] = entries; shared["hooks"] = hooks
        let kept = try AIHook.removing(from:shared), keptEntries = (kept["hooks"] as! [String:Any])["PostToolUse"] as! [[String:Any]]
        XCTAssertNil(AIHook.installed(in:kept))
        XCTAssertEqual(((keptEntries[1]["hooks"] as! [[String:Any]]).map { $0["command"] as? String }),["echo also"])
        // A file Board can't parse, or a hooks setting of another shape, is refused and left as it was.
        try Data("{ not json".utf8).write(to:url)
        XCTAssertThrowsError(try AIHook.update(url) { try AIHook.installing(script,for:.claude,into:$0) })
        XCTAssertEqual(try String(contentsOf:url,encoding:.utf8),"{ not json")
        XCTAssertThrowsError(try AIHook.installing(script,for:.claude,into:["hooks":["PostToolUse":"unexpected"]]))
        // Codex: its hooks.json keeps its own hooks; Board's entry quotes the path because Codex runs commands through a shell.
        let codex = temp.appendingPathComponent(".codex/hooks.json")
        let codexOther: [String:Any] = ["hooks":["PreToolUse":[["matcher":"Bash","hooks":[["type":"command","command":"/usr/local/bin/guard"]]]]]]
        try FileManager.default.createDirectory(at:codex.deletingLastPathComponent(),withIntermediateDirectories:true)
        try JSONSerialization.data(withJSONObject:codexOther).write(to:codex)
        try AIHook.update(codex) { try AIHook.installing(script,for:.codex,into:$0) }
        let codexSettings = try AIHook.read(codex), codexPost = try XCTUnwrap((codexSettings["hooks"] as? [String:Any])?["PostToolUse"] as? [[String:Any]])
        XCTAssertEqual(codexPost.map { NSDictionary(dictionary:$0) },[NSDictionary(dictionary:["matcher":"Write|Edit","hooks":[["type":"command","command":"'\(script)'","async":true,"timeout":10]]])])
        XCTAssertTrue(AIHook.runs(AIHook.installed(in:codexSettings),script))
        try AIHook.update(codex) { try AIHook.removing(from:$0) }
        XCTAssertEqual(NSDictionary(dictionary:try AIHook.read(codex)),NSDictionary(dictionary:codexOther))
        XCTAssertEqual(AIHook.quoted("/a/it's"),"'/a/it'\\''s'")
    }
    func testOfflineSpatialOutputAndProtection() throws {
        let left = try render(x:-1), right = try render(x:1), crowded = try render(x:0,voices:32)
        XCTAssertGreaterThan(left.0,left.1*1.2)
        XCTAssertGreaterThan(right.1,right.0*1.2)
        XCTAssertLessThanOrEqual(crowded.2,1.01)
        XCTAssertGreaterThan(crowded.2,0.01)
    }
    private func render(x:Float,voices:Int = 1) throws -> (Double,Double,Float) {
        let engine = AVAudioEngine(), environment = AVAudioEnvironmentNode()
        let format = AVAudioFormat(standardFormatWithSampleRate:48000,channels:2)!
        engine.attach(environment); environment.distanceAttenuationParameters.rolloffFactor = 0
        let limiter = AVAudioUnitEffect(audioComponentDescription:.init(componentType:kAudioUnitType_Effect,componentSubType:kAudioUnitSubType_PeakLimiter,componentManufacturer:kAudioUnitManufacturer_Apple,componentFlags:0,componentFlagsMask:0))
        engine.attach(limiter); engine.connect(environment,to:limiter,format:format); engine.connect(limiter,to:engine.mainMixerNode,format:format)
        let sample = try AudioFiles.decode(root.appendingPathComponent("Audio/alpaca/press/GENERIC_R2.mp3"))
        var players: [AVAudioPlayerNode] = []
        for _ in 0..<voices { let player = AVAudioPlayerNode(); engine.attach(player); engine.connect(player,to:environment,format:AudioFiles.format); player.position = AVAudio3DPoint(x:x,y:0,z:-1); player.renderingAlgorithm = .equalPowerPanning; player.scheduleBuffer(sample); players.append(player) }
        try engine.enableManualRenderingMode(.offline,format:format,maximumFrameCount:1024); try engine.start(); players.forEach { $0.play() }
        defer { engine.stop() }
        let buffer = AVAudioPCMBuffer(pcmFormat:format,frameCapacity:1024)!
        var energies = [0.0,0.0], peak: Float = 0
        for _ in 0..<96 {
            let status = try engine.renderOffline(1024,to:buffer); XCTAssertEqual(status,.success)
            for channel in 0..<2 { for i in 0..<Int(buffer.frameLength) { let value = buffer.floatChannelData![channel][i]; XCTAssertTrue(value.isFinite); peak = max(peak,abs(value)); energies[channel] += Double(value*value) } }
        }
        return (energies[0],energies[1],peak)
    }
}

/// SplitMix64, so pacing checks are repeatable.
private struct SeededRandom: RandomNumberGenerator {
    var state: UInt64
    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state; z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9; z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}
