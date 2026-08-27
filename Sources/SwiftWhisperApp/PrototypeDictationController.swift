import AppKit
import Combine
import Foundation
import SwiftWhisperCore
import SwiftWhisperPlatform

@MainActor
final class PrototypeDictationController: ObservableObject {
    enum DisplayState: Equatable {
        case idle
        case preparing
        case listening
        case processing
        case confirmation(String)
        case error(String)

        var label: String {
            switch self {
            case .idle: "Ready"
            case .preparing: "Preparing…"
            case .listening: "Listening"
            case .processing: "Processing…"
            case .confirmation(let message): message
            case .error(let message): message
            }
        }

        var keepsOverlayVisible: Bool {
            self != .idle
        }
    }

    @Published private(set) var displayState: DisplayState = .idle
    @Published private(set) var partialText = ""
    @Published private(set) var audioLevel: Float = 0
    @Published private(set) var history: [String] = []
    @Published private(set) var permissionSummary = "Permissions not checked"

    private let hotKeyMonitor = CGEventTapHotKeyMonitor()
    private let audioCapture = AudioCaptureService()
    private let speechEngine = AppleSpeechEngine()
    private let permissionService = PermissionService()
    private let textDelivery = AccessibilityTextDeliveryService()

    private var monitorTask: Task<Void, Never>?
    private var preparationTask: Task<Void, Never>?
    private var frameTask: Task<Void, Never>?
    private var levelTask: Task<Void, Never>?
    private var eventTask: Task<Void, Never>?
    private var activeSession: (any ASRSession)?
    private var focusSnapshot: FocusSnapshot?
    private var pressedAt: ContinuousClock.Instant?
    private var releasePending = false
    private var isFinishing = false

    init() {
        Task { await refreshPermissions() }
    }

    func startMonitoring() {
        guard monitorTask == nil else { return }
        monitorTask = Task { [weak self] in
            guard let self else { return }
            do {
                let events = try await hotKeyMonitor.events(for: .defaultBinding)
                for await event in events {
                    guard !Task.isCancelled else { return }
                    await handle(event)
                }
            } catch {
                displayState = .error("Enable Input Monitoring to use Right Option.")
            }
        }
    }

    func stopMonitoring() {
        monitorTask?.cancel()
        monitorTask = nil
        Task { await hotKeyMonitor.stop() }
    }

    func requestPermissions() {
        Task { [weak self] in
            guard let self else { return }
            _ = await permissionService.requestMicrophone()
            _ = await permissionService.requestSpeechRecognition()
            _ = await permissionService.requestInputMonitoring()
            _ = await permissionService.requestAccessibility()
            await refreshPermissions()
            stopMonitoring()
            startMonitoring()
        }
    }

    func toggleManualDictation() {
        if displayState == .listening || displayState == .preparing {
            finishDictation()
        } else if displayState == .idle || isTerminalState {
            beginDictation(at: ContinuousClock().now)
        }
    }

    func cancelDictation() {
        guard activeSession != nil || preparationTask != nil else { return }
        let session = activeSession
        cleanupTasks()
        Task {
            await audioCapture.cancel()
            await session?.cancel()
        }
        activeSession = nil
        focusSnapshot = nil
        releasePending = false
        isFinishing = false
        displayState = .idle
        partialText = ""
        audioLevel = 0
    }

    func refreshPermissions() async {
        let snapshot = await permissionService.currentSnapshot()
        let microphone = snapshot.microphone == .granted ? "Mic ✓" : "Mic —"
        let speech = snapshot.speechRecognition == .granted ? "Speech ✓" : "Speech —"
        let input = snapshot.inputMonitoring == .trusted ? "Input ✓" : "Input —"
        let accessibility = snapshot.accessibility == .trusted ? "AX ✓" : "AX —"
        permissionSummary = [microphone, speech, input, accessibility].joined(separator: "  ")
    }

    private var isTerminalState: Bool {
        switch displayState {
        case .confirmation, .error: true
        default: false
        }
    }

    private func handle(_ event: HotKeyEvent) async {
        switch event {
        case .pressed(let time):
            beginDictation(at: time)
        case .released:
            finishDictation()
        case .escapePressed:
            cancelDictation()
        case .tapDisabled, .physicalStateInvalidated:
            cancelDictation()
        }
    }

    private func beginDictation(at time: ContinuousClock.Instant) {
        guard activeSession == nil, preparationTask == nil, !isFinishing else { return }

        pressedAt = time
        releasePending = false
        focusSnapshot = textDelivery.snapshotFocus()
        partialText = ""
        audioLevel = 0
        displayState = .preparing

        preparationTask = Task { [weak self] in
            guard let self else { return }
            do {
                async let capture = audioCapture.start(format: .pcm16kMono)
                async let speech = speechEngine.makeSession(context: RecognitionContext(
                    localeIdentifier: Locale.current.identifier,
                    sourceApplicationBundleID: focusSnapshot?.bundleIdentifier
                ))
                let (captureSession, speechSession) = try await (capture, speech)
                await attach(capture: captureSession, speech: speechSession)
            } catch {
                fail(error)
            }
        }
    }

