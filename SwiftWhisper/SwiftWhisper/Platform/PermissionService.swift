import AVFoundation
import ApplicationServices
import Foundation
import Speech

enum PermissionStatus: Sendable, Equatable {
  case notDetermined
  case granted
  case denied
  case restricted
}

enum TrustStatus: Sendable, Equatable {
  case trusted
  case notTrusted(requestAttempted: Bool)
}

struct PermissionSnapshot: Sendable, Equatable {
  let microphone: PermissionStatus
  let speechRecognition: PermissionStatus
  let inputMonitoring: TrustStatus
  let accessibility: TrustStatus

  var hasRequiredPermissions: Bool {
    microphone == .granted
      && speechRecognition == .granted
      && inputMonitoring.isTrusted
      && accessibility.isTrusted
  }
}

private extension TrustStatus {
  var isTrusted: Bool {
    if case .trusted = self { return true }
    return false
  }
}

actor PermissionService {
  init() {}

  func currentSnapshot() -> PermissionSnapshot {
    PermissionSnapshot(
      microphone: Self.microphoneStatus,
      speechRecognition: Self.speechStatus,
      inputMonitoring: CGPreflightListenEventAccess()
        ? .trusted
        : .notTrusted(requestAttempted: false),
      accessibility: AXIsProcessTrusted()
        ? .trusted
        : .notTrusted(requestAttempted: false)
    )
  }

  func requestMicrophone() async -> PermissionStatus {
    if Self.microphoneStatus != .notDetermined {
      return Self.microphoneStatus
    }
    let granted = await AVCaptureDevice.requestAccess(for: .audio)
    return granted ? .granted : .denied
  }

  func requestSpeechRecognition() async -> PermissionStatus {
    if Self.speechStatus != .notDetermined {
      return Self.speechStatus
    }
    let status = await withCheckedContinuation { continuation in
      SFSpeechRecognizer.requestAuthorization { status in
        continuation.resume(returning: status)
      }
    }
    return Self.map(status)
  }

  func requestInputMonitoring() async -> TrustStatus {
    let granted = await MainActor.run {
      CGRequestListenEventAccess()
    }
    return granted
      ? .trusted
      : .notTrusted(requestAttempted: true)
  }

  func requestAccessibility() async -> TrustStatus {
    let granted = await MainActor.run {
      // The SDK exposes kAXTrustedCheckOptionPrompt as mutable global C state,
      // which is rejected by Swift 6 strict concurrency. Its documented value
      // is stable, so keep the unsafe C global at this boundary.
      let promptKey = "AXTrustedCheckOptionPrompt"
      let options = [promptKey: true] as CFDictionary
      return AXIsProcessTrustedWithOptions(options)
    }
    return granted
      ? .trusted
      : .notTrusted(requestAttempted: true)
  }

  private static var microphoneStatus: PermissionStatus {
    switch AVCaptureDevice.authorizationStatus(for: .audio) {
    case .authorized: .granted
    case .notDetermined: .notDetermined
    case .denied: .denied
    case .restricted: .restricted
    @unknown default: .denied
    }
  }

  private static var speechStatus: PermissionStatus {
    map(SFSpeechRecognizer.authorizationStatus())
  }

  private static func map(_ status: SFSpeechRecognizerAuthorizationStatus) -> PermissionStatus {
    switch status {
    case .authorized: .granted
    case .notDetermined: .notDetermined
    case .denied: .denied
    case .restricted: .restricted
    @unknown default: .denied
    }
  }
}
