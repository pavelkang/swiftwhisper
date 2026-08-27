import AVFoundation
import CoreMedia
import Foundation
import Speech
import SwiftWhisperCore

public actor AppleSpeechEngine: ASREngine {
    public nonisolated let modelID = ASRModelID.appleDictation

    public init() {}

    public func requiredAudioFormat() async throws -> AudioFormatSpec {
        .pcm16kMono
    }

    public func makeSession(context: RecognitionContext) async throws -> any ASRSession {
        try await AppleSpeechSession(context: context)
    }

    public func unload() async {
        await SpeechModels.endRetention()
    }
}

private actor AppleSpeechSession: ASRSession {
    nonisolated let events: AsyncThrowingStream<ASREvent, any Error>

    private let analyzer: SpeechAnalyzer
    private let inputContinuation: AsyncStream<AnalyzerInput>.Continuation
    private let eventContinuation: AsyncThrowingStream<ASREvent, any Error>.Continuation
    private let localeIdentifier: String
    private let format: AVAudioFormat

    private var analyzerTask: Task<Void, any Error>?
    private var resultTask: Task<Void, any Error>?
    private var segmentsByStart: [Int64: TranscriptSegment] = [:]
    private var didFinish = false

    init(context: RecognitionContext) async throws {
        let requestedLocale = Locale(identifier: context.localeIdentifier)
        guard let locale = await DictationTranscriber.supportedLocale(equivalentTo: requestedLocale) else {
            throw DictationFailure.modelIncompatible(
                .appleDictation,
                reason: "Apple Dictation does not support \(context.localeIdentifier)."
            )
        }

        let transcriber = DictationTranscriber(
            locale: locale,
            contentHints: [],
            transcriptionOptions: context.punctuationEnabled ? [.punctuation] : [],
            reportingOptions: [.volatileResults, .frequentFinalization],
            attributeOptions: [.audioTimeRange, .transcriptionConfidence]
        )
        let analyzer = SpeechAnalyzer(
            modules: [transcriber],
            options: SpeechAnalyzer.Options(
                priority: .userInitiated,
                modelRetention: .lingering
            )
        )
        guard let format = AVAudioFormat(
            standardFormatWithSampleRate: 16_000,
            channels: 1
        ) else {
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
        self.localeIdentifier = locale.identifier
        self.format = format

        try await analyzer.prepareToAnalyze(in: format)

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
        guard let buffer = AVAudioPCMBuffer(
            pcmFormat: format,
            frameCapacity: AVAudioFrameCount(frame.samples.count)
        ), let channel = buffer.floatChannelData?.pointee else {
            throw DictationFailure.transcriptionFailed(reason: "Could not allocate audio buffer.")
        }
        buffer.frameLength = AVAudioFrameCount(frame.samples.count)
        frame.samples.withUnsafeBufferPointer { source in
            guard let baseAddress = source.baseAddress else { return }
            channel.update(from: baseAddress, count: source.count)
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
        let text = segments.map(\.text).joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            eventContinuation.finish(throwing: DictationFailure.noSpeechDetected)
            return
        }
        eventContinuation.yield(.final(segments))
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
        let text = String(result.text.characters)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        let startSeconds = result.range.start.seconds
        let durationSeconds = result.range.duration.seconds
        let key = Int64((startSeconds * 1_000).rounded())
        segmentsByStart[key] = TranscriptSegment(
            text: text,
            start: .milliseconds(key),
            duration: .milliseconds(Int64((durationSeconds * 1_000).rounded()))
        )
        eventContinuation.yield(.partial(orderedSegments))
    }

    private func fail(_ error: any Error) {
        guard !didFinish else { return }
        didFinish = true
        eventContinuation.finish(throwing: error)
    }
}
