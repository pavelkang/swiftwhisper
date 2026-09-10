import AppKit
import Combine
import Foundation

@MainActor
final class DictationController: ObservableObject {
  private static let accidentalPressThreshold: Duration = .milliseconds(120)

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
      case .preparing: "Listening"
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
  @Published private(set) var audioLevel: Float = 0
  @Published private(set) var lastTranscript: String?
  @Published private(set) var permissionSnapshot: PermissionSnapshot?
  @Published private(set) var isRequestingPermissions = false
  @Published private(set) var smartPolishAvailability = SmartPolishService.availability

  private let hotKeyMonitor = CGEventTapHotKeyMonitor()
  private let audioCapture = AudioCaptureService()
  private let speechEngine = SpeechEngineRouter()
  private let smartPolish = SmartPolishService()
  private let permissionService = PermissionService()
  private let textDelivery = AccessibilityTextDeliveryService()

  private var monitorTask: Task<Void, Never>?
  private var monitoringRetryTask: Task<Void, Never>?
  private var preparationTask: Task<Void, Never>?
  private var frameTask: Task<Void, Never>?
  private var levelTask: Task<Void, Never>?
  private var eventTask: Task<Void, Never>?
  private var finishingTask: Task<Void, Never>?
  private var polishingTask: Task<Void, Never>?
  private var resetTask: Task<Void, Never>?
  private var activeSession: (any ASRSession)?
  private var focusSnapshot: FocusSnapshot?
  private var pressedAt: ContinuousClock.Instant?
  private var activeActivationMode: DictationActivationMode?
  private var releasePending = false
  private var isFinishing = false
  private var didDeliverCurrentSession = false
  private var shouldRecordHistorySession = false
  private var currentHistorySamples: [Float] = []

  init() {
    Task {
      await refreshPermissions()
      await prepareSelectedLanguageAssets()
      await smartPolish.prepareIfEnabled()
    }
  }

  func prepareSelectedLanguageAssets() async {
    do {
      try await speechEngine.prepareSelected(context: currentRecognitionContext)
    } catch {
      DiagnosticsLog.shared.record("speech.prepare_failed", error: error)
    }
  }

  func prepareSmartPolish() async {
    await smartPolish.prepareIfEnabled()
    smartPolishAvailability = SmartPolishService.availability
  }

  func startMonitoring() {
    guard monitorTask == nil else { return }
    monitoringRetryTask?.cancel()
    monitoringRetryTask = nil
    monitorTask = Task { [weak self] in
      guard let self else { return }
      do {
        let events = try await hotKeyMonitor.events(for: .defaultBinding)
        if displayState == .error("Enable Input Monitoring to use Right Option.") {
          displayState = .idle
        }
        for await event in events {
          guard !Task.isCancelled else { return }
          await handle(event)
        }
      } catch {
        guard !Task.isCancelled else { return }
        DiagnosticsLog.shared.record("shortcut.monitor_failed", error: error)
        monitorTask = nil
        displayState = .error("Enable Input Monitoring to use Right Option.")
        await refreshPermissions()
        scheduleMonitoringRetry()
      }
    }
  }

  func stopMonitoring() {
    monitorTask?.cancel()
    monitorTask = nil
    monitoringRetryTask?.cancel()
    monitoringRetryTask = nil
    Task { await hotKeyMonitor.stop() }
  }

  private func scheduleMonitoringRetry() {
    guard monitoringRetryTask == nil else { return }
    monitoringRetryTask = Task { [weak self] in
      while !Task.isCancelled {
        try? await Task.sleep(for: .seconds(1))
        guard !Task.isCancelled, let self else { return }
        let snapshot = await permissionService.currentSnapshot()
        await refreshPermissions()
        guard snapshot.inputMonitoring == .trusted else { continue }
        monitoringRetryTask = nil
        startMonitoring()
        return
      }
    }
  }

