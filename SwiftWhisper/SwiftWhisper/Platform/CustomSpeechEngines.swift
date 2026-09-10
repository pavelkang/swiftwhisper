import Foundation
import MoonshineVoice
import Qwen3ASR

actor SpeechEngineRouter: ASREngine {
  private let apple = AppleSpeechEngine()
  private let moonshine = MoonshineSpeechEngine()
  private let qwen = QwenSpeechEngine()

  func makeSession(context: RecognitionContext) async throws -> any ASRSession {
    switch SpeechModel.selected {
    case .appleDictation:
      return try await apple.makeSession(context: context)
    case .moonshineEnglish:
      return try await moonshine.makeSession(context: context)
    case .qwen3ASR06B:
      return try await qwen.makeSession(context: context)
    }
  }

  func prepareSelected(context: RecognitionContext) async throws {
    switch SpeechModel.selected {
    case .appleDictation:
      try await apple.prepareAssets(localeIdentifier: context.localeIdentifier)
    case .moonshineEnglish:
      try await moonshine.prepare()
    case .qwen3ASR06B:
      try await qwen.prepare()
    }
  }
}

private actor MoonshineSpeechEngine: ASREngine {
  private var transcriber: Transcriber?

  func prepare() throws {
    guard transcriber == nil else { return }
    guard FileManager.default.fileExists(atPath: SpeechModelManager.moonshineDirectory.path) else {
      throw DictationFailure.modelLoadFailed(
        .moonshine,
        reason: "Download the Moonshine model in Settings first."
      )
    }
    transcriber = try Transcriber(
      modelPath: SpeechModelManager.moonshineDirectory.path,
      modelArch: .mediumStreaming
    )
  }

  func makeSession(context: RecognitionContext) async throws -> any ASRSession {
    try prepare()
    guard let transcriber else { throw DictationFailure.cancelled }
    try transcriber.setKeyterms(context.vocabulary)
    let stream = try transcriber.createStream(
      updateInterval: .greatestFiniteMagnitude
    )
    try stream.start()
    return MoonshineStreamingSession(stream: SendableMoonshineStream(stream))
  }
}

private actor QwenSpeechEngine: ASREngine {
  private var model: Qwen3ASRModel?

  func prepare() async throws {
    guard model == nil else { return }
    guard FileManager.default.fileExists(atPath: SpeechModelManager.qwenDirectory.path) else {
      throw DictationFailure.modelLoadFailed(
        .qwen3ASR,
        reason: "Download the Qwen3-ASR model in Settings first."
      )
    }
    model = try await Qwen3ASRModel.fromPretrained(
      modelId: SpeechModelManager.qwenModelID,
      cacheDir: SpeechModelManager.qwenDirectory,
      offlineMode: true
    )
  }

  func makeSession(context: RecognitionContext) async throws -> any ASRSession {
    try await prepare()
    return QwenStreamingSession(
      languageHint: context.languageHint,
      vocabularyContext: context.vocabularyPrompt
    ) { [weak self] samples, languageHint, vocabularyContext in
        guard let self else { throw DictationFailure.cancelled }
        return try await self.transcribe(
          samples,
          languageHint: languageHint,
          vocabularyContext: vocabularyContext
        )
      }
  }

  private func transcribe(
    _ samples: [Float],
    languageHint: String?,
    vocabularyContext: String?
  ) async throws -> String {
    try Task.checkCancellation()
    try await prepare()
    guard let model else { throw DictationFailure.cancelled }
    let text = model.transcribe(
      audio: samples,
      sampleRate: 16_000,
      language: languageHint,
      context: vocabularyContext
    )
    try Task.checkCancellation()
    return Self.removingLeakedVocabularyContext(from: text, context: vocabularyContext)
  }

  private static func removingLeakedVocabularyContext(
    from transcript: String,
    context: String?
  ) -> String {
    guard let context, !context.isEmpty else { return transcript }

    var cleaned = transcript
    while let range = cleaned.range(
      of: context,
      options: [.caseInsensitive, .diacriticInsensitive]
    ) {
      cleaned.removeSubrange(range)
    }
    return cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
  }
}

