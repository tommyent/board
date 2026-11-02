import XCTest
import AppKit
import SwiftUI
@testable import Board

@MainActor final class GamingPracticeTests: XCTestCase {
    private func store() -> UserDefaults {
        let name = "com.tommyent.Board.tests.gaming"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    func testCountdownExcludesTimeAndFocusLossRequiresResume() throws {
        var now = 100.0
        let game = GamingPractice(defaults: store(), automaticallyTicks: false, clock: { now })
        game.selected = true; game.start()
        XCTAssertEqual(game.countdown, 3)
        game.press(.w)
        XCTAssertEqual(game.engine?.actions, 0)
        now = 103; game.tick()
        XCTAssertEqual(game.engine?.elapsed, 0)
        now = 105; game.updateAvailability(active: false, secureInput: false)
        XCTAssertEqual(game.engine?.phase, .paused)
        let actions = game.engine?.actions
        game.press(.w); XCTAssertEqual(game.engine?.actions, actions)
        now = 200; game.updateAvailability(active: true, secureInput: false)
        XCTAssertEqual(game.engine?.phase, .paused)
        game.resume(); now = 201; game.tick()
        XCTAssertEqual(game.engine?.elapsed, 3)
        game.updateAvailability(active: true, secureInput: true)
        game.resume(); game.press(.w)
        XCTAssertEqual(game.engine?.phase, .paused)
        XCTAssertFalse(game.acceptsInput)
        game.reset(); XCTAssertNil(game.engine)
        game.updateAvailability(active: true, secureInput: false); game.start()
        game.pause(); XCTAssertNil(game.countdown); XCTAssertNil(game.engine)
    }

    func testFinishedHistoryIsSummaryOnlySavedOnceAndBestMatchesSettings() throws {
        var now = 0.0
        let defaults = store()
        let game = GamingPractice(defaults: defaults, automaticallyTicks: false, clock: { now })
        game.selected = true; game.drill = .strafeRhythm; game.start()
        now = 3; game.tick()
        for cue in try XCTUnwrap(game.engine?.cues) {
            now = 3+cue.targetAt; game.press(cue.input); game.release(cue.input)
        }
        now = 33; game.tick(); game.tick()
        XCTAssertEqual(game.history.count, 1)
        XCTAssertEqual(game.history.first?.accuracy, 100)
        XCTAssertEqual(game.history.first?.apm, 100)
        XCTAssertNotNil(game.best)
        game.tempo = 120; XCTAssertNil(game.best)
        game.tempo = 100; XCTAssertNotNil(game.best)
        let data = try XCTUnwrap(defaults.data(forKey: "gaming.history.v1"))
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [[String: Any]])
        XCTAssertEqual(Set(try XCTUnwrap(json.first).keys), Set(["id","date","drill","duration","tempo","window","keys","version","median","mad","accuracy","apm","trials","interruptions"]))
        XCTAssertNil(defaults.data(forKey: "practice.history.v1"))
        let reloaded = GamingPractice(defaults: defaults, automaticallyTicks: false)
        XCTAssertEqual(reloaded.history.count, 1)
        game.clearHistory(); XCTAssertNil(defaults.data(forKey: "gaming.history.v1"))
    }

    func testCorruptHistoryIsPreservedUntilExplicitClear() {
        let defaults = store(), bad = Data("private invalid history".utf8)
        defaults.set(bad, forKey: "gaming.history.v1")
        var now = 0.0
        let game = GamingPractice(defaults: defaults, automaticallyTicks: false, clock: { now })
        XCTAssertNotNil(game.historyError)
        game.selected = true; game.start(); now = 3; game.tick(); now = 34; game.tick()
        XCTAssertEqual(defaults.data(forKey: "gaming.history.v1"), bad)
        XCTAssertTrue(game.history.isEmpty)
        game.clearHistory(); XCTAssertNil(game.historyError)
    }

