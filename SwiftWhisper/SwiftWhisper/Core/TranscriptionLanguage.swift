import Foundation

enum TranscriptionLanguage: String, CaseIterable, Identifiable {
  case automatic
  case englishUS
  case chineseSimplified
  case chineseTraditional

  static let storageKey = "transcriptionLanguage"
  static let defaultLanguage = TranscriptionLanguage.automatic

  var id: String { rawValue }

  var title: String {
    switch self {
    case .automatic: "Automatic"
    case .englishUS: "English (US)"
    case .chineseSimplified: "中文（简体）"
    case .chineseTraditional: "中文（繁體）"
    }
  }

  var localeIdentifier: String {
    switch self {
    case .automatic: Locale.current.identifier
    case .englishUS: "en-US"
    case .chineseSimplified: "zh-Hans-CN"
    case .chineseTraditional: "zh-Hant-TW"
    }
  }

  var modelLanguageHint: String? {
    switch self {
    case .automatic: nil
    case .englishUS: "English"
    case .chineseSimplified, .chineseTraditional: "Chinese"
    }
  }

  static var selected: TranscriptionLanguage {
    let rawValue = UserDefaults.standard.string(forKey: storageKey)
    return rawValue.flatMap(TranscriptionLanguage.init(rawValue:)) ?? defaultLanguage
  }
}
