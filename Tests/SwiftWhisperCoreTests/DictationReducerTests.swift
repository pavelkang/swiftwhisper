import Foundation
import XCTest
@testable import SwiftWhisperCore

final class DictationReducerTests: XCTestCase {
    private let clock = ContinuousClock()

    func testWakePressStartsCaptureAndPreparationConcurrently() {
        let snapshot = makeSnapshot()
        var state = DictationState.idle

        let effects = DictationReducer.reduce(state: &state, action: .wakePressed(snapshot))

        XCTAssertEqual(state, .arming(ArmingSession(snapshot: snapshot)))
        XCTAssertEqual(effects, [
            .showOverlay,
            .startCapture(snapshot.id),
            .prepareSession(snapshot),
        ])
    }

    func testArmingWaitsForCaptureAndEngineReadiness() {
        let snapshot = makeSnapshot()
        var state = DictationState.arming(ArmingSession(snapshot: snapshot))

        _ = DictationReducer.reduce(state: &state, action: .engineReady(snapshot.id))
        XCTAssertTrue(isArming(state))

        let effects = DictationReducer.reduce(state: &state, action: .captureStarted(snapshot.id))
        XCTAssertEqual(state, .listening(snapshot))
        XCTAssertEqual(effects, [.scheduleMaximumDuration(snapshot.id, after: .seconds(600))])
    }

    func testReleaseBeforeThresholdCancels() {
        let snapshot = makeSnapshot()
        var state = DictationState.arming(ArmingSession(snapshot: snapshot))

        let effects = DictationReducer.reduce(
            state: &state,
            action: .wakeReleased(at: snapshot.startedAt.advanced(by: .milliseconds(50)))
        )

        XCTAssertEqual(state, .cancelling(snapshot.id))
        XCTAssertEqual(effects, [.cancelSession(snapshot.id), .cleanup(snapshot.id)])
    }

    func testReleaseDuringArmingPreservesBufferedSessionUntilReady() {
        let snapshot = makeSnapshot()
        var state = DictationState.arming(ArmingSession(snapshot: snapshot))

        _ = DictationReducer.reduce(state: &state, action: .captureStarted(snapshot.id))
        let stopEffects = DictationReducer.reduce(
            state: &state,
            action: .wakeReleased(at: snapshot.startedAt.advanced(by: .milliseconds(300)))
        )
        XCTAssertEqual(stopEffects, [.finishCapture(snapshot.id)])

        _ = DictationReducer.reduce(state: &state, action: .captureStopped(snapshot.id))
        XCTAssertTrue(isArming(state))

        let finalizeEffects = DictationReducer.reduce(state: &state, action: .engineReady(snapshot.id))
        XCTAssertEqual(state, .finalizing(snapshot))
        XCTAssertEqual(finalizeEffects, [.finalizeRecognition(snapshot.id)])
    }

    func testLateCallbacksFromAnotherSessionAreIgnored() {
        let snapshot = makeSnapshot()
        var state = DictationState.listening(snapshot)

        let effects = DictationReducer.reduce(
            state: &state,
            action: .partialTranscript(SessionID(), "stale")
        )

        XCTAssertEqual(state, .listening(snapshot))
        XCTAssertTrue(effects.isEmpty)
    }

    func testFinalTranscriptIsPersistedBeforeDelivery() {
        let snapshot = makeSnapshot()
        let transcript = makeTranscript()
        var state = DictationState.finalizing(snapshot)

        let postProcess = DictationReducer.reduce(
            state: &state,
            action: .finalTranscript(snapshot.id, transcript)
        )
        XCTAssertEqual(postProcess, [.postProcess(snapshot.id, transcript)])

        let persist = DictationReducer.reduce(
            state: &state,
            action: .postProcessingCompleted(snapshot.id, transcript)
        )
        XCTAssertEqual(persist, [.persistRecovery(snapshot.id, transcript)])
        XCTAssertEqual(state, .persisting(snapshot, transcript))
    }

    func testRecoveryFailureBlocksAutomaticDelivery() {
        let snapshot = makeSnapshot()
        let transcript = makeTranscript()
        var state = DictationState.persisting(snapshot, transcript)

        let effects = DictationReducer.reduce(
            state: &state,
            action: .recoveryPersistenceFailed(snapshot.id, transcript: transcript)
        )

        XCTAssertEqual(effects, [.showPersistentRecovery(snapshot.id, transcript)])
        guard case .failed(let failure) = state else {
            return XCTFail("Expected failed state")
        }
        XCTAssertEqual(failure.recoverableTranscript, transcript)
    }

    func testProgressIsClamped() {
        let snapshot = makeSnapshot()
        var state = DictationState.finalizing(snapshot)

        _ = DictationReducer.reduce(
            state: &state,
            action: .transcriptionProgress(snapshot.id, 4.2)
        )

        XCTAssertEqual(state, .transcribing(snapshot, progress: 1))
    }

    private func makeSnapshot() -> SessionSnapshot {
        SessionSnapshot(
            startedAt: clock.now,
            modelID: .appleDictation,
            localeIdentifier: "en-US",
            sourceApplicationBundleID: "com.apple.TextEdit"
        )
    }

    private func makeTranscript() -> FinalTranscript {
        FinalTranscript(
            text: "Hello from SwiftWhisper.",
            segments: [TranscriptSegment(text: "Hello from SwiftWhisper.")],
            modelID: .appleDictation,
            localeIdentifier: "en-US",
            audioDuration: .seconds(2)
        )
    }

    private func isArming(_ state: DictationState) -> Bool {
        if case .arming = state { return true }
        return false
    }
}
