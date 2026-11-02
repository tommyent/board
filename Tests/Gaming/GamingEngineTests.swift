import XCTest
@testable import BoardGamingEngine

final class GamingEngineTests: XCTestCase {
    private struct SeededRandom: RandomNumberGenerator {
        var value: UInt64
        mutating func next() -> UInt64 {
            value = value &* 6364136223846793005 &+ 1442695040888963407
            return value
        }
    }

    private func session(_ drill: GamingDrill, duration: Double = 30,
                         keys: [GamingInput] = GamingInput.wasd) throws -> GamingSession {
        var random = SeededRandom(value: 42)
        return GamingSession(configuration: try GamingConfiguration(drill: drill, duration: duration, keys: keys), using: &random)
    }

    func testConfigurationRejectsInvalidAndUnboundedValues() throws {
        for duration in [Double.nan, .infinity, -1, 0, 2, 601] {
            XCTAssertThrowsError(try GamingConfiguration(drill: .reaction, duration: duration))
        }
        for tempo in [Double.nan, .infinity, 0, 29, 301] {
            XCTAssertThrowsError(try GamingConfiguration(drill: .strafeRhythm, tempo: tempo))
        }
        for window in [Double.nan, .infinity, 0, -0.1, 0.3] {
            XCTAssertThrowsError(try GamingConfiguration(drill: .holdTap, window: window))
        }
        XCTAssertThrowsError(try GamingConfiguration(drill: .reaction, keys: []))
        XCTAssertThrowsError(try GamingConfiguration(drill: .reaction, keys: [.w, .w]))
        XCTAssertThrowsError(try GamingConfiguration(drill: .reaction, keys: (0..<65).map { .key(UInt16($0)) }))
        XCTAssertNoThrow(try GamingConfiguration(drill: .reaction))
    }

    func testReactionScheduleHasRandomWaitsAndCompleteResponseWindows() throws {
        let game = try session(.reaction, keys: [.w, .mouse(0)])
        XCTAssertEqual(game.cues, try session(.reaction, keys: [.w, .mouse(0)]).cues)
        XCTAssertGreaterThan(game.cues.count, 5)
        XCTAssertEqual(Set(game.cues.map(\.id)).count, game.cues.count)
        var previousDeadline = 0.0
        for cue in game.cues {
            XCTAssertEqual(cue.startsAt, previousDeadline)
            XCTAssertGreaterThanOrEqual(cue.targetAt-cue.startsAt, 0.5-1e-9)
            XCTAssertLessThanOrEqual(cue.targetAt-cue.startsAt, 1.25+1e-9)
            XCTAssertEqual(cue.deadline-cue.targetAt, 1.25, accuracy: 1e-9)
            XCTAssertLessThanOrEqual(cue.deadline, 30)
            XCTAssertTrue([GamingInput.w, .mouse(0)].contains(cue.input))
            previousDeadline = cue.deadline
        }
        var otherRandom = SeededRandom(value: 43)
        XCTAssertNotEqual(game.cues, GamingSession(configuration: game.configuration, using: &otherRandom).cues)
    }

    func testReactionMedianAndMADUseCorrectTrialsOnly() throws {
        var game = try session(.reaction)
        XCTAssertNil(game.score.medianMilliseconds)
        XCTAssertNil(game.score.accuracyPercent)
        XCTAssertNil(game.score.actionsPerMinute)
        XCTAssertTrue(game.start(at: 0))
        for (cue, latency) in zip(game.cues, [0.1, 0.2, 0.4, 0.8]) {
            XCTAssertEqual(game.press(cue.input, at: cue.targetAt+latency), .hit)
            game.release(cue.input, at: cue.targetAt+latency+0.001)
        }
        XCTAssertEqual(try XCTUnwrap(game.score.medianMilliseconds), 300, accuracy: 1e-8)
        XCTAssertEqual(try XCTUnwrap(game.score.madMilliseconds), 150, accuracy: 1e-8)
        XCTAssertEqual(game.score.accuracyPercent, 100)
        XCTAssertNil(game.score.onTimePercent)
        game.advance(to: 30)
        XCTAssertEqual(game.score.completedTrials, game.cues.count)
        XCTAssertEqual(try XCTUnwrap(game.score.accuracyPercent), 400/Double(game.cues.count), accuracy: 1e-8)
        XCTAssertEqual(try XCTUnwrap(game.score.medianMilliseconds), 300, accuracy: 1e-8)
    }

