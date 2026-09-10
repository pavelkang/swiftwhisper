import AVFoundation
#if os(macOS)
import AudioToolbox
#endif
import Foundation

enum AudioCaptureError: Error, Sendable {
  case alreadyRunning
  case microphoneUnavailable
  case unsupportedFormat
  case conversionFailed
  case deviceConfigurationFailed(OSStatus)
}

actor AudioCaptureService: AudioCapturing {
  private var engine: AVAudioEngine?
  private var emitter: PCMFrameEmitter?

  init() {}

  func start(format: AudioFormatSpec) async throws -> AudioCaptureSession {
    guard engine == nil else { throw AudioCaptureError.alreadyRunning }
    guard format.channelCount == 1,
      let tapFormat = AVAudioFormat(
        standardFormatWithSampleRate: format.sampleRate,
        channels: AVAudioChannelCount(format.channelCount)
      )
    else {
      throw AudioCaptureError.unsupportedFormat
    }

    let engine = AVAudioEngine()
#if os(iOS)
    let audioSession = AVAudioSession.sharedInstance()
    try audioSession.setCategory(.record, mode: .measurement, options: [.allowBluetoothHFP])
    try audioSession.setActive(true)
#endif
    let input = engine.inputNode
#if os(macOS)
    guard let audioUnit = input.audioUnit else {
      throw AudioCaptureError.microphoneUnavailable
    }
    try AudioInputDeviceDiscovery.applySelectedDevice(to: audioUnit)
#endif
    let inputFormat = input.outputFormat(forBus: 0)
    guard inputFormat.sampleRate > 0, inputFormat.channelCount > 0 else {
      throw AudioCaptureError.microphoneUnavailable
    }
    guard let converter = AVAudioConverter(from: inputFormat, to: tapFormat) else {
      throw AudioCaptureError.unsupportedFormat
    }

    let pair = PCMFrameEmitter.makeStreams(
      converter: converter,
      outputFormat: tapFormat
    )
    let emitter = pair.emitter

    input.installTap(onBus: 0, bufferSize: 1_024, format: inputFormat) { buffer, _ in
      emitter.consume(buffer: buffer)
    }

    engine.prepare()
    do {
      try engine.start()
    } catch {
      input.removeTap(onBus: 0)
      emitter.finish(throwing: error)
      throw error
    }

    self.engine = engine
    self.emitter = emitter
    return AudioCaptureSession(frames: pair.frames, levels: pair.levels)
  }

  func stop() async throws {
    guard let engine else { return }
    engine.inputNode.removeTap(onBus: 0)
    engine.stop()
    emitter?.finish()
    self.engine = nil
    emitter = nil
#if os(iOS)
    try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
#endif
  }

  func cancel() async {
    try? await stop()
  }
}

private final class PCMFrameEmitter: @unchecked Sendable {
  struct Streams {
    let emitter: PCMFrameEmitter
    let frames: AsyncThrowingStream<PCMFrame, any Error>
    let levels: AsyncStream<AudioLevel>
  }

  private let lock = NSLock()
  private let converter: AVAudioConverter
  private let outputFormat: AVAudioFormat
  private var sequenceNumber: UInt64 = 0
  private var frameContinuation: AsyncThrowingStream<PCMFrame, any Error>.Continuation?
  private var levelContinuation: AsyncStream<AudioLevel>.Continuation?

  static func makeStreams(
    converter: AVAudioConverter,
    outputFormat: AVAudioFormat
  ) -> Streams {
    var frameContinuation: AsyncThrowingStream<PCMFrame, any Error>.Continuation?
    let frames = AsyncThrowingStream<PCMFrame, any Error>(bufferingPolicy: .bufferingNewest(128)) {
      frameContinuation = $0
    }

    var levelContinuation: AsyncStream<AudioLevel>.Continuation?
    let levels = AsyncStream<AudioLevel>(bufferingPolicy: .bufferingNewest(8)) {
      levelContinuation = $0
    }

    let emitter = PCMFrameEmitter(
      converter: converter,
      outputFormat: outputFormat,
      frameContinuation: frameContinuation,
      levelContinuation: levelContinuation
    )
    return Streams(emitter: emitter, frames: frames, levels: levels)
  }

  private init(
    converter: AVAudioConverter,
    outputFormat: AVAudioFormat,
    frameContinuation: AsyncThrowingStream<PCMFrame, any Error>.Continuation?,
    levelContinuation: AsyncStream<AudioLevel>.Continuation?
  ) {
    self.converter = converter
    self.outputFormat = outputFormat
    self.frameContinuation = frameContinuation
    self.levelContinuation = levelContinuation
  }

  func consume(buffer: AVAudioPCMBuffer) {
    let rateRatio = outputFormat.sampleRate / buffer.format.sampleRate
    let outputCapacity = AVAudioFrameCount(
      ceil(Double(buffer.frameLength) * rateRatio) + 32
    )
    guard
      let convertedBuffer = AVAudioPCMBuffer(
        pcmFormat: outputFormat,
        frameCapacity: outputCapacity
      )
    else {
      finish(throwing: AudioCaptureError.conversionFailed)
      return
    }

    let inputProvider = ConverterInputProvider(buffer: buffer)
    var conversionError: NSError?
    let status = converter.convert(to: convertedBuffer, error: &conversionError) { _, inputStatus in
      inputProvider.provide(status: inputStatus)
    }
    guard conversionError == nil, status != .error else {
      finish(throwing: conversionError ?? AudioCaptureError.conversionFailed)
      return
    }

    guard let channel = convertedBuffer.floatChannelData?.pointee else { return }
    let count = Int(convertedBuffer.frameLength)
    guard count > 0 else { return }

    let samples = Array(UnsafeBufferPointer(start: channel, count: count))
    var sumSquares: Float = 0
    var peak: Float = 0
    for sample in samples {
      sumSquares += sample * sample
      peak = max(peak, abs(sample))
    }
    let rms = sqrt(sumSquares / Float(count))

    lock.lock()
    let currentSequence = sequenceNumber
    sequenceNumber += 1
    let frameContinuation = self.frameContinuation
    let levelContinuation = self.levelContinuation
    lock.unlock()

    frameContinuation?.yield(
      PCMFrame(
        samples: samples,
        format: AudioFormatSpec(
          sampleRate: convertedBuffer.format.sampleRate,
          channelCount: Int(convertedBuffer.format.channelCount)
        ),
        sequenceNumber: currentSequence
      ))
    levelContinuation?.yield(AudioLevel(rms: rms, peak: peak))
  }

  func finish(throwing error: (any Error)? = nil) {
    lock.lock()
    let frameContinuation = self.frameContinuation
    let levelContinuation = self.levelContinuation
    self.frameContinuation = nil
    self.levelContinuation = nil
    lock.unlock()

    if let error {
      frameContinuation?.finish(throwing: error)
    } else {
      frameContinuation?.finish()
    }
    levelContinuation?.finish()
  }
}

private final class ConverterInputProvider: @unchecked Sendable {
  private var buffer: AVAudioPCMBuffer?

  init(buffer: AVAudioPCMBuffer) {
    self.buffer = buffer
  }

  func provide(
    status: UnsafeMutablePointer<AVAudioConverterInputStatus>
  ) -> AVAudioBuffer? {
    guard let buffer else {
      status.pointee = .noDataNow
      return nil
    }
    self.buffer = nil
    status.pointee = .haveData
    return buffer
  }
}