  func requestPermissions() {
    Task { [weak self] in
      guard let self else { return }
      isRequestingPermissions = true
      defer { isRequestingPermissions = false }
      _ = await permissionService.requestMicrophone()
      _ = await permissionService.requestSpeechRecognition()
      let inputMonitoring = await permissionService.requestInputMonitoring()
      await refreshPermissions()

      // Both Input Monitoring and Accessibility use synchronous TCC prompts.
      // Stop here while Input Monitoring is unresolved so the Accessibility
      // prompt cannot replace it before macOS presents it.
      guard inputMonitoring == .trusted else { return }

      _ = await permissionService.requestAccessibility()
      await refreshPermissions()
      stopMonitoring()
      startMonitoring()
    }
  }

  func requestInputMonitoring() {
    Task { [weak self] in
      guard let self else { return }
      isRequestingPermissions = true
      defer { isRequestingPermissions = false }
      let status = await permissionService.requestInputMonitoring()
      await refreshPermissions()
      guard status == .trusted else { return }
      stopMonitoring()
      startMonitoring()
    }
  }

  func cancelDictation() {
    guard !didDeliverCurrentSession,
      activeSession != nil || preparationTask != nil
    else { return }
    let session = activeSession
    cleanupTasks()
    Task {
      await audioCapture.cancel()
      await session?.cancel()
    }
    activeSession = nil
    focusSnapshot = nil
    pressedAt = nil
    activeActivationMode = nil
    releasePending = false
    isFinishing = false
    didDeliverCurrentSession = false
    shouldRecordHistorySession = false
    currentHistorySamples.removeAll(keepingCapacity: false)
    displayState = .idle
    audioLevel = 0
  }

  func refreshPermissions() async {
    permissionSnapshot = await permissionService.currentSnapshot()
  }

  private func handle(_ event: HotKeyEvent) async {
    switch event {
    case .pressed(let time):
      if activeActivationMode == .pressToToggle,
        activeSession != nil || preparationTask != nil
      {
        finishDictation(enforceMinimumDuration: false)
      } else {
        beginDictation(at: time)
      }
    case .released:
      if activeActivationMode == .holdToSpeak {
        finishDictation(enforceMinimumDuration: true)
      }
    case .cancelRequested:
      cancelDictation()
    case .tapDisabled, .physicalStateInvalidated:
      cancelDictation()
    }
  }

  private func beginDictation(at time: ContinuousClock.Instant) {
    guard activeSession == nil, preparationTask == nil, !isFinishing else { return }

    resetTask?.cancel()
    resetTask = nil
    DiagnosticsLog.shared.record("dictation.started")
    pressedAt = time
    activeActivationMode = DictationActivationMode.selected
    releasePending = false
    didDeliverCurrentSession = false
    shouldRecordHistorySession = DictationHistorySetting.isEnabled
    currentHistorySamples.removeAll(keepingCapacity: true)
    focusSnapshot = textDelivery.snapshotFocus()
    audioLevel = 0
    displayState = .preparing

    preparationTask = Task { [weak self] in
      guard let self else { return }
      do {
        async let capture = audioCapture.start(format: .pcm16kMono)
        async let speech = speechEngine.makeSession(
          context: currentRecognitionContext
        )
        let (captureSession, speechSession) = try await (capture, speech)
        await attach(capture: captureSession, speech: speechSession)
      } catch {
        guard !Task.isCancelled else { return }
        fail(error)
      }
    }
  }

  private var currentRecognitionContext: RecognitionContext {
    let language = TranscriptionLanguage.selected
    return RecognitionContext(
      localeIdentifier: language.localeIdentifier,
      languageHint: language.modelLanguageHint,
      vocabulary: VocabularyStore.shared.entries
    )
  }