    func testOddSampleMedianAndMAD() throws {
        var game = try session(.reaction)
        game.start(at: 0)
        for (cue, latency) in zip(game.cues, [0.1, 0.2, 0.4]) {
            game.press(cue.input, at: cue.targetAt+latency)
            game.release(cue.input, at: cue.targetAt+latency+0.001)
        }
        XCTAssertEqual(try XCTUnwrap(game.score.medianMilliseconds), 200, accuracy: 1e-8)
        XCTAssertEqual(try XCTUnwrap(game.score.madMilliseconds), 100, accuracy: 1e-8)
    }

    func testFalseStartsWrongKeysAndExtraPressesCannotImproveAccuracy() throws {
        var game = try session(.reaction)
        game.start(at: 0)
        let first = game.cues[0], second = game.cues[1]
        XCTAssertEqual(game.press(first.input, at: 0.1), .early)
        XCTAssertNil(game.press(first.input, at: 0.11))
        game.release(first.input, at: 0.12)
        XCTAssertEqual(game.press(first.input, at: 0.13), .extra)
        game.release(first.input, at: 0.14)
        XCTAssertEqual(game.press(.key(127), at: second.targetAt+0.1), .wrongKey)
        XCTAssertEqual(game.score.completedTrials, 2)
        XCTAssertEqual(game.score.extraPresses, 1)
        XCTAssertEqual(game.actions, 3)
        XCTAssertEqual(game.score.accuracyPercent, 0)
        XCTAssertNil(game.score.medianMilliseconds)
    }

    func testCueOnsetIsInclusiveButDeadlineIsExclusive() throws {
        var onset = try session(.reaction)
        onset.start(at: 0)
        XCTAssertEqual(onset.press(onset.cues[0].input, at: onset.cues[0].targetAt), .hit)
        XCTAssertEqual(onset.score.medianMilliseconds, 0)
        var deadline = try session(.reaction)
        deadline.start(at: 0)
        XCTAssertEqual(deadline.press(deadline.cues[0].input, at: deadline.cues[0].deadline), .early)
        XCTAssertEqual(deadline.results.map(\.verdict), [.timeout, .early])
    }

    func testNoInputCompletesAllTrialsAsTimeoutsAndStopsAcceptingInput() throws {
        for drill in GamingDrill.allCases {
            var game = try session(drill)
            XCTAssertNil(game.press(.w, at: 0))
            game.start(at: 10)
            game.advance(to: 40)
            XCTAssertEqual(game.phase, .finished)
            XCTAssertEqual(game.results.count, game.cues.count)
            XCTAssertTrue(game.results.allSatisfy { $0.verdict == .timeout })
            XCTAssertEqual(game.score.accuracyPercent, 0)
            XCTAssertEqual(game.score.actionsPerMinute, 0)
            XCTAssertNil(game.score.medianMilliseconds)
            XCTAssertNil(game.press(.w, at: 41))
            XCTAssertFalse(game.start(at: 42))
            XCTAssertFalse(game.advance(to: 43))
        }
    }

    func testFiftyBeatsInThirtySecondsProduces100APMAnd90PercentOnTime() throws {
        var game = try session(.strafeRhythm)
        XCTAssertEqual(game.cues.count, 50)
        game.start(at: 0)
        for cue in game.cues {
            let error = cue.id.isMultiple(of: 10) ? 0.084 : 0.018
            XCTAssertEqual(game.press(cue.input, at: cue.targetAt+error), cue.id.isMultiple(of: 10) ? .late : .hit)
            XCTAssertNil(game.press(cue.input, at: cue.targetAt+error+0.001, isRepeat: true))
            game.release(cue.input, at: cue.targetAt+error+0.002)
        }
        game.advance(to: 30)
        XCTAssertEqual(game.score.hits, 45)
        XCTAssertEqual(game.actions, 50)
        XCTAssertEqual(game.score.actionsPerMinute, 100)
        XCTAssertEqual(game.score.onTimePercent, 90)
        XCTAssertEqual(try XCTUnwrap(game.score.medianMilliseconds), 18, accuracy: 1e-8)
    }

