import AVFoundation
import CoreMedia
import Foundation
import Speech

actor AppleSpeechEngine: ASREngine {
  private var preparedLocaleIdentifiers: Set<String> = []

  init() {}

  func makeSession(context: RecognitionContext) async throws -> any ASRSession {
    try await prepareAssets(localeIdentifier: context.localeIdentifier)
    return try await AppleSpeechSession(context: context)
  }

  func prepareAssets(localeIdentifier: String) async throws {
    guard !preparedLocaleIdentifiers.contains(localeIdentifier) else { return }

    let requestedLocale = Locale(identifier: localeIdentifier)
    guard let locale = await DictationTranscriber.supportedLocale(equivalentTo: requestedLocale)
    else {
      throw DictationFailure.modelIncompatible(
        .appleDictation,
        reason: "Apple Dictation does not support \(localeIdentifier)."
      )
    }

    let transcriber = DictationTranscriber(locale: locale, preset: .progressiveShortDictation)
    if let installationRequest = try await AssetInventory.assetInstallationRequest(
      supporting: [transcriber]
    ) {
      try await installationRequest.downloadAndInstall()
    }
    preparedLocaleIdentifiers.insert(localeIdentifier)
  }
}

private actor AppleSpeechSession: ASRSession {
  nonisolated let events: AsyncThrowingStream<ASREvent, any Error>

  private let analyzer: SpeechAnalyzer
  private let inputContinuation: AsyncStream<AnalyzerInput>.Continuation
  private let eventContinuation: AsyncThrowingStream<ASREvent, any Error>.Continuation
  private let analyzerFormat: AVAudioFormat
  private let segmentSeparator: String

  private var analyzerTask: Task<Void, any Error>?
  private var resultTask: Task<Void, any Error>?
  private var segmentsByStart: [Int64: TranscriptSegment] = [:]
  private var didFinish = false

  init(context: RecognitionContext) async throws {
    let requestedLocale = Locale(identifier: context.localeIdentifier)
    guard let locale = await DictationTranscriber.supportedLocale(equivalentTo: requestedLocale)
    else {
      throw DictationFailure.modelIncompatible(
        .appleDictation,
        reason: "Apple Dictation does not support \(context.localeIdentifier)."
      )
    }

    let transcriber = DictationTranscriber(
      locale: locale,
      contentHints: [],
      transcriptionOptions: context.punctuationEnabled ? [.punctuation] : [],
      reportingOptions: [.frequentFinalization],
      attributeOptions: [.audioTimeRange, .transcriptionConfidence]
    )
    let analyzer = SpeechAnalyzer(
      modules: [transcriber],
      options: SpeechAnalyzer.Options(
        priority: .userInitiated,
        modelRetention: .lingering
      )
    )
    if !context.vocabulary.isEmpty {
      let analysisContext = AnalysisContext()
      analysisContext.contextualStrings[.general] = context.vocabulary
      try await analyzer.setContext(analysisContext)
    }
    guard
      let captureFormat = AVAudioFormat(
        standardFormatWithSampleRate: 16_000,
        channels: 1
      )
    else {
      throw AudioCaptureError.unsupportedFormat
    }
    guard
      let analyzerFormat = await SpeechAnalyzer.bestAvailableAudioFormat(
        compatibleWith: [transcriber],
        considering: captureFormat
      )
    else {
      throw DictationFailure.modelIncompatible(
        .appleDictation,
        reason: "Apple Dictation audio assets are unavailable."
      )
    }
    guard analyzerFormat.commonFormat == .pcmFormatInt16,
      analyzerFormat.sampleRate == captureFormat.sampleRate,
      analyzerFormat.channelCount == captureFormat.channelCount
    else {
      throw AudioCaptureError.unsupportedFormat
    }

    var inputContinuation: AsyncStream<AnalyzerInput>.Continuation?
    let inputStream = AsyncStream<AnalyzerInput>(bufferingPolicy: .bufferingNewest(256)) {
      inputContinuation = $0
    }

    var eventContinuation: AsyncThrowingStream<ASREvent, any Error>.Continuation?
    let events = AsyncThrowingStream<ASREvent, any Error>(bufferingPolicy: .bufferingNewest(32)) {
      eventContinuation = $0
    }

    guard let inputContinuation, let eventContinuation else {
      throw DictationFailure.transcriptionFailed(reason: "Could not initialize streams.")
    }

    self.analyzer = analyzer
    self.inputContinuation = inputContinuation
    self.eventContinuation = eventContinuation
    self.events = events
    self.analyzerFormat = analyzerFormat
    self.segmentSeparator = locale.identifier.lowercased().hasPrefix("zh") ? "" : " "

    try await analyzer.prepareToAnalyze(in: analyzerFormat)

    analyzerTask = Task {
      try await analyzer.start(inputSequence: inputStream)
    }
    resultTask = Task { [weak self] in
      do {
        for try await result in transcriber.results {
          await self?.consume(result)
        }
      } catch {
        await self?.fail(error)
      }
    }
    eventContinuation.yield(.ready)
  }

  func append(_ frame: PCMFrame) async throws {
    guard !didFinish else { return }
    guard frame.format == .pcm16kMono else {
      throw DictationFailure.transcriptionFailed(reason: "Unexpected audio format.")
    }
    guard
      let buffer = AVAudioPCMBuffer(
        pcmFormat: analyzerFormat,
        frameCapacity: AVAudioFrameCount(frame.samples.count)
      ), let channel = buffer.int16ChannelData?.pointee
    else {
      throw DictationFailure.transcriptionFailed(reason: "Could not allocate audio buffer.")
    }
    buffer.frameLength = AVAudioFrameCount(frame.samples.count)
    for (index, sample) in frame.samples.enumerated() {
      let clamped = max(-1, min(1, sample))
      channel[index] = Int16((clamped * Float(Int16.max)).rounded())
    }
    inputContinuation.yield(AnalyzerInput(buffer: buffer))
  }

  func finish() async throws {
    guard !didFinish else { return }
    didFinish = true
    inputContinuation.finish()
    try await analyzer.finalizeAndFinishThroughEndOfInput()
    try await analyzerTask?.value
    try await resultTask?.value

    let segments = orderedSegments
    let text = segments.map(\.text).joined(separator: segmentSeparator)
      .trimmingCharacters(in: .whitespacesAndNewlines)
    guard !text.isEmpty else {
      eventContinuation.finish(throwing: DictationFailure.noSpeechDetected)
      return
    }
    eventContinuation.yield(.final(text))
    eventContinuation.finish()
  }

  func cancel() async {
    guard !didFinish else { return }
    didFinish = true
    inputContinuation.finish()
    analyzerTask?.cancel()
    resultTask?.cancel()
    await analyzer.cancelAndFinishNow()
    eventContinuation.finish(throwing: DictationFailure.cancelled)
  }

  private var orderedSegments: [TranscriptSegment] {
    segmentsByStart.keys.sorted().compactMap { segmentsByStart[$0] }
  }

  private func consume(_ result: DictationTranscriber.Result) {
    guard result.isFinal else { return }

    let text = String(result.text.characters)
      .trimmingCharacters(in: .whitespacesAndNewlines)
    guard !text.isEmpty else { return }

    let startSeconds = result.range.start.seconds
    let key = Int64((startSeconds * 1_000).rounded())
    segmentsByStart[key] = TranscriptSegment(text: text)
  }

  private func fail(_ error: any Error) {
    guard !didFinish else { return }
    didFinish = true
    eventContinuation.finish(throwing: error)
  }
}