private actor MoonshineStreamingSession: ASRSession {
  nonisolated let events: AsyncThrowingStream<ASREvent, any Error>

  private static let updateSampleCount = 8_000

  private let continuation: AsyncThrowingStream<ASREvent, any Error>.Continuation
  private let stream: SendableMoonshineStream
  private var samplesSinceUpdate = 0
  private var latestText = ""
  private var didTerminate = false

  init(stream: SendableMoonshineStream) {
    var continuation: AsyncThrowingStream<ASREvent, any Error>.Continuation?
    events = AsyncThrowingStream(bufferingPolicy: .bufferingNewest(8)) {
      continuation = $0
    }
    self.continuation = continuation!
    self.stream = stream
    continuation?.yield(.ready)
  }

  func append(_ frame: PCMFrame) throws {
    guard !didTerminate else { return }
    guard frame.format == .pcm16kMono else {
      throw DictationFailure.transcriptionFailed(reason: "Unexpected audio format.")
    }

    try stream.value.addAudio(frame.samples, sampleRate: 16_000)
    samplesSinceUpdate += frame.samples.count
    if samplesSinceUpdate >= Self.updateSampleCount {
      samplesSinceUpdate = 0
      publish(try stream.value.updateTranscription())
    }
  }

  func finish() throws {
    guard !didTerminate else { return }
    didTerminate = true
    defer { stream.value.close() }

    // Capture the forced update while the stream is still active. `stop()` also
    // drains Moonshine internally, but that implicit update is only delivered
    // to SDK listeners and its return value is otherwise lost.
    publish(try stream.value.updateTranscription(flags: TranscribeStreamFlags.flagForceUpdate))
    try stream.value.stop()
    let text = latestText.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !text.isEmpty else {
      continuation.finish(throwing: DictationFailure.noSpeechDetected)
      return
    }
    continuation.yield(.final(text))
    continuation.finish()
  }

  func cancel() {
    guard !didTerminate else { return }
    didTerminate = true
    stream.value.close()
    continuation.finish(throwing: DictationFailure.cancelled)
  }

  private func publish(_ transcript: Transcript) {
    let text = transcript.lines.map(\.text).joined(separator: " ")
      .trimmingCharacters(in: .whitespacesAndNewlines)
    guard !text.isEmpty, text != latestText else { return }
    latestText = text
    continuation.yield(.partial(text))
  }
}

/// Moonshine's stream type predates Swift 6 Sendable annotations. Each wrapped
/// value is created for and exclusively owned by one Moonshine session actor.
private final class SendableMoonshineStream: @unchecked Sendable {
  let value: MoonshineVoice.Stream

  init(_ value: MoonshineVoice.Stream) {
    self.value = value
  }
}

