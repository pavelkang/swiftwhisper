import ApplicationServices
import AVFoundation
import Foundation
import Speech
import SwiftWhisperCore

public enum PermissionStatus: Sendable, Equatable {
    case notDetermined
    case granted
    case denied
    case restricted
}

public enum TrustStatus: Sendable, Equatable {
    case trusted
    case notTrusted(requestAttempted: Bool)
}

public struct PermissionSnapshot: Sendable, Equatable {
    public let microphone: PermissionStatus
    public let speechRecognition: PermissionStatus
    public let inputMonitoring: TrustStatus
    public let accessibility: TrustStatus
}

public actor PermissionService {
    public init() {}

    public func currentSnapshot() -> PermissionSnapshot {
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

    public func requestMicrophone() async -> PermissionStatus {
        if Self.microphoneStatus != .notDetermined {
            return Self.microphoneStatus
        }
        let granted = await AVCaptureDevice.requestAccess(for: .audio)
        return granted ? .granted : .denied
    }

    public func requestSpeechRecognition() async -> PermissionStatus {
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

    public func requestInputMonitoring() -> TrustStatus {
        CGRequestListenEventAccess()
            ? .trusted
            : .notTrusted(requestAttempted: true)
    }

    public func requestAccessibility() -> TrustStatus {
        // The SDK exposes kAXTrustedCheckOptionPrompt as mutable global C state,
        // which is rejected by Swift 6 strict concurrency. Its documented value
        // is stable, so keep the unsafe C global at this boundary.
        let promptKey = "AXTrustedCheckOptionPrompt"
        let options = [promptKey: true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
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
