import Foundation

enum PermissionKind: String, Codable, Sendable, CaseIterable {
  case microphone
  case speechRecognition
  case inputMonitoring
  case accessibility
}

enum DictationFailure: Error, Sendable, Equatable {
  case permissionMissing(PermissionKind)
  case microphoneUnavailable
  case audioDeviceChanged
  case audioBufferOverrun
  case noSpeechDetected
  case modelNotInstalled(ASRModelID)
  case modelIncompatible(ASRModelID, reason: String)
  case modelLoadFailed(ASRModelID, reason: String)
  case transcriptionFailed(reason: String)
  case transcriptEmpty
  case insertionUnavailable
  case insertionFailed(reason: String)
  case historyWriteFailed
  case cancelled
}
