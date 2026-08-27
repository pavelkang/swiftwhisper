import Foundation

public enum DeliveryMethod: String, Codable, Sendable {
    case accessibilitySelectedText
    case unicodeKeyEvents
    case clipboardPaste
    case historyOnly
}

public enum DeliveryVerification: String, Codable, Sendable {
    case verified
    case acceptedUnverified
    case failed
}

public struct DeliveryResult: Sendable, Equatable {
    public let method: DeliveryMethod
    public let verification: DeliveryVerification
    public let destinationBundleIdentifier: String?
    public let userMessage: String?

    public init(
        method: DeliveryMethod,
        verification: DeliveryVerification,
        destinationBundleIdentifier: String? = nil,
        userMessage: String? = nil
    ) {
        self.method = method
        self.verification = verification
        self.destinationBundleIdentifier = destinationBundleIdentifier
        self.userMessage = userMessage
    }
}
