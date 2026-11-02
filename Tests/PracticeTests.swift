import XCTest
import AppKit
import SwiftUI
@testable import Board

@MainActor final class PracticeTests: XCTestCase {
    private let suite = "com.tommyent.Board.tests.practice"
    private func defaults() -> UserDefaults {
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    func testCorrectedMistakesStillAffectAccuracyAndWPMUsesCurrentCorrectText() {
        var now = 0.0
        let session = PracticeSession(defaults: defaults(), clock: { now })
        session.mode = .custom; session.customText = "hello world"; session.reset()
        XCTAssertTrue(session.replaceTyped("helx"))
        now = 10; session.tick()
        XCTAssertEqual(session.correct, 3)
        XCTAssertEqual(session.wpm, 3.6, accuracy: 0.001)
        XCTAssertEqual(session.accuracy, 75)
        XCTAssertTrue(session.replaceTyped("hel"))
        XCTAssertTrue(session.replaceTyped("hello"))
        XCTAssertEqual(session.attempts, 6)
        XCTAssertEqual(session.correctAttempts, 5)
        XCTAssertEqual(session.accuracy, 100 * 5 / 6, accuracy: 0.001)
        XCTAssertEqual(session.wpm, 6, accuracy: 0.001)
        XCTAssertTrue(session.replaceTyped("he"))
        XCTAssertEqual(session.correct, 2)
        XCTAssertEqual(session.attempts, 6)
    }

    func testPauseExcludesInactiveTimeAndRequiresExplicitResume() {
        var now = 100.0
        let session = PracticeSession(defaults: defaults(), clock: { now })
        session.replaceTyped("T")
        now = 110; session.updateAvailability(active: false, secureInput: false)
        XCTAssertEqual(session.phase, .paused)
        XCTAssertEqual(session.elapsed, 10)
        now = 170
        XCTAssertFalse(session.replaceTyped("Th"))
        session.updateAvailability(active: true, secureInput: false)
        XCTAssertEqual(session.phase, .paused)
        session.resume(); now = 175; session.tick()
        XCTAssertEqual(session.elapsed, 15)
        session.updateAvailability(active: true, secureInput: true)
        XCTAssertEqual(session.phase, .paused)
        session.resume()
        XCTAssertEqual(session.phase, .paused)
        XCTAssertFalse(session.replaceTyped("The"))
        now = 300; session.updateAvailability(active: true, secureInput: false); session.resume()
        now = 301; session.tick()
        XCTAssertEqual(session.elapsed, 16)
    }

    func testEditingEarlierMistakeDoesNotRecountUnchangedSuffix() {
        let session = PracticeSession(defaults: defaults())
        session.mode = .custom; session.customText = "hello world again"; session.reset()
        session.replaceTyped("hexlo world")
        XCTAssertEqual(session.attempts, 11)
        session.replaceTyped("hello world")
        XCTAssertEqual(session.attempts, 12)
        XCTAssertEqual(session.correctAttempts, 11)
        XCTAssertEqual(session.correct, 11)
    }

    func testDeadlineRejectsLateInputAndSavesOnce() {
        var now = 0.0
        let store = defaults()
        let session = PracticeSession(defaults: store, clock: { now })
        session.duration = 30; session.reset(); session.replaceTyped("The ")
        now = 31
        XCTAssertFalse(session.replaceTyped("The room"))
        XCTAssertEqual(session.phase, .finished)
        XCTAssertEqual(session.typed, "The ")
        XCTAssertEqual(session.elapsed, 30)
        XCTAssertEqual(session.history.count, 1)
        session.tick(); session.pause(); session.resume(); session.tick()
        XCTAssertEqual(session.history.count, 1)
        let loaded = PracticeSession(defaults: store)
        XCTAssertEqual(loaded.history.first?.wpm, 1.6)
        XCTAssertEqual(loaded.best, nil) // 30s and 60s bests stay separate.
        loaded.duration = 30
        XCTAssertEqual(loaded.best, 1.6)
        loaded.mode = .code
        XCTAssertNil(loaded.best)
    }

    func testCustomTextAndTypedContentNeverEnterHistoryAndCloseClearsText() throws {
        var now = 0.0
        let store = defaults()
        let session = PracticeSession(defaults: store, clock: { now })
        session.mode = .custom; session.customText = "private passage"; session.reset()
        session.replaceTyped("private "); now = 5; session.replaceTyped("private passage")
        XCTAssertEqual(session.phase, .finished)
        XCTAssertEqual(session.history.count, 1)
        let serialized = try XCTUnwrap(String(data: XCTUnwrap(store.data(forKey: "practice.history.v1")), encoding: .utf8))
        XCTAssertFalse(serialized.contains("private"))
        XCTAssertFalse(serialized.contains("passage"))
        XCTAssertNil(session.best)
        session.close()
        XCTAssertTrue(session.customText.isEmpty)
        XCTAssertTrue(session.typed.isEmpty)
        XCTAssertTrue(session.target.isEmpty)
        session.clearHistory()
        XCTAssertNil(store.data(forKey: "practice.history.v1"))
        XCTAssertTrue(PracticeSession(defaults: store).history.isEmpty)
    }

    func testBoundaryValidationAndCorruptHistoryPreservation() {
        let store = defaults()
        let damaged = Data("invalid history".utf8)
        store.set(damaged, forKey: "practice.history.v1")
        var now = 0.0
        let session = PracticeSession(defaults: store, clock: { now })
        XCTAssertNotNil(session.historyError)
        session.mode = .custom; session.customText = " \t\n"; session.reset()
        XCTAssertFalse(session.acceptsInput)
        session.customText = "a\r\n\tb"; session.duration = -10; session.reset()
        XCTAssertEqual(String(session.target), "a\n    b")
        XCTAssertEqual(session.duration, 60)
        session.replaceTyped("a"); now = 5; session.replaceTyped("a\n    b")
        XCTAssertEqual(store.data(forKey: "practice.history.v1"), damaged)
        session.customText = String(repeating: "x", count: 20_000); session.reset()
        XCTAssertEqual(session.target.count, PracticeSession.textLimit)
        XCTAssertFalse(session.replaceTyped(String(repeating: "x", count: 10_001)))
    }

    func testUnicodeCompositionAndNativeTextInput() {
        let session = PracticeSession(defaults: defaults())
        session.mode = .custom; session.customText = "café 👩🏽‍💻 done"; session.reset()
        let input = PracticeTextView(frame: NSRect(x: 0, y: 0, width: 500, height: 100))
        let delegate = PracticeInput.Coordinator(session: session)
        input.session = session; input.delegate = delegate; input.isRichText = false
        input.insertText("café ", replacementRange: NSRange(location: 0, length: 0))
        XCTAssertEqual(session.typed, "café ")
        XCTAssertEqual(session.attempts, 5)
        input.setMarkedText("👩🏽‍💻", selectedRange: NSRange(location: 7, length: 0), replacementRange: NSRange(location: 5, length: 0))
        XCTAssertEqual(session.typed, "café ")
        input.insertText("👩🏽‍💻", replacementRange: input.markedRange())
        XCTAssertEqual(session.typed, "café 👩🏽‍💻")
        XCTAssertEqual(session.correct, 6)
        input.paste(nil)
        XCTAssertEqual(session.typed, "café 👩🏽‍💻")
        session.updateAvailability(active: true, secureInput: true)
        input.insertText(" secret", replacementRange: input.selectedRange())
        XCTAssertEqual(session.typed, "café 👩🏽‍💻")
        withExtendedLifetime(delegate) { }
    }

    func testTrailIsBoundedAndClearedOnFocusLoss() {
        var now = 0.0
        let session = PracticeSession(defaults: defaults(), clock: { now })
        for index in 0..<20 { session.recordKey(String(index)) }
        XCTAssertEqual(session.strokes.count, 7)
        now = 3; session.tick()
        XCTAssertTrue(session.strokes.isEmpty)
        session.recordKey("A"); session.updateAvailability(active: false, secureInput: false)
        XCTAssertTrue(session.strokes.isEmpty)
        session.recordKey("private")
        XCTAssertTrue(session.strokes.isEmpty)
    }

    func testOffscreenPracticeRendering() throws {
        let directory = URL(fileURLWithPath: "/private/tmp/board-practice-artifacts", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let store = defaults()
        let app = AppState(defaults: store)
        var now = 0.0
        let session = PracticeSession(defaults: store, clock: { now })
        func capture<V: View>(_ name: String, _ view: V, width: CGFloat = 920, height: CGFloat = 720, dark: Bool = false) throws {
            let window = NSWindow(contentRect: NSRect(x: -10_000, y: -10_000, width: width, height: height), styleMask: [.titled], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
            let host = NSHostingView(rootView: view.frame(width: width, height: height).background(Color(nsColor: .windowBackgroundColor)))
            window.contentView = host
            host.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.15))
            let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
            host.cacheDisplay(in: host.bounds, to: bitmap)
            let data = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
            XCTAssertGreaterThan(data.count, 5_000)
            try data.write(to: directory.appendingPathComponent(name + ".png"))
            XCTAssertFalse(window.isVisible)
            window.contentView = nil
            window.close()
        }
        try capture("english-ready", PracticeView(session: session, app: app, checkAvailability: {}))
        session.replaceTyped("The room grew quiet as the raim")
        now = 12; session.tick()
        for label in ["T", "H", "E", "Space", "R"] { session.recordKey(label) }
        try capture("english-running", PracticeView(session: session, app: app, checkAvailability: {}))
        session.updateAvailability(active: true, secureInput: true)
        try capture("secure-input-paused", PracticeView(session: session, app: app, checkAvailability: {}))
        session.updateAvailability(active: true, secureInput: false)
        session.mode = .code; session.reset()
        session.replaceTyped("func greet(_ name: Strimg")
        now = 20; session.tick()
        try capture("code-minimum-dark", PracticeView(session: session, app: app, checkAvailability: {}), width: 760, height: 640, dark: true)
        now = 100; session.tick()
        try capture("finished", PracticeView(session: session, app: app, checkAvailability: {}))
        try capture("history", PracticeHistoryView(session: session), width: 668, height: 508)
    }

}
