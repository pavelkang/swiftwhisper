import Foundation

enum AudioInputSelection {
  static let storageKey = "audioInputDeviceUID"
  static let systemDefaultID = "__system_default__"

  static var selectedID: String {
    UserDefaults.standard.string(forKey: storageKey) ?? systemDefaultID
  }
}
