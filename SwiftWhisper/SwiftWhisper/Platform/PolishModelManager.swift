@preconcurrency import AudioCommon
import Combine
import Foundation

@MainActor
final class PolishModelManager: ObservableObject {
  enum State: Equatable {
    case notDownloaded
    case downloading(Double?)
    case installed
    case failed(String)
  }

  static let shared = PolishModelManager()
  nonisolated static let modelID = "mlx-community/Qwen3-0.6B-4bit"
  nonisolated static let modelDirectory = FileManager.default.urls(
    for: .applicationSupportDirectory,
    in: .userDomainMask
  )[0]
    .appendingPathComponent("SwiftWhisper/Models", isDirectory: true)
    .appendingPathComponent("Polish/Qwen3-0.6B-4bit", isDirectory: true)

  @Published private(set) var state: State = .notDownloaded
  private var downloadTask: Task<Void, Never>?

  private init() {
    refresh()
  }

  nonisolated static var isInstalled: Bool {
    guard HuggingFaceDownloader.weightsExist(in: modelDirectory) else { return false }
    let requiredFiles = ["config.json", "tokenizer.json", "tokenizer_config.json"]
    return requiredFiles.allSatisfy {
      FileManager.default.fileExists(atPath: modelDirectory.appendingPathComponent($0).path)
    }
  }

  func refresh() {
    guard downloadTask == nil else { return }
    state = Self.isInstalled ? .installed : .notDownloaded
  }

  func download() {
    guard downloadTask == nil, !Self.isInstalled else { return }
    state = .downloading(nil)
    let task = Task { [weak self] in
      guard let self else { return }
      do {
        try FileManager.default.createDirectory(
          at: Self.modelDirectory,
          withIntermediateDirectories: true
        )
        try await HuggingFaceDownloader.downloadWeights(
          modelId: Self.modelID,
          to: Self.modelDirectory,
          additionalFiles: [
            "tokenizer.json", "tokenizer_config.json", "special_tokens_map.json",
            "added_tokens.json", "vocab.json", "merges.txt",
          ]
        )
        try Task.checkCancellation()
        state = .installed
      } catch is CancellationError {
        state = .notDownloaded
      } catch {
        DiagnosticsLog.shared.record("polish_model.download_failed", error: error)
        state = .failed(error.localizedDescription)
      }
      downloadTask = nil
    }
    downloadTask = task
  }

  func cancelDownload() {
    downloadTask?.cancel()
    downloadTask = nil
    state = Self.isInstalled ? .installed : .notDownloaded
  }

  func remove() throws {
    cancelDownload()
    if FileManager.default.fileExists(atPath: Self.modelDirectory.path) {
      try FileManager.default.removeItem(at: Self.modelDirectory)
    }
    if SmartPolishModel.selected == .qwen3Compact {
      UserDefaults.standard.set(
        SmartPolishModel.defaultModel.rawValue,
        forKey: SmartPolishModel.storageKey
      )
    }
    state = .notDownloaded
  }
}
