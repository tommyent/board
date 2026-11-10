import XCTest
@testable import Board

final class SettingsCompatibilityTests: XCTestCase {
    func testHistoricalDefaultsDecode() throws {
        let fixtures = URL(fileURLWithPath:#filePath).deletingLastPathComponent().appendingPathComponent("Fixtures")
        for version in ["0.4.1","0.4.7"] {
            let data = try Data(contentsOf:fixtures.appendingPathComponent("settings-\(version).json"))
            XCTAssertEqual(try JSONDecoder().decode(AppSettings.self,from:data),AppSettings(),version)
        }
    }
    func testEveryMissingSettingsFieldUsesItsDefault() throws {
        let encoder = JSONEncoder(), decoder = JSONDecoder()
        func check<T: Codable & Equatable>(_ value: T) throws {
            let json = try XCTUnwrap(JSONSerialization.jsonObject(with:encoder.encode(value)) as? [String:Any])
            for key in json.keys {
                var older = json; older[key] = nil
                XCTAssertEqual(try decoder.decode(T.self,from:JSONSerialization.data(withJSONObject:older)),value,key)
            }
            XCTAssertEqual(try decoder.decode(T.self,from:Data("{}".utf8)),value)
        }
        try check(AppSettings()); try check(SoundConfiguration()); try check(VisualizerSettings())
    }
    func testEveryStoredSettingsPropertyIsSaved() throws {
        // The three settings types list their coding keys by hand. A property left out of a list would silently
        // stop being saved and loaded; Mirror sees every stored property, so a forgotten one fails here.
        func check<T: Encodable>(_ value: T) throws {
            let saved = Set(try XCTUnwrap(JSONSerialization.jsonObject(with:JSONEncoder().encode(value)) as? [String:Any]).keys)
            XCTAssertEqual(saved,Set(Mirror(reflecting:value).children.compactMap(\.label)),String(describing:T.self))
        }
        var settings = AppSettings()   // optionals are only encoded when set
        settings.iconColor = "Sage"; settings.aiMode = true; settings.aiSpeed = 0.2; settings.aiFolder = "/tmp/code"
        try check(settings); try check(settings.sound); try check(settings.visualizer)
    }
    func testMissingNestedFieldsKeepOtherSavedChoices() throws {
        var expected = AppSettings()
        expected.layout = "ISO"; expected.showDock = true; expected.onboardingComplete = true
        expected.sound.profile = "cream"; expected.sound.volume = 0.12
        expected.sound.overrides[0] = KeyOverride(profile:"topre",volume:0.24)
        expected.visualizer.enabled = true; expected.visualizer.style = "Keystrokes"
        expected.presets = [SoundPreset(name:"Quiet",sound:expected.sound)]
        expected.imports = [ImportedSound(id:"test",name:"Test",press:"test.wav")]
        expected.iconColor = "Sage"; expected.aiMode = true; expected.aiSpeed = 0.2; expected.aiFolder = "/tmp/code"
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with:JSONEncoder().encode(expected)) as? [String:Any])
        json["gestureTaps"] = nil
        var sound = try XCTUnwrap(json["sound"] as? [String:Any]); sound["width"] = nil; json["sound"] = sound
        var visualizer = try XCTUnwrap(json["visualizer"] as? [String:Any]); visualizer["flow"] = nil; json["visualizer"] = visualizer
        var presets = try XCTUnwrap(json["presets"] as? [[String:Any]])
        var presetSound = try XCTUnwrap(presets[0]["sound"] as? [String:Any]); presetSound["width"] = nil; presets[0]["sound"] = presetSound; json["presets"] = presets
        XCTAssertEqual(try JSONDecoder().decode(AppSettings.self,from:JSONSerialization.data(withJSONObject:json)),expected)
    }
    @MainActor func testUnreadableSettingsAreBackedUpBeforeTheyCanBeOverwritten() throws {
        let suite = "com.tommyent.Board.tests.settings-recovery", defaults = try XCTUnwrap(UserDefaults(suiteName:suite))
        defaults.removePersistentDomain(forName:suite)
        defer { defaults.removePersistentDomain(forName:suite) }
        for bytes in [Data("broken JSON".utf8), Data("{\"sound\":{\"volume\":\"broken\"}}".utf8), Data("{\"version\":2}".utf8)] {
            defaults.set(bytes,forKey:"appSettings.v1")
            let app = AppState(defaults:defaults)
            XCTAssertEqual(app.settings,AppSettings())
            XCTAssertNotNil(app.error)
            XCTAssertEqual(defaults.data(forKey:"appSettings.v1.unreadable"),bytes)
            XCTAssertEqual(defaults.data(forKey:"appSettings.v1"),bytes)
            defaults.set(try JSONEncoder().encode(app.settings),forKey:"appSettings.v1")
            XCTAssertEqual(defaults.data(forKey:"appSettings.v1.unreadable"),bytes)
            XCTAssertNil(AppState(defaults:defaults).error)
        }
    }
}
