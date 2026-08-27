import AVFoundation
import Foundation
import SwiftWhisperCore

public enum AudioCaptureError: Error, Sendable {
    case alreadyRunning
    case microphoneUnavailable
    case unsupportedFormat
}

public actor AudioCaptureService: AudioCapturing {
    private var engine: AVAudioEngine?
    private var emitter: PCMFrameEmitter?

    public init() {}

    public func start(format: AudioFormatSpec) async throws -> AudioCaptureSession {
        guard engine == nil else { throw AudioCaptureError.alreadyRunning }
        guard format.channelCount == 1,
              let tapFormat = AVAudioFormat(
                standardFormatWithSampleRate: format.sampleRate,
                channels: AVAudioChannelCount(format.channelCount)
              ) else {
            throw AudioCaptureError.unsupportedFormat
        }

        let engine = AVAudioEngine()
        let input = engine.inputNode
        guard input.inputFormat(forBus: 0).sampleRate > 0 else {
            throw AudioCaptureError.microphoneUnavailable
        }

        let pair = PCMFrameEmitter.makeStreams()
        let emitter = pair.emitter

        input.installTap(onBus: 0, bufferSize: 1_024, format: tapFormat) { buffer, _ in
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

    public func stop() async throws {
        guard let engine else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        emitter?.finish()
        self.engine = nil
        emitter = nil
    }

    public func cancel() async {
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
    private var sequenceNumber: UInt64 = 0
    private var frameContinuation: AsyncThrowingStream<PCMFrame, any Error>.Continuation?
    private var levelContinuation: AsyncStream<AudioLevel>.Continuation?

    static func makeStreams() -> Streams {
        var frameContinuation: AsyncThrowingStream<PCMFrame, any Error>.Continuation?
        let frames = AsyncThrowingStream<PCMFrame, any Error>(bufferingPolicy: .bufferingNewest(128)) {
            frameContinuation = $0
        }

        var levelContinuation: AsyncStream<AudioLevel>.Continuation?
        let levels = AsyncStream<AudioLevel>(bufferingPolicy: .bufferingNewest(8)) {
            levelContinuation = $0
        }

        let emitter = PCMFrameEmitter(
            frameContinuation: frameContinuation,
            levelContinuation: levelContinuation
        )
        return Streams(emitter: emitter, frames: frames, levels: levels)
    }

    private init(
        frameContinuation: AsyncThrowingStream<PCMFrame, any Error>.Continuation?,
        levelContinuation: AsyncStream<AudioLevel>.Continuation?
    ) {
        self.frameContinuation = frameContinuation
        self.levelContinuation = levelContinuation
    }

    func consume(buffer: AVAudioPCMBuffer) {
        guard let channel = buffer.floatChannelData?.pointee else { return }
        let count = Int(buffer.frameLength)
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

        frameContinuation?.yield(PCMFrame(
            samples: samples,
            format: AudioFormatSpec(
                sampleRate: buffer.format.sampleRate,
                channelCount: Int(buffer.format.channelCount)
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
