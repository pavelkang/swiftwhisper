import Foundation

public enum DictationReducer {
    public static let accidentalPressThreshold: Duration = .milliseconds(120)
    public static let maximumDuration: Duration = .seconds(600)

    public static func reduce(
        state: inout DictationState,
        action: DictationAction
    ) -> [DictationEffect] {
        switch (state, action) {
        case (.idle, .wakePressed(let snapshot)):
            state = .arming(ArmingSession(snapshot: snapshot))
            return [.showOverlay, .startCapture(snapshot.id), .prepareSession(snapshot)]

        case (.arming(var arming), .captureStarted(let id)) where arming.snapshot.id == id:
            arming.captureStarted = true
            return advanceArming(state: &state, arming: arming)

        case (.arming(var arming), .engineReady(let id)) where arming.snapshot.id == id:
            arming.engineReady = true
            return advanceArming(state: &state, arming: arming)

        case (.arming(var arming), .wakeReleased(let releasedAt)):
            let heldFor = arming.snapshot.startedAt.duration(to: releasedAt)
            if heldFor < accidentalPressThreshold {
                state = .cancelling(arming.snapshot.id)
                return [.cancelSession(arming.snapshot.id), .cleanup(arming.snapshot.id)]
            }
            arming.releasedAt = releasedAt
            state = .arming(arming)
            return [.finishCapture(arming.snapshot.id)]

        case (.arming(var arming), .captureStopped(let id)) where arming.snapshot.id == id:
            arming.captureStopped = true
            return advanceArming(state: &state, arming: arming)

        case (.arming(var arming), .audioLevel(let id, let level)) where arming.snapshot.id == id:
            arming.snapshot.level = level
            state = .arming(arming)
            return []

        case (.listening(var snapshot), .audioLevel(let id, let level)) where snapshot.id == id:
            snapshot.level = level
            state = .listening(snapshot)
            return []

        case (.listening(let snapshot), .wakeReleased):
            state = .finalizing(snapshot)
            return [.finishCapture(snapshot.id)]

        case (.listening(let snapshot), .captureStopped(let id)) where snapshot.id == id:
            state = .finalizing(snapshot)
            return [.finalizeRecognition(id)]

        case (.listening(let snapshot), .maximumDurationElapsed(let id)) where snapshot.id == id:
            state = .finalizing(snapshot)
            return [.finishCapture(id)]

        case (.listening(let snapshot), .cancelRequested),
             (.finalizing(let snapshot), .cancelRequested),
             (.transcribing(let snapshot, _), .cancelRequested):
            state = .cancelling(snapshot.id)
            return [.cancelSession(snapshot.id), .cleanup(snapshot.id)]

        case (.finalizing(let snapshot), .recognitionFinalizationStarted(let id, let progressSupported))
            where snapshot.id == id:
            if progressSupported {
                state = .transcribing(snapshot, progress: 0)
            }
            return []

        case (.finalizing(var snapshot), .partialTranscript(let id, let text)) where snapshot.id == id:
            snapshot.partialText = text
            state = .finalizing(snapshot)
            return []

        case (.transcribing(var snapshot, let progress), .partialTranscript(let id, let text))
            where snapshot.id == id:
            snapshot.partialText = text
            state = .transcribing(snapshot, progress: progress)
            return []

        case (.listening(var snapshot), .partialTranscript(let id, let text)) where snapshot.id == id:
            snapshot.partialText = text
            state = .listening(snapshot)
            return []

        case (.finalizing(let snapshot), .transcriptionProgress(let id, let progress))
            where snapshot.id == id:
            state = .transcribing(snapshot, progress: clamped(progress))
            return []

        case (.transcribing(let snapshot, _), .transcriptionProgress(let id, let progress))
            where snapshot.id == id:
            state = .transcribing(snapshot, progress: clamped(progress))
            return []

        case (.finalizing(let snapshot), .finalTranscript(let id, let transcript))
            where snapshot.id == id:
            state = .postProcessing(snapshot, transcript)
            return [.postProcess(id, transcript)]

        case (.transcribing(let snapshot, _), .finalTranscript(let id, let transcript))
            where snapshot.id == id:
            state = .postProcessing(snapshot, transcript)
            return [.postProcess(id, transcript)]

        case (.postProcessing(let snapshot, _), .postProcessingCompleted(let id, let transcript))
            where snapshot.id == id:
            state = .persisting(snapshot, transcript)
            return [.persistRecovery(id, transcript)]

        case (.persisting(_, let transcript), .recoveryPersisted(let id, _)):
            return [.persistPendingRecord(id, transcript)]

        case (.persisting(_, _), .recoveryPersistenceFailed(let id, let transcript)):
            state = .failed(FailureState(
                sessionID: id,
                failure: .historyWriteFailed,
                recoverableTranscript: transcript
            ))
            return [.showPersistentRecovery(id, transcript)]

        case (.persisting(let snapshot, let transcript), .pendingRecordPersisted(let id, let recordID))
            where snapshot.id == id:
            state = .delivering(session: snapshot, recordID: recordID, transcript: transcript)
            return [.deliver(id, recordID: recordID, transcript: transcript)]

        case (.persisting(let snapshot, _), .historyPersistenceFailed(let id, let transcript))
            where snapshot.id == id:
            state = .delivering(session: snapshot, recordID: nil, transcript: transcript)
            return [.deliver(id, recordID: nil, transcript: transcript)]

        case (.delivering(let snapshot, let recordID, let transcript), .deliveryCompleted(let id, let result))
            where snapshot.id == id:
            let mayAutoDismiss = result.verification != .failed
            state = .confirmation(ConfirmationState(
                sessionID: id,
                recordID: recordID,
                transcript: transcript,
                delivery: result,
                mayAutoDismiss: mayAutoDismiss
            ))
            if let recordID {
                return [.updateHistory(id, recordID: recordID, result)]
            }
            return []

        case (.confirmation(let confirmation), .historyOutcomeUpdated(let id))
            where confirmation.sessionID == id:
            return confirmation.mayAutoDismiss ? [.hideOverlay(after: .milliseconds(500))] : []

        case (.confirmation(let confirmation), .historyOutcomeUpdateFailed(let id))
            where confirmation.sessionID == id:
            state = .confirmation(ConfirmationState(
                sessionID: confirmation.sessionID,
                recordID: confirmation.recordID,
                transcript: confirmation.transcript,
                delivery: confirmation.delivery,
                mayAutoDismiss: false
            ))
            return [.showPersistentRecovery(id, confirmation.transcript)]

        case (.confirmation(let confirmation), .confirmationExpired(let id))
            where confirmation.sessionID == id && confirmation.mayAutoDismiss:
            return [.cleanup(id)]

        case (.cancelling(let activeID), .cleanupCompleted(let id)) where activeID == id:
            state = .idle
            return [.hideOverlay(after: .zero)]

        case (_, .failed(let id, let failure)):
            let recoverable = recoverableTranscript(from: state)
            state = .failed(FailureState(
                sessionID: id,
                failure: failure,
                recoverableTranscript: recoverable
            ))
            return id.map { [.cancelSession($0), .cleanup($0)] } ?? []

        default:
            return []
        }
    }

    private static func advanceArming(
        state: inout DictationState,
        arming: ArmingSession
    ) -> [DictationEffect] {
        guard arming.captureStarted, arming.engineReady else {
            state = .arming(arming)
            return []
        }

        if arming.releasedAt == nil {
            state = .listening(arming.snapshot)
            return [.scheduleMaximumDuration(arming.snapshot.id, after: maximumDuration)]
        }

        guard arming.captureStopped else {
            state = .arming(arming)
            return []
        }

        state = .finalizing(arming.snapshot)
        return [.finalizeRecognition(arming.snapshot.id)]
    }

    private static func clamped(_ value: Double) -> Double {
        min(max(value, 0), 1)
    }

    private static func recoverableTranscript(from state: DictationState) -> FinalTranscript? {
        switch state {
        case .postProcessing(_, let transcript),
             .persisting(_, let transcript),
             .delivering(_, _, let transcript):
            return transcript
        case .confirmation(let confirmation):
            return confirmation.transcript
        case .failed(let failure):
            return failure.recoverableTranscript
        default:
            return nil
        }
    }
}
