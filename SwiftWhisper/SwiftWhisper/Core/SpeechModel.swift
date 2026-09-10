import Foundation

enum SpeechModel: String, CaseIterable, Identifiable, Sendable {
  case appleDictation
  case moonshineEnglish
  case qwen3ASR06B

  static let storageKey = "speechModel"
  static let defaultModel = SpeechModel.appleDictation

  var id: String { rawValue }

  var name: String {
    switch self {
    case .appleDictation: "Apple Dictation"
    case .moonshineEnglish: "Moonshine Medium Streaming"
    case .qwen3ASR06B: "Qwen3-ASR 0.6B"
    }
  }

  var detail: String {
    switch self {
    case .appleDictation: "Built into macOS · Uses the selected language"
    case .moonshineEnglish: "English · Fast streaming model"
    case .qwen3ASR06B: "English + Chinese · Automatic language detection"
    }
  }

  var approximateSize: String? {
    switch self {
    case .appleDictation: nil
    case .moonshineEnglish: "~500 MB"
    case .qwen3ASR06B: "~715 MB"
    }
  }

  var systemImage: String {
    switch self {
    case .appleDictation: "apple.logo"
    case .moonshineEnglish: "moon.stars.fill"
    case .qwen3ASR06B: "sparkles.rectangle.stack"
    }
  }

  var requiresDownload: Bool { self != .appleDictation }

  static var selected: SpeechModel {
    let rawValue = UserDefaults.standard.string(forKey: storageKey)
    return rawValue.flatMap(SpeechModel.init(rawValue:)) ?? defaultModel
  }
}
