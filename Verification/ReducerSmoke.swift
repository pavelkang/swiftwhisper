import Foundation

func require(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else { fatalError("Verification failed: \(message)") }
}

func isArming(_ state: DictationState) -> Bool {
    if case .arming = state { return true }
    return false
}

let now = ContinuousClock().now
let snapshot = SessionSnapshot(
    startedAt: now,
    modelID: .appleDictation,
    localeIdentifier: "en-US",
    sourceApplicationBundleID: "com.apple.TextEdit"
)

var state = DictationState.idle
let startEffects = DictationReducer.reduce(state: &state, action: .wakePressed(snapshot))
require(startEffects == [
    .showOverlay,
    .startCapture(snapshot.id),
    .prepareSession(snapshot),
], "wake press must start capture and preparation")

_ = DictationReducer.reduce(state: &state, action: .captureStarted(snapshot.id))
require(isArming(state), "capture readiness alone must remain arming")

_ = DictationReducer.reduce(state: &state, action: .engineReady(snapshot.id))
require(state == .listening(snapshot), "both readiness signals must enter listening")

let stopEffects = DictationReducer.reduce(
    state: &state,
    action: .wakeReleased(at: now.advanced(by: .seconds(1)))
)
require(stopEffects == [.finishCapture(snapshot.id)], "release must stop capture")
require(state == .finalizing(snapshot), "release must enter finalizing")

let transcript = FinalTranscript(
    text: "Hello from SwiftWhisper.",
    segments: [TranscriptSegment(text: "Hello from SwiftWhisper.")],
    modelID: .appleDictation,
    localeIdentifier: "en-US",
    audioDuration: .seconds(1)
)
_ = DictationReducer.reduce(state: &state, action: .finalTranscript(snapshot.id, transcript))
let persistEffects = DictationReducer.reduce(
    state: &state,
    action: .postProcessingCompleted(snapshot.id, transcript)
)
require(
    persistEffects == [.persistRecovery(snapshot.id, transcript)],
    "recovery must precede delivery"
)

print("Reducer smoke verification passed")