    func testTimingMedianIsAbsoluteButMADUsesSignedErrors() throws {
        var game = try session(.strafeRhythm)
        game.start(at: 0)
        for (cue, error) in zip(game.cues, [-0.02, 0.04]) {
            game.press(cue.input, at: cue.targetAt+error)
            game.release(cue.input, at: cue.targetAt+error+0.001)
        }
        XCTAssertEqual(try XCTUnwrap(game.score.medianMilliseconds), 30, accuracy: 1e-8)
        XCTAssertEqual(try XCTUnwrap(game.score.madMilliseconds), 30, accuracy: 1e-8)
        XCTAssertEqual(game.score.onTimePercent, 100)
    }

    func testTimingWindowIncludesBothEdgesAndRejectsOutside() throws {
        var game = try session(.strafeRhythm)
        game.start(at: 0)
        let errors = [-0.06, 0.06, -0.0601, 0.0601]
        let expected: [GamingVerdict] = [.hit, .hit, .early, .late]
        for index in errors.indices {
            let cue = game.cues[index], time = cue.targetAt+errors[index]
            XCTAssertEqual(game.press(cue.input, at: time), expected[index])
            game.release(cue.input, at: time+0.001)
        }
        XCTAssertEqual(game.score.onTimePercent, 50)
    }

    func testRepeatAndDuplicatePressesRequireAReleaseBeforeReuse() throws {
        var game = try session(.reaction, keys: [.w])
        game.start(at: 0)
        XCTAssertNil(game.press(.w, at: 0.1, isRepeat: true))
        XCTAssertEqual(game.press(.w, at: game.cues[0].targetAt+0.1), .hit)
        XCTAssertNil(game.press(.w, at: game.cues[1].targetAt+0.1))
        XCTAssertNil(game.press(.w, at: game.cues[1].targetAt+0.2, isRepeat: true))
        game.release(.w, at: game.cues[1].targetAt+0.3)
        XCTAssertEqual(game.press(.w, at: game.cues[1].targetAt+0.4), .hit)
        XCTAssertEqual(game.actions, 2)
        XCTAssertEqual(game.score.completedTrials, 2)
    }

    func testOnlyExplicitlySelectedMouseButtonsCount() throws {
        var game = try session(.reaction, keys: [.mouse(0)])
        game.start(at: 0)
        XCTAssertNil(game.press(.mouse(1), at: 0.1))
        game.release(.mouse(1), at: 0.2)
        XCTAssertEqual(game.actions, 0)
        XCTAssertTrue(game.results.isEmpty)
        XCTAssertEqual(game.press(.mouse(0), at: game.cues[0].targetAt+0.2), .hit)
        game.release(.mouse(0), at: game.cues[0].targetAt+0.21)
        XCTAssertEqual(game.actions, 1)
        XCTAssertEqual(try XCTUnwrap(game.score.medianMilliseconds), 200, accuracy: 1e-8)
    }

    func testPauseExcludesWallTimeAndAbandonsTheCurrentCue() throws {
        var game = try session(.strafeRhythm, duration: 3)
        game.start(at: 10)
        XCTAssertTrue(game.pause(at: 10.1))
        let pausedElapsed = game.elapsed
        XCTAssertNil(game.currentCue)
        XCTAssertEqual(game.results.map(\.verdict), [.interrupted])
        XCTAssertEqual(game.score.completedTrials, 0)
        XCTAssertNil(game.score.accuracyPercent)
        XCTAssertNil(game.press(.w, at: 50))
        game.advance(to: 100)
        XCTAssertEqual(game.elapsed, pausedElapsed)
        XCTAssertFalse(game.resume(at: 99))
        XCTAssertTrue(game.resume(at: 100))
        let cue = game.cues[1]
        XCTAssertEqual(game.press(cue.input, at: 100+cue.targetAt-pausedElapsed), .hit)
        game.advance(to: 100+3-pausedElapsed)
        XCTAssertEqual(game.phase, .finished)
        XCTAssertEqual(game.score.completedTrials, 4)
        XCTAssertEqual(game.score.actionsPerMinute, 20)
    }