    func testOverlayRestoresOnAndOffWithoutChangingAvailability() {
        let defaults = store()
        let overlay = GamingOverlay(defaults: defaults, presentsWindow: false)
        XCTAssertFalse(overlay.enabled)
        overlay.enabled = true
        XCTAssertTrue(defaults.bool(forKey: "gaming.overlay.enabled"))
        let restored = GamingOverlay(defaults: defaults, presentsWindow: false)
        XCTAssertTrue(restored.enabled)
        XCTAssertFalse(restored.available)
        restored.setAvailable(true)
        restored.setAvailable(false)
        XCTAssertTrue(defaults.bool(forKey: "gaming.overlay.enabled"))
        restored.enabled = false
        XCTAssertFalse(defaults.bool(forKey: "gaming.overlay.enabled"))
        XCTAssertFalse(GamingOverlay(defaults: defaults, presentsWindow: false).enabled)
    }

    func testOverlayOptInHoldExpiryAndSecurityResetStopTimer() {
        var now = 10.0
        let overlay = GamingOverlay(defaults: store(), presentsWindow: false, clock: { now })
        func event(_ key: Int, _ transition: PhysicalInputEvent.Transition) -> PhysicalInputEvent {
            .init(key: key, transition: transition, modifiers: 0, timestamp: now)
        }
        overlay.setAvailable(true); overlay.receive(event(13, .press))
        XCTAssertTrue(overlay.holds.isEmpty)
        overlay.enabled = true; overlay.receive(event(13, .press))
        XCTAssertEqual(overlay.holds[13]?.start, 10)
        now = 11; overlay.receive(event(13, .press))
        XCTAssertEqual(overlay.holds[13]?.start, 10)
        overlay.receive(event(13, .release))
        now = 11.2; overlay.tick(); XCTAssertNotNil(overlay.holds[13])
        now = 11.4; overlay.tick(); XCTAssertTrue(overlay.holds.isEmpty); XCTAssertNil(overlay.timer)
        overlay.receive(event(1000, .press)); overlay.receive(event(12, .press))
        XCTAssertEqual(overlay.holds.count, 1)
        overlay.setAvailable(false); XCTAssertTrue(overlay.holds.isEmpty); XCTAssertNil(overlay.timer)
        overlay.receive(event(1000, .press)); XCTAssertTrue(overlay.holds.isEmpty)
        overlay.setAvailable(true); overlay.receive(event(49, .press))
        overlay.enabled = false; XCTAssertTrue(overlay.holds.isEmpty); XCTAssertNil(overlay.timer)
    }

    func testNativeInputIgnoresRepeatAndPausesOnEscapeAndResponderLoss() throws {
        var now = 0.0
        let game = GamingPractice(defaults: store(), automaticallyTicks: false, clock: { now })
        game.selected = true; game.start(); now = 3; game.tick()
        let view = GamingInputSurface(); view.game = game
        func key(_ code: UInt16, repeatKey: Bool = false, type: NSEvent.EventType = .keyDown) throws -> NSEvent {
            try XCTUnwrap(NSEvent.keyEvent(with: type, location: .zero, modifierFlags: [], timestamp: now,
                                          windowNumber: 0, context: nil, characters: "", charactersIgnoringModifiers: "", isARepeat: repeatKey, keyCode: code))
        }
        view.keyDown(with: try key(13, repeatKey: true)); XCTAssertEqual(game.engine?.actions, 0)
        view.keyDown(with: try key(13)); XCTAssertEqual(game.engine?.actions, 1)
        view.keyDown(with: try key(13)); XCTAssertEqual(game.engine?.actions, 1)
        view.keyUp(with: try key(13, type: .keyUp))
        view.keyDown(with: try key(53)); XCTAssertEqual(game.engine?.phase, .paused)
        game.resume(); _ = view.resignFirstResponder(); XCTAssertEqual(game.engine?.phase, .paused)
        game.resume(); game.selected = false; view.keyDown(with: try key(2)); XCTAssertEqual(game.engine?.actions, 1)
    }

