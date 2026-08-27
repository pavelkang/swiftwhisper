import Foundation

public struct ASRModelID: RawRepresentable, Codable, Hashable, Sendable {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public static let appleDictation = Self(rawValue: "apple-dictation")
}

public enum ASRFamily: String, Codable, Sendable {
    case appleDictation
    case whisper
    case moonshine
    case qwen3ASR
    case parakeet
}

public struct RecognitionContext: Sendable, Equatable {
    public let localeIdentifier: String
    public let vocabularyHints: [String]
    public let punctuationEnabled: Bool
    public let sourceApplicationBundleID: String?

    public init(
        localeIdentifier: String,
        vocabularyHints: [String] = [],
        punctuationEnabled: Bool = true,
        sourceApplicationBundleID: String? = nil
    ) {
        self.localeIdentifier = localeIdentifier
        self.vocabularyHints = vocabularyHints
        self.punctuationEnabled = punctuationEnabled
        self.sourceApplicationBundleID = sourceApplicationBundleID
    }
}

public struct TranscriptSegment: Sendable, Equatable {
    public let id: UUID
    public let text: String
    public let start: Duration?
    public let duration: Duration?
    public let confidence: Double?

    public init(
        id: UUID = UUID(),
        text: String,
        start: Duration? = nil,
        duration: Duration? = nil,
        confidence: Double? = nil
    ) {
        self.id = id
        self.text = text
        self.start = start
        self.duration = duration
        self.confidence = confidence
    }
}

public struct FinalTranscript: Sendable, Equatable {
    public let text: String
    public let segments: [TranscriptSegment]
    public let modelID: ASRModelID
    public let localeIdentifier: String
    public let audioDuration: Duration

    public init(
        text: String,
        segments: [TranscriptSegment],
        modelID: ASRModelID,
        localeIdentifier: String,
        audioDuration: Duration
    ) {
        self.text = text
        self.segments = segments
        self.modelID = modelID
        self.localeIdentifier = localeIdentifier
        self.audioDuration = audioDuration
    }
}

public enum ASREvent: Sendable, Equatable {
    case ready
    case partial([TranscriptSegment])
    case final([TranscriptSegment])
    case progress(Double)
}

public struct AudioFormatSpec: Sendable, Equatable {
    public let sampleRate: Double
    public let channelCount: Int

    public init(sampleRate: Double, channelCount: Int) {
        self.sampleRate = sampleRate
        self.channelCount = channelCount
    }

    public static let pcm16kMono = Self(sampleRate: 16_000, channelCount: 1)
}

public struct PCMFrame: Sendable, Equatable {
    public let samples: [Float]
    public let format: AudioFormatSpec
    public let sequenceNumber: UInt64

    public init(samples: [Float], format: AudioFormatSpec, sequenceNumber: UInt64) {
        self.samples = samples
        self.format = format
        self.sequenceNumber = sequenceNumber
    }
}

public struct AudioCaptureSession: Sendable {
    public let frames: AsyncThrowingStream<PCMFrame, any Error>
    public let levels: AsyncStream<AudioLevel>

    public init(
        frames: AsyncThrowingStream<PCMFrame, any Error>,
        levels: AsyncStream<AudioLevel>
    ) {
        self.frames = frames
        self.levels = levels
    }
}

public protocol AudioCapturing: Sendable {
    func start(format: AudioFormatSpec) async throws -> AudioCaptureSession
    func stop() async throws
    func cancel() async
}

public protocol ASRSession: Sendable {
    var events: AsyncThrowingStream<ASREvent, any Error> { get }
    func append(_ frame: PCMFrame) async throws
    func finish() async throws
    func cancel() async
}

public protocol ASREngine: Sendable {
    var modelID: ASRModelID { get }
    func requiredAudioFormat() async throws -> AudioFormatSpec
    func makeSession(context: RecognitionContext) async throws -> any ASRSession
    func unload() async
}