  private func attach(capture: AudioCaptureSession, speech: any ASRSession) async {
    preparationTask = nil
    activeSession = speech
    displayState = releasePending ? .processing : .listening

    frameTask = Task { [weak self] in
      do {
        for try await frame in capture.frames {
          if self?.shouldRecordHistorySession == true {
            self?.currentHistorySamples.append(contentsOf: frame.samples)
          }
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

  private func finishDictation(enforceMinimumDuration: Bool) {
    guard let pressedAt else { return }
    let heldFor = pressedAt.duration(to: ContinuousClock().now)
    if enforceMinimumDuration, heldFor < Self.accidentalPressThreshold {
      cancelDictation()
      return
    }
    releasePending = true
    displayState = .processing

    guard let activeSession else { return }
    finishingTask?.cancel()
    finishingTask = Task { [weak self] in
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
    case .partial(let text):
      lastTranscript = text
    case .final(let text):
      polishingTask?.cancel()
      polishingTask = Task { [weak self] in
        guard let self else { return }
        let polished = await smartPolish.polish(text)
        guard !Task.isCancelled else { return }
        complete(text: polished)
      }
    }
  }

  private func complete(text: String) {
    guard !didDeliverCurrentSession else { return }
    didDeliverCurrentSession = true

    let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !normalized.isEmpty else {
      showNoSpeech()
      return
    }

    lastTranscript = normalized
    if shouldRecordHistorySession {
      DictationHistoryStore.shared.add(
        transcript: normalized,
        samples: currentHistorySamples
      )
    }
    let delivery =
      focusSnapshot.map { textDelivery.deliver(normalized, to: $0) }
      ?? .notInserted

    switch delivery {
    case .inserted, .duplicateSuppressed:
      DiagnosticsLog.shared.record("dictation.delivered")
      displayState = .confirmation("Inserted")
    case .notInserted:
      DiagnosticsLog.shared.record("dictation.copy_fallback")
      displayState = .confirmation("Copy available")
    }
    scheduleReset()
  }

  private func setAudioLevel(_ level: Float) {
    audioLevel = min(max(level * 8, 0), 1)
  }

  private func showNoSpeech() {
    DiagnosticsLog.shared.record("dictation.no_speech")
    displayState = .confirmation("No speech detected")
    scheduleReset()
  }

  private func fail(_ error: any Error) {
    DiagnosticsLog.shared.record("dictation.failed", error: error)
    let session = activeSession
    Task {
      await audioCapture.cancel()
      await session?.cancel()
    }
    preparationTask?.cancel()
    frameTask?.cancel()
    levelTask?.cancel()
    eventTask?.cancel()
    finishingTask?.cancel()
    polishingTask?.cancel()
    preparationTask = nil
    frameTask = nil
    levelTask = nil
    eventTask = nil
    finishingTask = nil
    polishingTask = nil
    activeSession = nil
    pressedAt = nil
    activeActivationMode = nil
    releasePending = false
    isFinishing = false
    shouldRecordHistorySession = false
    currentHistorySamples.removeAll(keepingCapacity: false)
    displayState = .error(Self.userMessage(for: error))
    scheduleReset(after: .seconds(2))
  }

  private func scheduleReset(after delay: Duration = .milliseconds(700)) {
    resetTask?.cancel()
    resetTask = Task { [weak self] in
      do { try await Task.sleep(for: delay) } catch { return }
      guard !Task.isCancelled, let self else { return }
      resetSession()
    }
  }

  private func resetSession() {
    cleanupTasks()
    activeSession = nil
    focusSnapshot = nil
    pressedAt = nil
    activeActivationMode = nil
    releasePending = false
    isFinishing = false
    didDeliverCurrentSession = false
    shouldRecordHistorySession = false
    currentHistorySamples.removeAll(keepingCapacity: false)
    audioLevel = 0
    displayState = .idle
  }

  private func cleanupTasks() {
    resetTask?.cancel()
    resetTask = nil
    preparationTask?.cancel()
    frameTask?.cancel()
    levelTask?.cancel()
    eventTask?.cancel()
    finishingTask?.cancel()
    polishingTask?.cancel()
    preparationTask = nil
    frameTask = nil
    levelTask = nil
    eventTask = nil
    finishingTask = nil
    polishingTask = nil
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
        .insertionFailed(let reason):
        return reason
      default: return "Dictation failed"
      }
    }
    return error.localizedDescription
  }
}
