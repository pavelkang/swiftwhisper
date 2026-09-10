import AppKit
import ApplicationServices
import Foundation
import OSLog

struct FocusSnapshot: @unchecked Sendable {
  let processIdentifier: pid_t?
}

@MainActor
final class AccessibilityTextDeliveryService {
  private struct RecentInsertion {
    let processIdentifier: pid_t
    let text: String
    let timestamp: ContinuousClock.Instant
  }

  private static let duplicateWindow: Duration = .seconds(2)
  private static var recentInsertion: RecentInsertion?
  private static let logger = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "com.swiftwhisper.app",
    category: "TextDelivery"
  )

  init() {}

  func snapshotFocus() -> FocusSnapshot {
    guard let application = NSWorkspace.shared.frontmostApplication else {
      return FocusSnapshot(processIdentifier: nil)
    }
    return FocusSnapshot(processIdentifier: application.processIdentifier)
  }

  func deliver(_ text: String, to original: FocusSnapshot) -> TextDeliveryOutcome {
    guard AXIsProcessTrusted() else {
      DiagnosticsLog.shared.record("insertion.accessibility_not_trusted")
      Self.logger.error("Insertion rejected: Accessibility is not trusted")
      return .notInserted
    }
    guard let originalProcessIdentifier = original.processIdentifier,
      let currentApplication = NSWorkspace.shared.frontmostApplication
    else {
      DiagnosticsLog.shared.record("insertion.no_target")
      Self.logger.error("Insertion rejected: no target application")
      return .notInserted
    }
    guard currentApplication.processIdentifier == originalProcessIdentifier else {
      DiagnosticsLog.shared.record("insertion.focus_changed")
      Self.logger.error("Insertion rejected: the frontmost application changed")
      return .notInserted
    }

    let appElement = AXUIElementCreateApplication(currentApplication.processIdentifier)
    guard
      let currentElement = copyElementAttribute(
        appElement,
        attribute: kAXFocusedUIElementAttribute
      )
    else {
      DiagnosticsLog.shared.record("insertion.no_focused_element")
      Self.logger.error("Insertion rejected: no focused Accessibility element")
      return .notInserted
    }
    guard isSafeEditableElement(currentElement) else {
      DiagnosticsLog.shared.record("insertion.not_editable")
      let role = copyStringAttribute(currentElement, attribute: kAXRoleAttribute) ?? "unknown"
      let subrole = copyStringAttribute(currentElement, attribute: kAXSubroleAttribute) ?? "none"
      Self.logger.error(
        "Insertion rejected: focused element is not editable (role: \(role), subrole: \(subrole))"
      )
      return .notInserted
    }

    let processIdentifier = currentApplication.processIdentifier
    let now = ContinuousClock().now
    if let recent = Self.recentInsertion,
      recent.processIdentifier == processIdentifier,
      recent.text == text,
      recent.timestamp.duration(to: now) < Self.duplicateWindow
    {
      Self.logger.notice("Suppressed duplicate insertion of \(text.utf16.count) UTF-16 units")
      return .duplicateSuppressed
    }

    guard postUnicodeText(text, to: processIdentifier) else {
      DiagnosticsLog.shared.record("insertion.event_creation_failed")
      Self.logger.error("Insertion rejected: could not create keyboard events")
      return .notInserted
    }

    Self.recentInsertion = RecentInsertion(
      processIdentifier: processIdentifier,
      text: text,
      timestamp: now
    )
    Self.logger.notice("Posted one insertion of \(text.utf16.count) UTF-16 units")
    return .inserted
  }

  private func isSafeEditableElement(_ element: AXUIElement) -> Bool {
    let role = copyStringAttribute(element, attribute: kAXRoleAttribute)
    let subrole = copyStringAttribute(element, attribute: kAXSubroleAttribute)
    if subrole == kAXSecureTextFieldSubrole as String { return false }
    if role == kAXTextFieldRole as String || role == kAXTextAreaRole as String {
      return true
    }

    var isSelectedTextSettable = DarwinBoolean(false)
    let status = AXUIElementIsAttributeSettable(
      element,
      kAXSelectedTextAttribute as CFString,
      &isSelectedTextSettable
    )
    return status == .success && isSelectedTextSettable.boolValue
  }

  private func postUnicodeText(_ text: String, to processIdentifier: pid_t) -> Bool {
    guard !text.isEmpty,
      let source = CGEventSource(stateID: .combinedSessionState),
      let keyDown = CGEvent(
        keyboardEventSource: source,
        virtualKey: 0,
        keyDown: true
      ),
      let keyUp = CGEvent(
        keyboardEventSource: source,
        virtualKey: 0,
        keyDown: false
      )
    else { return false }

    let codeUnits = Array(text.utf16)
    codeUnits.withUnsafeBufferPointer { buffer in
      keyDown.keyboardSetUnicodeString(
        stringLength: buffer.count,
        unicodeString: buffer.baseAddress
      )
    }
    keyDown.postToPid(processIdentifier)
    keyUp.postToPid(processIdentifier)
    return true
  }

  private func copyElementAttribute(
    _ element: AXUIElement,
    attribute: String
  ) -> AXUIElement? {
    var value: CFTypeRef?
    guard
      AXUIElementCopyAttributeValue(
        element,
        attribute as CFString,
        &value
      ) == .success
    else { return nil }
    return (value as! AXUIElement)
  }

  private func copyStringAttribute(
    _ element: AXUIElement,
    attribute: String
  ) -> String? {
    var value: CFTypeRef?
    guard
      AXUIElementCopyAttributeValue(
        element,
        attribute as CFString,
        &value
      ) == .success
    else { return nil }
    return value as? String
  }
}
