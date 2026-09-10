import AVFoundation
import Combine
import Foundation
import Speech

@MainActor
final class MobileDictationController: ObservableObject {
  enum State: Equatable {
    case idle
    case preparing
    case recording
    case processing
    case complete
    case error(String)
  }

  @Published private(set) var state: State = .idle
  @Published private(set) var transcript: String?

  private let capture = AudioCaptureService()
  private let speech = AppleSpeechEngine()
  private let smartPolish = SmartPolishService()
  private var session: (any ASRSession)?
  private var frameTask: Task<Void, Never>?
  private var eventTask: Task<Void, Never>?
  private var startTask: Task<Void, Never>?
  private var samples: [Float] = []

  init() {
    Task { await smartPolish.prepareIfEnabled() }
  }

  func preparePolish() async {
    await smartPolish.prepareIfEnabled()
  }

  func toggleDictation() {
    switch state {
    case .recording:
      stop()
    case .idle, .complete, .error:
      start()
    case .preparing, .processing:
      break
    }
  }

  func requestPermissions() async {
    _ = await AVCaptureDevice.requestAccess(for: .audio)
    _ = await withCheckedContinuation { continuation in
      SFSpeechRecognizer.requestAuthorization { status in
        continuation.resume(returning: status)
      }
    }
  }

  func cancel() {
    guard state == .recording || state == .preparing else { return }
    let activeSession = session
    cleanupTasks()
    Task {
      await capture.cancel()
      await activeSession?.cancel()
    }
    session = nil
    samples.removeAll(keepingCapacity: false)
    state = .idle
  }

  private func start() {
    guard AVCaptureDevice.authorizationStatus(for: .audio) != .denied else {
      state = .error("Enable Microphone access in Settings to dictate.")
      return
    }
    transcript = nil
    samples.removeAll(keepingCapacity: true)
    state = .preparing

    startTask = Task { [weak self] in
      guard let self else { return }
      do {
        if AVCaptureDevice.authorizationStatus(for: .audio) == .notDetermined {
          guard await AVCaptureDevice.requestAccess(for: .audio) else {
            throw DictationFailure.permissionMissing(.microphone)
          }
        }
        let language = TranscriptionLanguage.selected
        async let captureSession = capture.start(format: .pcm16kMono)
        async let speechSession = speech.makeSession(
          context: RecognitionContext(
            localeIdentifier: language.localeIdentifier,
            languageHint: language.modelLanguageHint,
            vocabulary: VocabularyStore.shared.entries
          )
        )
        let (audio, recognizer) = try await (captureSession, speechSession)
        attach(audio: audio, recognizer: recognizer)
      } catch {
        fail(error)
      }
    }
  }

  private func attach(audio: AudioCaptureSession, recognizer: any ASRSession) {
    startTask = nil
    session = recognizer
    state = .recording

    frameTask = Task { [weak self] in
      do {
        for try await frame in audio.frames {
          guard let self else { return }
          samples.append(contentsOf: frame.samples)
          try await recognizer.append(frame)
        }
      } catch {
        self?.fail(error)
      }
    }

    eventTask = Task { [weak self] in
      do {
        for try await event in recognizer.events {
          guard let self else { return }
          switch event {
          case .ready: break
          case .partial(let text): transcript = text
          case .final(let text):
            Task { [weak self] in
              guard let self else { return }
              let polished = await smartPolish.polish(text)
              guard !Task.isCancelled else { return }
              complete(polished)
            }
          }
        }
      } catch DictationFailure.noSpeechDetected {
        self?.fail(DictationFailure.noSpeechDetected)
      } catch {
        self?.fail(error)
      }
    }
  }

  private func stop() {
    guard let session else { return }
    state = .processing
    Task { [weak self] in
      guard let self else { return }
      do {
        try await capture.stop()
        await frameTask?.value
        try await session.finish()
      } catch {
        fail(error)
      }
    }
  }

  private func complete(_ text: String) {
    let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !normalized.isEmpty else {
      fail(DictationFailure.noSpeechDetected)
      return
    }
    transcript = normalized
    DictationHistoryStore.shared.add(transcript: normalized, samples: samples)
    cleanupTasks()
    session = nil
    samples.removeAll(keepingCapacity: false)
    state = .complete
  }

  private func fail(_ error: any Error) {
    let message: String
    switch error {
    case DictationFailure.noSpeechDetected:
      message = "No speech was detected. Try again and speak a little closer to the microphone."
    case DictationFailure.permissionMissing:
      message = "Microphone access is required to dictate."
    default:
      message = error.localizedDescription
    }
    let activeSession = session
    cleanupTasks()
    Task {
      await capture.cancel()
      await activeSession?.cancel()
    }
    session = nil
    samples.removeAll(keepingCapacity: false)
    state = .error(message)
  }

  private func cleanupTasks() {
    startTask?.cancel()
    frameTask?.cancel()
    eventTask?.cancel()
    startTask = nil
    frameTask = nil
    eventTask = nil
  }
}