private actor QwenStreamingSession: ASRSession {
  typealias Transcribe = @Sendable ([Float], String?, String?) async throws -> String

  nonisolated let events: AsyncThrowingStream<ASREvent, any Error>

  private static let sampleRate = 16_000
  private static let minimumSegmentSamples = sampleRate
  private static let silenceSamplesToSplit = sampleRate * 45 / 100
  private static let maximumSegmentSamples = sampleRate * 6
  private static let silenceRMSThreshold: Float = 0.012

  private let continuation: AsyncThrowingStream<ASREvent, any Error>.Continuation
  private let transcribe: Transcribe
  private let languageHint: String?
  private let vocabularyContext: String?
  private var currentSegment: [Float] = []
  private var queuedSegments: [[Float]] = []
  private var completedText = ""
  private var consecutiveSilenceSamples = 0
  private var segmentHasSpeech = false
  private var processingTask: Task<Void, Never>?
  private var terminalError: (any Error)?
  private var isFinishing = false
  private var didTerminate = false

  init(
    languageHint: String? = nil,
    vocabularyContext: String? = nil,
    transcribe: @escaping Transcribe
  ) {
    var continuation: AsyncThrowingStream<ASREvent, any Error>.Continuation?
    self.events = AsyncThrowingStream(bufferingPolicy: .bufferingNewest(8)) {
      continuation = $0
    }
    self.continuation = continuation!
    self.transcribe = transcribe
    self.languageHint = languageHint
    self.vocabularyContext = vocabularyContext
    continuation?.yield(.ready)
  }

  func append(_ frame: PCMFrame) throws {
    guard !didTerminate, !isFinishing else { return }
    guard frame.format == .pcm16kMono else {
      throw DictationFailure.transcriptionFailed(reason: "Unexpected audio format.")
    }

    currentSegment.append(contentsOf: frame.samples)
    let rms = Self.rms(of: frame.samples)
    if rms < Self.silenceRMSThreshold {
      consecutiveSilenceSamples += frame.samples.count
    } else {
      consecutiveSilenceSamples = 0
      segmentHasSpeech = true
    }

    let shouldSplitAtSilence =
      currentSegment.count >= Self.minimumSegmentSamples
      && consecutiveSilenceSamples >= Self.silenceSamplesToSplit
    if shouldSplitAtSilence || currentSegment.count >= Self.maximumSegmentSamples {
      enqueueCurrentSegment()
    }
  }

  func finish() async throws {
    guard !didTerminate, !isFinishing else { return }
    isFinishing = true
    // Never let the lightweight silence heuristic discard the user's final
    // segment. Qwen itself is the authority on whether speech was present.
    enqueueCurrentSegment(force: true)
    startProcessingIfNeeded()
    await processingTask?.value

    if let terminalError { throw terminalError }
    try Task.checkCancellation()
    guard !didTerminate else { throw DictationFailure.cancelled }
    didTerminate = true
    let text = completedText.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !text.isEmpty else {
      continuation.finish(throwing: DictationFailure.noSpeechDetected)
      return
    }
    continuation.yield(.final(text))
    continuation.finish()
  }

  func cancel() {
    guard !didTerminate else { return }
    didTerminate = true
    processingTask?.cancel()
    processingTask = nil
    currentSegment.removeAll(keepingCapacity: false)
    queuedSegments.removeAll(keepingCapacity: false)
    continuation.finish(throwing: DictationFailure.cancelled)
  }

  private func enqueueCurrentSegment(force: Bool = false) {
    guard !currentSegment.isEmpty else { return }
    if segmentHasSpeech || force {
      queuedSegments.append(currentSegment)
    }
    currentSegment.removeAll(keepingCapacity: true)
    consecutiveSilenceSamples = 0
    segmentHasSpeech = false
    startProcessingIfNeeded()
  }

  private func startProcessingIfNeeded() {
    guard processingTask == nil, !queuedSegments.isEmpty, !didTerminate else { return }
    processingTask = Task { [weak self] in
      await self?.drainSegments()
    }
  }

  private func drainSegments() async {
    while !queuedSegments.isEmpty, !didTerminate {
      let samples = queuedSegments.removeFirst()
      do {
        try Task.checkCancellation()
        let text = try await transcribe(samples, languageHint, vocabularyContext)
          .trimmingCharacters(in: .whitespacesAndNewlines)
        try Task.checkCancellation()
        guard !didTerminate else { return }
        if !text.isEmpty {
          completedText = Self.join(completedText, text, languageHint: languageHint)
          continuation.yield(.partial(completedText))
        }
      } catch {
        guard !didTerminate else { return }
        terminalError = error
        didTerminate = true
        queuedSegments.removeAll(keepingCapacity: false)
        continuation.finish(throwing: error)
        processingTask = nil
        return
      }
    }
    processingTask = nil
  }

  private static func rms(of samples: [Float]) -> Float {
    guard !samples.isEmpty else { return 0 }
    let sum = samples.reduce(Float.zero) { $0 + $1 * $1 }
    return sqrt(sum / Float(samples.count))
  }

  private static func join(_ existing: String, _ next: String, languageHint: String?) -> String {
    guard !existing.isEmpty else { return next }
    let isChinese = languageHint?.localizedCaseInsensitiveContains("chinese") == true
    return existing + (isChinese ? "" : " ") + next
  }
}
