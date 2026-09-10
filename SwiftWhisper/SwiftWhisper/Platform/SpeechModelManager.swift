import AudioCommon
import Combine
import Foundation
import MoonshineVoice

@MainActor
final class SpeechModelManager: ObservableObject {
  enum State: Equatable {
    case available
    case notDownloaded
    case downloading(Double?)
    case installed
    case failed(String)
  }

  static let shared = SpeechModelManager()
  static let qwenModelID = "aufklarer/Qwen3-ASR-0.6B-MLX-4bit"

  @Published private(set) var states: [SpeechModel: State] = [:]
  private var downloadTasks: [SpeechModel: Task<Void, Never>] = [:]

  private init() {
    refresh()
  }

  func state(for model: SpeechModel) -> State {
    states[model] ?? (model.requiresDownload ? .notDownloaded : .available)
  }

  func refresh() {
    states[.appleDictation] = .available
    if downloadTasks[.moonshineEnglish] == nil {
      let spec = ModelSpec.stt(language: "en", modelArch: .mediumStreaming)
      states[.moonshineEnglish] = AssetDownloader().isModelPresent(
        root: Self.moonshineDirectory,
        spec: spec
      ) ? .installed : .notDownloaded
    }
    if downloadTasks[.qwen3ASR06B] == nil {
      states[.qwen3ASR06B] = Self.qwenBundleIsComplete ? .installed : .notDownloaded
    }
  }

  func download(_ model: SpeechModel) {
    guard model.requiresDownload, downloadTasks[model] == nil else { return }
    states[model] = .downloading(nil)

    let task = Task { [weak self] in
      guard let self else { return }
      do {
        switch model {
        case .appleDictation:
          break
        case .moonshineEnglish:
          try await downloadMoonshine()
        case .qwen3ASR06B:
          try await downloadQwen()
        }
        guard !Task.isCancelled else { return }
        states[model] = .installed
      } catch is CancellationError {
        states[model] = .notDownloaded
      } catch {
        DiagnosticsLog.shared.record("speech_model.download_failed", error: error)
        states[model] = .failed(error.localizedDescription)
      }
      downloadTasks[model] = nil
    }
    downloadTasks[model] = task
  }

  func cancelDownload(_ model: SpeechModel) {
    downloadTasks[model]?.cancel()
    downloadTasks[model] = nil
    states[model] = .notDownloaded
  }

  func remove(_ model: SpeechModel) throws {
    guard model.requiresDownload else { return }
    cancelDownload(model)
    let directory = Self.directory(for: model)
    if FileManager.default.fileExists(atPath: directory.path) {
      try FileManager.default.removeItem(at: directory)
    }
    if SpeechModel.selected == model {
      UserDefaults.standard.set(SpeechModel.defaultModel.rawValue, forKey: SpeechModel.storageKey)
    }
    states[model] = .notDownloaded
  }

  nonisolated static func directory(for model: SpeechModel) -> URL {
    switch model {
    case .appleDictation: modelsRoot
    case .moonshineEnglish: moonshineDirectory
    case .qwen3ASR06B: qwenDirectory
    }
  }

  nonisolated static let modelsRoot: URL = {
    let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    return base.appendingPathComponent("SwiftWhisper/Models", isDirectory: true)
  }()

  nonisolated static let moonshineDirectory = modelsRoot
    .appendingPathComponent("Moonshine/medium-streaming-en", isDirectory: true)

  nonisolated static let qwenDirectory = modelsRoot
    .appendingPathComponent("Qwen/Qwen3-ASR-0.6B-MLX-4bit", isDirectory: true)

  private static var qwenBundleIsComplete: Bool {
    guard HuggingFaceDownloader.weightsExist(in: qwenDirectory) else { return false }
    let required = ["config.json", "vocab.json", "merges.txt", "tokenizer_config.json"]
    return required.allSatisfy {
      FileManager.default.fileExists(atPath: qwenDirectory.appendingPathComponent($0).path)
    }
  }

  private func downloadMoonshine() async throws {
    try FileManager.default.createDirectory(
      at: Self.moonshineDirectory,
      withIntermediateDirectories: true
    )
    let spec = ModelSpec.stt(language: "en", modelArch: .mediumStreaming)
    _ = try await AssetDownloader().ensureModelPresent(
      root: Self.moonshineDirectory,
      spec: spec
    ) { [weak self] progress in
      let fileFraction: Double
      if progress.bytesTotal > 0 {
        fileFraction = Double(progress.bytesDownloaded) / Double(progress.bytesTotal)
      } else {
        fileFraction = 0
      }
      let overall = (Double(progress.fileIndex - 1) + fileFraction)
        / Double(max(progress.totalFiles, 1))
      Task { @MainActor [weak self] in
        self?.states[.moonshineEnglish] = .downloading(min(max(overall, 0), 1))
      }
    }
  }

  private func downloadQwen() async throws {
    try FileManager.default.createDirectory(
      at: Self.qwenDirectory,
      withIntermediateDirectories: true
    )
    try await HuggingFaceDownloader.downloadWeights(
      modelId: Self.qwenModelID,
      to: Self.qwenDirectory,
      additionalFiles: ["vocab.json", "merges.txt", "tokenizer_config.json"]
    )
  }
}
