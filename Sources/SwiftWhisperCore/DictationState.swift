import Foundation

public struct SessionID: RawRepresentable, Hashable, Sendable, Codable {
    public let rawValue: UUID

    public init(rawValue: UUID = UUID()) {
        self.rawValue = rawValue
    }
}

public struct AudioLevel: Sendable, Equatable {
    public let rms: Float
    public let peak: Float

    public init(rms: Float, peak: Float) {
        self.rms = rms
        self.peak = peak
    }
}

public struct SessionSnapshot: Sendable, Equatable {
    public let id: SessionID
    public let startedAt: ContinuousClock.Instant
    public let modelID: ASRModelID
    public let localeIdentifier: String
    public let sourceApplicationBundleID: String?
    public var partialText: String
    public var level: AudioLevel

    public init(
        id: SessionID = SessionID(),
        startedAt: ContinuousClock.Instant,
        modelID: ASRModelID,
        localeIdentifier: String,
        sourceApplicationBundleID: String? = nil,
        partialText: String = "",
        level: AudioLevel = AudioLevel(rms: 0, peak: 0)
    ) {
        self.id = id
        self.startedAt = startedAt
        self.modelID = modelID
        self.localeIdentifier = localeIdentifier
        self.sourceApplicationBundleID = sourceApplicationBundleID
        self.partialText = partialText
        self.level = level
    }
}

public struct ArmingSession: Sendable, Equatable {
    public var snapshot: SessionSnapshot
    public var captureStarted: Bool
    public var captureStopped: Bool
    public var engineReady: Bool
    public var releasedAt: ContinuousClock.Instant?

    public init(snapshot: SessionSnapshot) {
        self.snapshot = snapshot
        self.captureStarted = false
        self.captureStopped = false
        self.engineReady = false
        self.releasedAt = nil
    }
}

public struct ConfirmationState: Sendable, Equatable {
    public let sessionID: SessionID
    public let recordID: UUID?
    public let transcript: FinalTranscript
    public let delivery: DeliveryResult
    public let mayAutoDismiss: Bool

    public init(
        sessionID: SessionID,
        recordID: UUID?,
        transcript: FinalTranscript,
        delivery: DeliveryResult,
        mayAutoDismiss: Bool
    ) {
        self.sessionID = sessionID
        self.recordID = recordID
        self.transcript = transcript
        self.delivery = delivery
        self.mayAutoDismiss = mayAutoDismiss
    }
}

public struct FailureState: Sendable, Equatable {
    public let sessionID: SessionID?
    public let failure: DictationFailure
    public let recoverableTranscript: FinalTranscript?

    public init(
        sessionID: SessionID?,
        failure: DictationFailure,
        recoverableTranscript: FinalTranscript? = nil
    ) {
        self.sessionID = sessionID
        self.failure = failure
        self.recoverableTranscript = recoverableTranscript
    }
}

public enum DictationState: Sendable, Equatable {
    case idle
    case arming(ArmingSession)
    case listening(SessionSnapshot)
    case finalizing(SessionSnapshot)
    case transcribing(SessionSnapshot, progress: Double?)
    case postProcessing(SessionSnapshot, FinalTranscript)
    case persisting(SessionSnapshot, FinalTranscript)
    case delivering(session: SessionSnapshot, recordID: UUID?, transcript: FinalTranscript)
    case confirmation(ConfirmationState)
    case cancelling(SessionID)
    case failed(FailureState)
}

public enum DictationAction: Sendable, Equatable {
    case wakePressed(SessionSnapshot)
    case wakeReleased(at: ContinuousClock.Instant)
    case engineReady(SessionID)
    case captureStarted(SessionID)
    case captureStopped(SessionID)
    case recognitionFinalizationStarted(SessionID, progressSupported: Bool)
    case audioLevel(SessionID, AudioLevel)
    case partialTranscript(SessionID, String)
    case transcriptionProgress(SessionID, Double)
    case finalTranscript(SessionID, FinalTranscript)
    case postProcessingCompleted(SessionID, FinalTranscript)
    case recoveryPersisted(SessionID, recordID: UUID)
    case recoveryPersistenceFailed(SessionID, transcript: FinalTranscript)
    case pendingRecordPersisted(SessionID, recordID: UUID)
    case historyPersistenceFailed(SessionID, transcript: FinalTranscript)
    case deliveryCompleted(SessionID, DeliveryResult)
    case historyOutcomeUpdated(SessionID)
    case historyOutcomeUpdateFailed(SessionID)
    case cancelRequested(at: ContinuousClock.Instant)
    case maximumDurationElapsed(SessionID)
    case failed(SessionID?, DictationFailure)
    case confirmationExpired(SessionID)
    case cleanupCompleted(SessionID)
}

public enum DictationEffect: Sendable, Equatable {
    case prepareSession(SessionSnapshot)
    case startCapture(SessionID)
    case finishCapture(SessionID)
    case finalizeRecognition(SessionID)
    case postProcess(SessionID, FinalTranscript)
    case persistRecovery(SessionID, FinalTranscript)
    case persistPendingRecord(SessionID, FinalTranscript)
    case cancelSession(SessionID)
    case deliver(SessionID, recordID: UUID?, transcript: FinalTranscript)
    case updateHistory(SessionID, recordID: UUID, DeliveryResult)
    case scheduleMaximumDuration(SessionID, after: Duration)
    case showPersistentRecovery(SessionID, FinalTranscript)
    case cleanup(SessionID)
    case showOverlay
    case hideOverlay(after: Duration)
}
