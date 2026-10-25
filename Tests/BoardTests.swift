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
    func testImportsAreValidatedBeforeReplacement() throws {
        let temp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at:temp,withIntermediateDirectories:true)
        let invalid = temp.appendingPathComponent("invalid.wav"); try Data("not audio".utf8).write(to:invalid)
        let source = root.appendingPathComponent("Audio/alpaca/press/SPACE.mp3")
        XCTAssertThrowsError(try AudioFiles.importPair(press:source,release:invalid,name:"bad",root:temp.appendingPathComponent("imports")))
        XCTAssertFalse(FileManager.default.fileExists(atPath:temp.appendingPathComponent("imports").path))
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