    private func attach(capture: AudioCaptureSession, speech: any ASRSession) async {
        preparationTask = nil
        activeSession = speech
        displayState = releasePending ? .processing : .listening

        frameTask = Task { [weak self] in
            do {
                for try await frame in capture.frames {
                    try await speech.append(frame)
                }
            } catch {
                self?.fail(error)
            }
        }

        levelTask = Task { [weak self] in
            for await level in capture.levels {
                guard !Task.isCancelled else { return }
                self?.setAudioLevel(level.rms)
            }
        }

        eventTask = Task { [weak self] in
            do {
                for try await event in speech.events {
                    guard !Task.isCancelled else { return }
                    self?.handleSpeechEvent(event)
                }
            } catch DictationFailure.noSpeechDetected {
                self?.showNoSpeech()
            } catch {
                self?.fail(error)
            }
        }

        if releasePending {
            await finishAttachedSession(speech)
        }
    }

    private func finishDictation() {
        guard let pressedAt else { return }
        let heldFor = pressedAt.duration(to: ContinuousClock().now)
        if heldFor < DictationReducer.accidentalPressThreshold {
            cancelDictation()
            return
        }
        releasePending = true
        displayState = .processing

        guard let activeSession else { return }
        Task { [weak self] in
            await self?.finishAttachedSession(activeSession)
        }
    }

    private func finishAttachedSession(_ speech: any ASRSession) async {
        guard !isFinishing else { return }
        isFinishing = true
        do {
            try await audioCapture.stop()
            await frameTask?.value
            try await speech.finish()
        } catch DictationFailure.noSpeechDetected {
            showNoSpeech()
        } catch {
            fail(error)
        }
    }

    private func handleSpeechEvent(_ event: ASREvent) {
        switch event {
        case .ready:
            if !releasePending { displayState = .listening }
        case .partial(let segments):
            partialText = joinedText(segments)
        case .final(let segments):
            complete(text: joinedText(segments))
        case .progress:
            displayState = .processing
        }
    }

    private func complete(text: String) {
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else {
            showNoSpeech()
            return
        }

        history.insert(normalized, at: 0)
        let result: DeliveryResult
        if let focusSnapshot {
            result = textDelivery.deliver(normalized, to: focusSnapshot)
        } else {
            result = DeliveryResult(
                method: .historyOnly,
                verification: .failed,
                userMessage: "Saved to History."
            )
        }

        switch result.verification {
        case .verified:
            displayState = .confirmation("Inserted")
        case .acceptedUnverified:
            displayState = .confirmation("Sent — saved in History")
        case .failed:
            displayState = .confirmation("Saved to History")
        }
        scheduleReset()
    }

    private func joinedText(_ segments: [TranscriptSegment]) -> String {
        segments.map(\.text).joined(separator: " ")
            .replacingOccurrences(of: "  ", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func setAudioLevel(_ level: Float) {
        audioLevel = min(max(level * 8, 0), 1)
    }

    private func showNoSpeech() {
        displayState = .confirmation("No speech detected")
        scheduleReset()
    }

    private func fail(_ error: any Error) {
        let session = activeSession
        Task {
            await audioCapture.cancel()
            await session?.cancel()
        }
        preparationTask?.cancel()
        frameTask?.cancel()
        levelTask?.cancel()
        eventTask?.cancel()
        preparationTask = nil
        frameTask = nil
        levelTask = nil
        eventTask = nil
        activeSession = nil
        releasePending = false
        isFinishing = false
        displayState = .error(Self.userMessage(for: error))
        scheduleReset(after: .seconds(2))
    }

    private func scheduleReset(after delay: Duration = .milliseconds(700)) {
        Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard let self else { return }
            resetSession()
        }
    }

    private func resetSession() {
        cleanupTasks()
        activeSession = nil
        focusSnapshot = nil
        pressedAt = nil
        releasePending = false
        isFinishing = false
        partialText = ""
        audioLevel = 0
        displayState = .idle
    }

    private func cleanupTasks() {
        preparationTask?.cancel()
        frameTask?.cancel()
        levelTask?.cancel()
        eventTask?.cancel()
        preparationTask = nil
        frameTask = nil
        levelTask = nil
        eventTask = nil
    }

    private static func userMessage(for error: any Error) -> String {
        if let failure = error as? DictationFailure {
            switch failure {
            case .noSpeechDetected: return "No speech detected"
            case .permissionMissing(.microphone): return "Microphone access is required"
            case .permissionMissing(.speechRecognition): return "Speech access is required"
            case .permissionMissing(.inputMonitoring): return "Input Monitoring is required"
            case .permissionMissing(.accessibility): return "Accessibility is required"
            case .modelIncompatible(_, let reason),
                 .modelLoadFailed(_, let reason),
                 .transcriptionFailed(let reason),
                 .insertionFailed(let reason): return reason
            default: return "Dictation failed"
            }
        }
        return error.localizedDescription
    }
}