    func testInvalidAndOutOfOrderTimestampsDoNotMutateTheSession() throws {
        var game = try session(.strafeRhythm, duration: 3)
        XCTAssertFalse(game.start(at: .nan))
        XCTAssertFalse(game.start(at: -1))
        XCTAssertTrue(game.start(at: 10))
        XCTAssertFalse(game.start(at: 11))
        XCTAssertFalse(game.advance(to: 9))
        XCTAssertNil(game.press(.d, at: .infinity))
        XCTAssertEqual(game.elapsed, 0)
        XCTAssertEqual(game.press(.d, at: 10.3), .hit)
        let score = game.score
        game.release(.d, at: 10.2)
        XCTAssertNil(game.press(.d, at: 10.3))
        XCTAssertFalse(game.pause(at: 10.1))
        XCTAssertFalse(game.resume(at: 10.4))
        XCTAssertEqual(game.score, score)
    }

    func testHoldThenTapRequiresTheModifierToRemainHeld() throws {
        var game = try session(.holdTap)
        game.start(at: 0)
        XCTAssertNil(game.press(.shift, at: 0.1))
        XCTAssertTrue(game.results.isEmpty)
        XCTAssertEqual(game.press(.space, at: game.cues[0].targetAt), .hit)
        game.release(.space, at: 0.31)
        game.release(.shift, at: 0.4)
        XCTAssertEqual(game.press(.space, at: game.cues[1].targetAt), .missingHold)
        XCTAssertEqual(game.actions, 3)
        XCTAssertEqual(game.score.onTimePercent, 50)
    }

    func testPauseClearsHeldModifiersAndRequiresExplicitResume() throws {
        var game = try session(.holdTap)
        game.start(at: 0)
        game.press(.shift, at: 0.1)
        game.pause(at: 0.2)
        XCTAssertNil(game.press(.space, at: 0.3))
        game.release(.shift, at: 0.4)
        game.resume(at: 10)
        XCTAssertEqual(game.press(.space, at: 10+game.cues[1].targetAt-0.2), .missingHold)
        XCTAssertEqual(game.actions, 2)
    }

    func testKeyReversalMeasuresReleaseToOppositePress() throws {
        var game = try session(.keyReversal)
        game.start(at: 0)
        XCTAssertNil(game.press(.a, at: 0.1))
        game.release(.a, at: game.cues[0].targetAt)
        XCTAssertEqual(game.press(.d, at: game.cues[0].targetAt+0.05), .hit)
        game.release(.d, at: game.cues[1].targetAt)
        XCTAssertEqual(game.press(.a, at: game.cues[1].targetAt+0.07), .late)
        XCTAssertEqual(try XCTUnwrap(game.score.medianMilliseconds), 60, accuracy: 1e-8)
        XCTAssertEqual(try XCTUnwrap(game.score.madMilliseconds), 10, accuracy: 1e-8)
        XCTAssertEqual(game.score.onTimePercent, 50)
        XCTAssertEqual(game.actions, 3)
    }

    func testKeyReversalRejectsOverlapAndReleaseBeforeTheCue() throws {
        var game = try session(.keyReversal)
        game.start(at: 0)
        game.press(.a, at: 0.1)
        XCTAssertEqual(game.press(.d, at: 0.31), .wrongOrder)
        game.release(.a, at: 0.32)
        game.release(.d, at: 0.8)
        XCTAssertEqual(game.press(.a, at: 0.91), .wrongOrder)
        XCTAssertNil(game.score.medianMilliseconds)
        XCTAssertEqual(game.score.onTimePercent, 0)
    }

    func testSchedulesStayBoundedAtMaximumDurationAndTempo() throws {
        var random = SeededRandom(value: 1)
        let config = try GamingConfiguration(drill: .strafeRhythm, duration: 600, tempo: 300)
        var game = GamingSession(configuration: config, using: &random)
        XCTAssertEqual(game.cues.count, 3000)
        XCTAssertEqual(game.cues.last?.deadline, 600)
        game.start(at: 0)
        game.advance(to: 600)
        XCTAssertEqual(game.results.count, 3000)
        XCTAssertEqual(game.phase, .finished)
    }
}