    func testOffscreenGamingRendering() throws {
        let directory = URL(fileURLWithPath: "/private/tmp/board-gaming-artifacts", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let defaults = store(), app = AppState(defaults: store())
        var now = 0.0
        let game = GamingPractice(defaults: defaults, automaticallyTicks: false, clock: { now })
        let typing = PracticeSession(defaults: defaults)
        game.selected = true
        func capture(_ name: String, width: CGFloat = 920, height: CGFloat = 780, dark: Bool = false) throws {
            let window = NSWindow(contentRect: NSRect(x: -10_000, y: -10_000, width: width, height: height), styleMask: [.titled], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false; window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
            let host = NSHostingView(rootView: GamingPracticeRoot(session: typing, game: game, app: app, checkAvailability: {})
                .frame(width: width, height: height))
            window.contentView = host; host.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.1))
            let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
            host.cacheDisplay(in: host.bounds, to: bitmap)
            let data = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
            XCTAssertGreaterThan(data.count, 5_000)
            try data.write(to: directory.appendingPathComponent(name+".png"))
            XCTAssertFalse(window.isVisible); window.contentView = nil; window.close()
        }
        try capture("reaction-ready")
        game.start(); try capture("countdown")
        now = 3; game.tick()
        now = 3 + (try XCTUnwrap(game.engine?.cues.first?.targetAt)) + 0.1; game.tick()
        try capture("reaction-cue")
        game.updateAvailability(active: true, secureInput: true); try capture("secure-paused", dark: true)
        game.updateAvailability(active: true, secureInput: false)
        for drill in [GamingDrill.strafeRhythm, .keyReversal, .holdTap] {
            game.reset(); game.drill = drill; now = 0; game.start(); now = 3; game.tick()
            now = 3.35; game.tick(); try capture(drill.rawValue)
        }
        try capture("minimum-dark", width: 760, height: 640, dark: true)
        now = 34; game.tick(); try capture("finished")
        game.reset(); game.drill = .keyReversal; now = 0; game.start(); now = 3; game.tick()
        game.press(.a); now = 3.3; game.release(.a); now = 3.32; game.press(.d)
        XCTAssertEqual(game.engine?.lastFeedback, .hit)
        try capture("key-reversal-hold-between-beats")
    }

    func testNativeAccessibilityStartAndPauseActions() throws {
        let defaults = store(), app = AppState(defaults: store())
        let game = GamingPractice(defaults: defaults, automaticallyTicks: false)
        game.selected = true
        let window = NSWindow(contentRect: NSRect(x: -10_000, y: -10_000, width: 920, height: 780), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.contentView = nil; window.close() }
        let host = NSHostingView(rootView: GamingView(game: game, app: app, checkAvailability: {}).frame(width: 920, height: 780))
        window.contentView = host; host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        func descendants(_ element: NSAccessibilityProtocol) -> [NSAccessibilityProtocol] {
            [element] + (element.accessibilityChildren() ?? []).compactMap { $0 as? NSAccessibilityProtocol }.flatMap(descendants)
        }
        let elements = descendants(host)
        try elements.map { "\($0.accessibilityRole()?.rawValue ?? "nil") | \($0.accessibilityLabel() ?? "nil") | \($0.accessibilityTitle() ?? "nil")" }.joined(separator: "\n").write(toFile: "/private/tmp/board-gaming-accessibility.txt", atomically: true, encoding: .utf8)
        try XCTSkipIf(!elements.contains { $0.accessibilityRole() == .button }, "This hidden SwiftUI host exposes no button accessibility nodes. Live AX activation remains unverified; do not show the owner's windows from this test.")
        let start = try XCTUnwrap(elements.first { ($0.accessibilityLabel() == "Start" || $0.accessibilityTitle() == "Start") && $0.accessibilityRole() == .button })
        XCTAssertTrue(start.accessibilityPerformPress())
        XCTAssertEqual(game.countdown, 3)
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        let pause = try XCTUnwrap(descendants(host).first { ($0.accessibilityLabel() == "Pause" || $0.accessibilityTitle() == "Pause") && $0.accessibilityRole() == .button })
        XCTAssertTrue(pause.accessibilityPerformPress()); XCTAssertNil(game.countdown)
        XCTAssertFalse(window.isVisible)
    }

