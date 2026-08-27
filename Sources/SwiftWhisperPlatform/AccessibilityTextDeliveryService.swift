import AppKit
import ApplicationServices
import Foundation
import SwiftWhisperCore

public struct FocusSnapshot: @unchecked Sendable {
    public let processIdentifier: pid_t?
    public let bundleIdentifier: String?
    fileprivate let element: AXUIElement?

    fileprivate init(
        processIdentifier: pid_t?,
        bundleIdentifier: String?,
        element: AXUIElement?
    ) {
        self.processIdentifier = processIdentifier
        self.bundleIdentifier = bundleIdentifier
        self.element = element
    }
}

@MainActor
public final class AccessibilityTextDeliveryService {
    public init() {}

    public func snapshotFocus() -> FocusSnapshot {
        guard let application = NSWorkspace.shared.frontmostApplication else {
            return FocusSnapshot(processIdentifier: nil, bundleIdentifier: nil, element: nil)
        }

        let appElement = AXUIElementCreateApplication(application.processIdentifier)
        let focused = copyElementAttribute(appElement, attribute: kAXFocusedUIElementAttribute)
        return FocusSnapshot(
            processIdentifier: application.processIdentifier,
            bundleIdentifier: application.bundleIdentifier,
            element: focused
        )
    }

    public func deliver(_ text: String, to original: FocusSnapshot) -> DeliveryResult {
        guard AXIsProcessTrusted(),
              let currentApplication = NSWorkspace.shared.frontmostApplication,
              currentApplication.processIdentifier == original.processIdentifier,
              let originalElement = original.element else {
            return historyOnly("Focus changed or Accessibility is unavailable.")
        }

        let appElement = AXUIElementCreateApplication(currentApplication.processIdentifier)
        guard let currentElement = copyElementAttribute(
            appElement,
            attribute: kAXFocusedUIElementAttribute
        ), CFEqual(currentElement, originalElement), isSafeEditableElement(currentElement) else {
            return historyOnly("The original editable field is no longer focused.")
        }

        var settable = DarwinBoolean(false)
        guard AXUIElementIsAttributeSettable(
            currentElement,
            kAXSelectedTextAttribute as CFString,
            &settable
        ) == .success, settable.boolValue else {
            return historyOnly("This editor does not support direct text insertion.")
        }

        let result = AXUIElementSetAttributeValue(
            currentElement,
            kAXSelectedTextAttribute as CFString,
            text as CFString
        )
        guard result == .success else {
            return historyOnly("Text insertion failed and was saved locally.")
        }

        return DeliveryResult(
            method: .accessibilitySelectedText,
            verification: .verified,
            destinationBundleIdentifier: currentApplication.bundleIdentifier
        )
    }

    private func isSafeEditableElement(_ element: AXUIElement) -> Bool {
        let role = copyStringAttribute(element, attribute: kAXRoleAttribute)
        let subrole = copyStringAttribute(element, attribute: kAXSubroleAttribute)
        if subrole == kAXSecureTextFieldSubrole as String { return false }
        return role == kAXTextFieldRole as String || role == kAXTextAreaRole as String
    }

    private func historyOnly(_ message: String) -> DeliveryResult {
        DeliveryResult(
            method: .historyOnly,
            verification: .failed,
            userMessage: message
        )
    }

    private func copyElementAttribute(
        _ element: AXUIElement,
        attribute: String
    ) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element,
            attribute as CFString,
            &value
        ) == .success else { return nil }
        return (value as! AXUIElement)
    }

    private func copyStringAttribute(
        _ element: AXUIElement,
        attribute: String
    ) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element,
            attribute as CFString,
            &value
        ) == .success else { return nil }
        return value as? String
    }
}
