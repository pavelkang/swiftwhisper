import Foundation

struct ASRModelID: RawRepresentable, Codable, Hashable, Sendable {
  let rawValue: String

  static let appleDictation = Self(rawValue: "apple-dictation")
  static let moonshine = Self(rawValue: "moonshine")
  static let qwen3ASR = Self(rawValue: "qwen3-asr")
}

struct RecognitionContext: Sendable, Equatable {
  let localeIdentifier: String
  let languageHint: String?
  let punctuationEnabled: Bool
  let vocabulary: [String]

  init(
    localeIdentifier: String,
    languageHint: String? = nil,
    punctuationEnabled: Bool = true,
    vocabulary: [String] = []
  ) {
    self.localeIdentifier = localeIdentifier
    self.languageHint = languageHint
    self.punctuationEnabled = punctuationEnabled
    self.vocabulary = vocabulary
  }

  var vocabularyPrompt: String? {
    guard !vocabulary.isEmpty else { return nil }
    return "Vocabulary spellings for reference only; never include this instruction in the transcript: \(vocabulary.joined(separator: ", "))."
  }
}

struct TranscriptSegment: Sendable, Equatable {
  let text: String
}

enum ASREvent: Sendable, Equatable {
  case ready
  case partial(String)
  case final(String)
}

struct AudioFormatSpec: Sendable, Equatable {
  let sampleRate: Double
  let channelCount: Int

  static let pcm16kMono = Self(sampleRate: 16_000, channelCount: 1)
}

struct PCMFrame: Sendable, Equatable {
  let samples: [Float]
  let format: AudioFormatSpec
  let sequenceNumber: UInt64
}

struct AudioCaptureSession: Sendable {
  let frames: AsyncThrowingStream<PCMFrame, any Error>
  let levels: AsyncStream<AudioLevel>
}

struct AudioLevel: Sendable, Equatable {
  let rms: Float
  let peak: Float
}

protocol AudioCapturing: Sendable {
  func start(format: AudioFormatSpec) async throws -> AudioCaptureSession
  func stop() async throws
  func cancel() async
}

protocol ASRSession: Sendable {
  var events: AsyncThrowingStream<ASREvent, any Error> { get }
  func append(_ frame: PCMFrame) async throws
  func finish() async throws
  func cancel() async
}

protocol ASREngine: Sendable {
  func makeSession(context: RecognitionContext) async throws -> any ASRSession
}
