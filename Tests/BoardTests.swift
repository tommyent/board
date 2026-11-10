import XCTest
import AppKit
import AVFoundation
import AudioToolbox
@testable import Board

final class BoardTests: XCTestCase {
    func testVisualizerTrailIdentityCapacityAndRepeatCoalescing() {
        var trail = VisualizerTrail()
        func press(_ key: Int, _ time: Double, _ modifiers: UInt64 = 0) -> PhysicalInputEvent {
            .init(key:key,transition:.press,modifiers:modifiers,timestamp:time)
        }
        trail.press(press(51,0))
        let repeatedID = trail.strokes[0].id
        trail.press(press(51,0.1)); trail.press(press(51,0.2))
        XCTAssertEqual(trail.strokes.count,1)
        XCTAssertEqual(trail.strokes[0].id,repeatedID)
        XCTAssertEqual(trail.strokes[0].label,"⌫ ×3")
        trail.press(press(51,0.3,CGEventFlags.maskCommand.rawValue))
        XCTAssertEqual(trail.strokes.count,2,"A different chord must not coalesce")
        trail.press(press(51,0.7))
        XCTAssertEqual(trail.strokes.count,3,"Separated repeats get their own identity")
        let preservedID = trail.strokes.last!.id
        for key in 0..<14 { trail.press(press(key,0.8+Double(key)*0.01)) }
        XCTAssertEqual(trail.strokes.count,15)
        XCTAssertEqual(trail.strokes.first?.id,preservedID)
        XCTAssertEqual(Set(trail.strokes.map(\.id)).count,15)
        XCTAssertFalse(trail.strokes.contains { $0.id == repeatedID })
        trail.expire(at:3)
        XCTAssertTrue(trail.strokes.isEmpty)
        XCTAssertNil(trail.nextExpiry)
    }
    func testVisualizerAfterglowExpiresAndRepressCancelsIt() {
        var trail = VisualizerTrail()
        trail.release(0,at:0); trail.release(1,at:0.5)
        trail.expire(at:1.4)
        XCTAssertNil(trail.releases[0]); XCTAssertEqual(trail.releases[1],0.5)
        trail.press(.init(key:1,transition:.press,modifiers:0,timestamp:1.5))
        XCTAssertNil(trail.releases[1])
        trail.expire(at:3.5)
        XCTAssertNil(trail.nextExpiry)
    }
    func testVisualizerMovementIsIndependentOfPlacement() {
        var settings = VisualizerSettings()
        settings.style = "Keystrokes"
        for motion in VisualizerMotion.allCases {
            settings.motion = motion.rawValue
            for placement in ["Follow Cursor","Pin to Screen","Random"] {
                settings.placement = placement
                XCTAssertEqual(settings.movement,motion)
                XCTAssertEqual(settings.tailDuration,1.9)
                XCTAssertGreaterThanOrEqual(settings.panelSize.width,540)
            }
        }
        XCTAssertLessThan(VisualizerMotion.pop.arrivalScale,1)
        XCTAssertGreaterThan(VisualizerMotion.pulse.arrivalScale,1)
        XCTAssertGreaterThan(VisualizerMotion.slide.arrivalX,0)
        XCTAssertGreaterThan(VisualizerMotion.bounce.arrivalY,0)
        settings.style = "Keyboard"
        XCTAssertEqual(settings.tailDuration,1.4)
    }
    @MainActor func testVisualizerExpiryAndSecureReset() async throws {
        let app = AppState(defaults:UserDefaults(suiteName:"com.tommyent.Board.tests.visualizer")!)
        app.settings.visualizer.enabled = true
        app.settings.visualizer.style = "Keystrokes"
        var presentations = 0
        app.onVisualEvent = { _ in presentations += 1 }
        let time = ProcessInfo.processInfo.systemUptime
        app.visualize(.init(key:0,transition:.press,modifiers:0,timestamp:time))
        app.visualize(.init(key:0,transition:.release,modifiers:0,timestamp:time+0.01))
        XCTAssertTrue(app.heldKeys.isEmpty)
        XCTAssertEqual(app.visualTrail.strokes.count,1)
        XCTAssertNotNil(app.visualTrail.releases[0])
        XCTAssertEqual(presentations,1,"A release must not reopen a dismissed ribbon")
        try await Task.sleep(for:.seconds(2.1))
        XCTAssertTrue(app.visualTrail.strokes.isEmpty)
        XCTAssertTrue(app.visualTrail.releases.isEmpty)
        app.visualize(.init(key:1,transition:.press,modifiers:0,timestamp:ProcessInfo.processInfo.systemUptime))
        var resets = 0
        app.onVisualReset = { resets += 1 }
        app.clearVisuals() // InputMonitor's Secure Input reset uses this path.
        XCTAssertTrue(app.heldKeys.isEmpty)
        XCTAssertEqual(app.visualTrail,VisualizerTrail())
        XCTAssertEqual(app.combo.count,0)
        XCTAssertEqual(resets,1)
        try await Task.sleep(for:.seconds(2))
        XCTAssertEqual(app.visualTrail,VisualizerTrail(),"Cancelled expiry must not resurrect old input")
    }
    func testLaunchOpensSettingsOnlyForOnboardingOrMissingPermission() {
        XCTAssertFalse(AppDelegate.opensSettingsAtLaunch(onboardingComplete:true,inputAllowed:true),"A normal launch opens no window")
        XCTAssertTrue(AppDelegate.opensSettingsAtLaunch(onboardingComplete:false,inputAllowed:true))
        XCTAssertTrue(AppDelegate.opensSettingsAtLaunch(onboardingComplete:true,inputAllowed:false))
        XCTAssertTrue(AppDelegate.opensSettingsAtLaunch(onboardingComplete:false,inputAllowed:false))
    }
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
        app.heldKeys = [1]
        app.visualTrail.press(.init(key:1,transition:.press,modifiers:CGEventFlags.maskCommand.rawValue,timestamp:ProcessInfo.processInfo.systemUptime))
        NSWorkspace.shared.notificationCenter.post(name:NSWorkspace.activeSpaceDidChangeNotification,object:nil)
        RunLoop.main.run(until:Date()+0.1)
        XCTAssertTrue(app.visualTrail.strokes.isEmpty)
        XCTAssertTrue(app.heldKeys.isEmpty)
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
        let downs = AITyping.plan("Hi(\n    x)",speed:1).filter(\.down)
        XCTAssertEqual(downs.map(\.key),[56,4,34,56,25,36,48,7,56,29])
        XCTAssertEqual(downs.map { $0.modifiers & CGEventFlags.maskShift.rawValue != 0 },[true,true,false,true,true,false,false,false,true,true])
        XCTAssertEqual(AITyping.keyText("      a\r\n\tb"),"\t  a\n\tb")
        let printable = String((32...126).map { Character(UnicodeScalar($0)!) })
        XCTAssertTrue(printable.allSatisfy { AITyping.keys[$0] != nil })
        let all = AITyping.plan(printable,speed:1,cap:100)
        XCTAssertEqual(all.filter(\.down).count,all.filter { !$0.down }.count) // every press is released
    }
    func testAIPacingAndCap() {
        var rng = SeededRandom(state:7)
        let text = "word next, more.\nline", gap = AITyping.gap(0.5)
        let downs = AITyping.plan(text,speed:0.5,using:&rng).filter(\.down)
        XCTAssertEqual(downs.count,text.count)
        let previous = [Character("x")] + Array(text.dropLast())
        func leads(_ after: (Character) -> Bool) -> [Double] { zip(previous,downs).filter { after($0.0) }.map { $0.1.delay/gap } }
        let inWord = leads { $0.isLetter }, word = leads { $0 == " " }, punctuation = leads { ",.".contains($0) }, line = leads { $0 == "\n" }
        XCTAssertGreaterThanOrEqual(inWord.min()!,0.6)
        XCTAssertLessThan(inWord.max()!,word.min()!); XCTAssertLessThan(word.max()!,punctuation.min()!); XCTAssertLessThan(punctuation.max()!,line.min()!)
        // A long chunk stops inside the 10 s cap, with every key released; a faster speed types more of it.
        let long = String(repeating:"let value = compute(input) // keep going\n",count:200)
        for speed in [0.0,0.5,1.0] {
            let strokes = AITyping.plan(long,speed:speed,using:&rng), total = strokes.reduce(0) { $0+$1.delay }
            XCTAssertLessThanOrEqual(total,10); XCTAssertGreaterThan(total,8.5)
            XCTAssertFalse(strokes.last!.down)
        }
        XCTAssertGreaterThan(AITyping.plan(long,speed:1,using:&rng).filter(\.down).count,AITyping.plan(long,speed:0,using:&rng).filter(\.down).count*3)
        XCTAssertEqual(AITyping.plan("ok",speed:0.5,using:&rng).filter(\.down).map(\.key),[31,40]) // short text is typed whole
    }
    @MainActor func testJokeModeCodesAlongOnlyWhileAnAgentWorks() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
        defer { try? FileManager.default.removeItem(at:folder) }
        try Data("let answer = 42\nprint(answer)".utf8).write(to:folder.appendingPathComponent("main.swift")) // no blank line to start a chunk on
        let ai = AIMode(watchAgents:false), typing = expectation(description:"joke typing reaches Board's pipeline")
        var presses = 0, statuses: [String] = []
        ai.onStatus = { statuses.append($0) }
        ai.onEvent = { event in if event.transition == .press { presses += 1; if presses == 3 { typing.fulfill() } } }
        ai.configure(enabled:true,speed:1,folder:folder.path)
        XCTAssertEqual(statuses,["Waiting for a coding agent to work in Rex"])
        ai.agents.working = true
        wait(for:[typing],timeout:6) // the first key waits 1–3 s
        XCTAssertEqual(statuses.last,"Coding along from source files while an agent works")
        ai.stop()
        let stopped = presses
        RunLoop.main.run(until:Date().addingTimeInterval(0.5))
        XCTAssertEqual(presses,stopped) // nothing typed after AI mode is off
        XCTAssertEqual(statuses.last,"Off")
    }
    @MainActor func testJokeTypingStopsTheMomentTheAgentStops() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
        defer { try? FileManager.default.removeItem(at:folder) }
        let source = Array(repeating:"let value = compute(input) // keep going",count:20).joined(separator:"\n") // a burst of many seconds
        try Data(source.utf8).write(to:folder.appendingPathComponent("main.swift"))
        let ai = AIMode(watchAgents:false), cut = expectation(description:"the agent stops mid-burst")
        var down = Set<Int>(), heldAtCut = Set<Int>(), presses = 0, stopped = false, statuses: [String] = []
        ai.onStatus = { statuses.append($0) }
        ai.onEvent = { event in
            if event.transition == .press { down.insert(event.key); presses += 1 } else { down.remove(event.key) }
            guard event.transition == .press, presses == 3, !stopped else { return }
            stopped = true
            // Rex's update arrives on the main queue, as AgentWatch delivers it, while this key is still down.
            DispatchQueue.main.async { heldAtCut = down; ai.agents.working = false; cut.fulfill() }
        }
        ai.configure(enabled:true,speed:0,folder:folder.path)
        ai.agents.working = true
        wait(for:[cut],timeout:6) // the first key waits 1–3 s
        XCTAssertFalse(heldAtCut.isEmpty) // a key was down when the agent stopped
        XCTAssertEqual(down,[]) // and it was released at once: no stuck key or sound
        let typed = presses
        RunLoop.main.run(until:Date().addingTimeInterval(0.5))
        XCTAssertEqual(presses,typed) // the rest of the burst is dropped
        XCTAssertEqual(statuses.last,"Waiting for a coding agent to work in Rex")
        ai.stop()
    }
    @MainActor func testAIModeSaysWhenItNeedsRex() throws {
        // A stand-in rex: the real one exits 4 when no server runs and --autostart=false; a running Rex lists its sessions.
        let temp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at:temp,withIntermediateDirectories:true)
        defer { try? FileManager.default.removeItem(at:temp) }
        func rex(_ body: String) throws -> URL {
            let url = temp.appendingPathComponent(UUID().uuidString)
            try Data("#!/bin/sh\n\(body)\n".utf8).write(to:url)
            try FileManager.default.setAttributes([.posixPermissions:0o755],ofItemAtPath:url.path)
            return url
        }
        XCTAssertNil(AgentWatch.snapshot(try rex("exit 4")))
        XCTAssertEqual(AgentWatch.snapshot(try rex("echo '{\"sessions\":[]}'")),[])
        // The status line tells "no agent working" from "can't see agents".
        let ai = AIMode(watchAgents:false)
        var statuses: [String] = []
        ai.onStatus = { statuses.append($0) }
        ai.configure(enabled:true,speed:0.35,folder:nil)
        ai.agents.rexReachable = false
        ai.agents.rexReachable = true
        ai.stop()
        XCTAssertEqual(statuses,["Waiting for a coding agent to work in Rex","Needs Rex to see when your agents are working","Waiting for a coding agent to work in Rex","Off"])
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