    func testNativeModifierHoldAndSelectedMouseInput() throws {
        var now = 0.0
        let game = GamingPractice(defaults: store(), automaticallyTicks: false, clock: { now })
        let input = GamingInputSurface(); input.game = game
        let window = NSWindow(contentRect: NSRect(x: -10_000, y: -10_000, width: 200, height: 100), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.contentView = input
        defer { window.contentView = nil; window.close() }
        XCTAssertTrue(window.makeFirstResponder(input))
        game.selected = true; game.drill = .holdTap; game.start(); now = 3; game.tick()
        let shift = try XCTUnwrap(NSEvent.keyEvent(with: .flagsChanged, location: .zero, modifierFlags: NSEvent.ModifierFlags(rawValue: 2), timestamp: now, windowNumber: window.windowNumber, context: nil, characters: "", charactersIgnoringModifiers: "", isARepeat: false, keyCode: 56))
        input.flagsChanged(with: shift)
        now = 3.3
        let space = try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: .shift, timestamp: now, windowNumber: window.windowNumber, context: nil, characters: " ", charactersIgnoringModifiers: " ", isARepeat: false, keyCode: 49))
        input.keyDown(with: space)
        XCTAssertEqual(game.engine?.lastFeedback, .hit)
        XCTAssertEqual(game.engine?.actions, 2)
        game.reset(); game.drill = .reaction; game.keySet = 2; game.start(); now += 3; game.tick()
        let mouse = try XCTUnwrap(NSEvent.mouseEvent(with: .rightMouseDown, location: .zero, modifierFlags: [], timestamp: now, windowNumber: window.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: 1))
        input.rightMouseDown(with: mouse); XCTAssertEqual(game.engine?.actions, 1)
        game.updateAvailability(active: true, secureInput: true)
        input.rightMouseDown(with: mouse); XCTAssertEqual(game.engine?.actions, 1)
        XCTAssertFalse(window.isVisible)
    }

    func testOffscreenOverlayAndReducedMotionLane() throws {
        let overlay = GamingOverlay(defaults: store(), presentsWindow: false, clock: { 12.0 })
        overlay.setAvailable(true); overlay.enabled = true
        overlay.receive(.init(key: 13, transition: .press, modifiers: 0, timestamp: 12))
        overlay.receive(.init(key: 1000, transition: .press, modifiers: 0, timestamp: 12))
        defer { overlay.enabled = false }
        var engine = GamingSession(configuration: try GamingConfiguration(drill: .strafeRhythm))
        engine.start(at: 0); engine.advance(to: 0.2)
        let window = NSWindow(contentRect: NSRect(x: -10_000, y: -10_000, width: 600, height: 310), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.contentView = nil; window.close() }
        let host = NSHostingView(rootView: VStack(spacing: 20) {
            GamingCluster(overlay: overlay)
            GamingBeatLane(engine: engine, color: .pink, reduceMotion: true)
        }.padding(20).frame(width: 600, height: 310).background(Color(nsColor: .windowBackgroundColor)))
        window.contentView = host; host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        let data = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
        let path = URL(fileURLWithPath: "/private/tmp/board-gaming-artifacts", isDirectory: true)
        try FileManager.default.createDirectory(at: path, withIntermediateDirectories: true)
        try data.write(to: path.appendingPathComponent("overlay-and-reduced-motion.png"))
        XCTAssertGreaterThan(data.count, 5_000); XCTAssertFalse(window.isVisible)
    }
}
