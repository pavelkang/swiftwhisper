import Foundation

enum SmartPolishSetting {
  static let storageKey = "smartPolishEnabled"
  static let defaultEnabled = true

  static var isEnabled: Bool {
    guard UserDefaults.standard.object(forKey: storageKey) != nil else {
      return defaultEnabled
    }
    return UserDefaults.standard.bool(forKey: storageKey)
  }
}

enum SmartPolishModel: String, CaseIterable, Identifiable {
  case appleIntelligence
  case qwen3Compact

  static let storageKey = "smartPolishModel"
  static let defaultModel = SmartPolishModel.appleIntelligence

  var id: String { rawValue }

  var title: String {
    switch self {
    case .appleIntelligence: "Apple Intelligence"
    case .qwen3Compact: "Qwen3 0.6B"
    }
  }

  var detail: String {
    switch self {
    case .appleIntelligence: "Built in · no download"
    case .qwen3Compact: "Compact multilingual model · about 350 MB"
    }
  }

  static var selected: SmartPolishModel {
    let value = UserDefaults.standard.string(forKey: storageKey)
    return value.flatMap(SmartPolishModel.init(rawValue:)) ?? defaultModel
  }
}

enum SmartPolishAvailability: Equatable {
  case available
  case appleIntelligenceDisabled
  case modelPreparing
  case deviceNotEligible
  case modelNotDownloaded
  case modelLoadFailed
}
