import Foundation
import FoundationModels
import Qwen3Chat

actor SmartPolishService {
  private static let instructions = """
    You format speech-recognition transcripts for direct insertion into another app.
    Add appropriate punctuation, capitalization, and paragraph breaks.
    Preserve every spoken word, name, and number exactly. Do not add, remove, replace,
    summarize, answer, explain, or wrap the transcript in quotes or Markdown.
    Return only the formatted transcript.
    """

  private var preparedSession: LanguageModelSession?
  private var preparedQwenModel: Qwen3DenseChat?

  nonisolated static var availability: SmartPolishAvailability {
    if SmartPolishModel.selected == .qwen3Compact {
      return PolishModelManager.isInstalled ? .available : .modelNotDownloaded
    }
    return switch SystemLanguageModel.default.availability {
    case .available:
      .available
    case .unavailable(.appleIntelligenceNotEnabled):
      .appleIntelligenceDisabled
    case .unavailable(.modelNotReady):
      .modelPreparing
    case .unavailable(.deviceNotEligible):
      .deviceNotEligible
    @unknown default:
      .modelPreparing
    }
  }

  func prepareIfEnabled() async {
    guard SmartPolishSetting.isEnabled else {
      preparedSession = nil
      preparedQwenModel = nil
      return
    }
    switch SmartPolishModel.selected {
    case .appleIntelligence:
      preparedQwenModel = nil
      guard SystemLanguageModel.default.isAvailable else { return }
      let session = makeSession()
      session.prewarm()
      preparedSession = session
    case .qwen3Compact:
      preparedSession = nil
      guard PolishModelManager.isInstalled else { return }
      do {
        preparedQwenModel = try Qwen3DenseChat.fromDirectory(
          PolishModelManager.modelDirectory
        )
      } catch {
        DiagnosticsLog.shared.record("polish.prepare_failed", error: error)
        preparedQwenModel = nil
      }
    }
  }

  func polish(_ transcript: String) async -> String {
    let original = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
    guard SmartPolishSetting.isEnabled, !original.isEmpty else { return original }

    do {
      try Task.checkCancellation()
      let response: String
      switch SmartPolishModel.selected {
      case .appleIntelligence:
        guard SystemLanguageModel.default.isAvailable else { return original }
        let session = preparedSession ?? makeSession()
        preparedSession = nil
        response = try await session.respond(
          to: "Format this transcript:\n<transcript>\n\(original)\n</transcript>",
          options: GenerationOptions(
            sampling: .greedy,
            maximumResponseTokens: responseTokenLimit(for: original)
          )
        ).content
      case .qwen3Compact:
        guard PolishModelManager.isInstalled else { return original }
        let model: Qwen3DenseChat
        if let preparedQwenModel {
          model = preparedQwenModel
        } else {
          model = try Qwen3DenseChat.fromDirectory(PolishModelManager.modelDirectory)
          preparedQwenModel = model
        }
        response = try await qwenResponse(for: original, using: model)
      }
      try Task.checkCancellation()

      let candidate = sanitize(response)
      guard preservesSpokenContent(candidate, from: original) else {
        DiagnosticsLog.shared.record("polish.content_change_rejected")
        return original
      }
      return candidate
    } catch {
      DiagnosticsLog.shared.record("polish.failed_using_original", error: error)
      return original
    }
  }

  private func qwenResponse(for transcript: String, using model: Qwen3DenseChat) async throws
    -> String
  {
    let messages = [
      ChatMessage(role: .system, content: Self.instructions),
      ChatMessage(
        role: .user,
        content: "/no_think\nFormat this transcript:\n<transcript>\n\(transcript)\n</transcript>"
      ),
    ]
    var response = ""
    for try await fragment in model.generateStream(
      messages: messages,
      sampling: ChatSamplingConfig(
        temperature: 0,
        topK: 1,
        topP: 1,
        maxTokens: responseTokenLimit(for: transcript),
        repetitionPenalty: 1
      )
    ) {
      try Task.checkCancellation()
      response += fragment
    }
    return response
  }

  private func makeSession() -> LanguageModelSession {
    LanguageModelSession(instructions: Self.instructions)
  }

  private func responseTokenLimit(for transcript: String) -> Int {
    min(max(transcript.count / 2 + 64, 128), 2_048)
  }

  private func sanitize(_ response: String) -> String {
    var text = response.trimmingCharacters(in: .whitespacesAndNewlines)
    if let end = text.range(of: "</think>") {
      text = String(text[end.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
    } else if let start = text.range(of: "<think>") {
      text = String(text[..<start.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
    }
    if text.hasPrefix("```") && text.hasSuffix("```") {
      text.removeFirst(3)
      text.removeLast(3)
      text = text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    return text
  }

  private func preservesSpokenContent(_ candidate: String, from original: String) -> Bool {
    guard !candidate.isEmpty else { return false }
    return contentFingerprint(candidate) == contentFingerprint(original)
  }

  private func contentFingerprint(_ text: String) -> String {
    text.folding(options: [.caseInsensitive], locale: .current)
      .unicodeScalars
      .filter { CharacterSet.alphanumerics.contains($0) }
      .map(String.init)
      .joined()
  }
}
