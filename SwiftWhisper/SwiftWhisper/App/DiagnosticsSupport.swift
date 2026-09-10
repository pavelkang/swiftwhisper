import AppKit
import Combine
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class DiagnosticsSupport: NSObject, ObservableObject, NSSharingServiceDelegate {
  @Published var report: String?
  @Published var isPreparing = false
  @Published var message: String?
  private var sharingService: NSSharingService?

  static var supportEmail: String? {
    guard let value = Bundle.main.object(forInfoDictionaryKey: "SwiftWhisperSupportEmail") as? String,
      !value.contains("$("), value.contains("@"), !value.contains(where: { $0.isWhitespace })
    else { return nil }
    return value
  }

  static var versionLabel: String {
    let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Unknown"
    let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "Unknown"
    return "Version \(version) (\(build))"
  }

  func prepareReport(permissions: PermissionSnapshot?) {
    guard !isPreparing else { return }
    isPreparing = true
    message = nil
    Task {
      defer { isPreparing = false }
      do {
        DiagnosticsLog.shared.record("diagnostics.report_requested")
        let logs = try await DiagnosticsLog.shared.snapshot()
        #if arch(arm64)
        let architecture = "Apple silicon"
        #else
        let architecture = "Intel"
        #endif
        report = """
          SwiftWhisper beta diagnostics — report format 1
          Generated: \(ISO8601DateFormatter().string(from: Date()))
          \(Self.versionLabel)
          macOS: \(ProcessInfo.processInfo.operatingSystemVersionString)
          Architecture: \(architecture)
          Memory: \(ProcessInfo.processInfo.physicalMemory / 1_073_741_824) GB
          Speech model: \(SpeechModel.selected.rawValue)
          Smart Polish: \(SmartPolishSetting.isEnabled ? SmartPolishModel.selected.rawValue : "off")
          Required permissions granted: \(permissions.map { String($0.hasRequiredPermissions) } ?? "unknown")
          Microphone: \(permissions.map { String(describing: $0.microphone) } ?? "unknown")
          Speech recognition: \(permissions.map { String(describing: $0.speechRecognition) } ?? "unknown")
          Input Monitoring: \(permissions.map { String(describing: $0.inputMonitoring) } ?? "unknown")
          Accessibility: \(permissions.map { String(describing: $0.accessibility) } ?? "unknown")
          History enabled: \(DictationHistorySetting.isEnabled)

          Contains app events and error types/codes. Does not include transcripts,
          recordings, vocabulary, account details, or raw system crash reports.
          An unexpected-termination event can mean a crash, force quit, or power loss.

          Recent events (up to 4 × 256 KB; files expire after 7 inactive days):
          \(logs.isEmpty ? "No events recorded." : logs)
          """
      } catch {
        DiagnosticsLog.shared.record("diagnostics.report_failed", error: error)
        message = "Couldn’t read diagnostics. Check that your disk has free space and try again."
      }
    }
  }

  func composeEmail() {
    guard let report else { return }
    guard let recipient = Self.supportEmail else {
      message = "A support address hasn’t been configured in this build. Save the report and share it with the person who gave you the beta."
      return
    }
    do {
      let directory = DiagnosticsLog.shared.directory.appendingPathComponent("Reports", isDirectory: true)
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
        attributes: [.posixPermissions: 0o700])
      // Keep recent attachments available to Mail, with bounded storage for draft reports.
      let cutoff = Date().addingTimeInterval(-7 * 86_400)
      let previousReports = try FileManager.default.contentsOfDirectory(at: directory,
        includingPropertiesForKeys: [.contentModificationDateKey])
        .filter { $0.lastPathComponent.hasPrefix("SwiftWhisper-Diagnostics-") && $0.pathExtension == "txt" }
        .map { ($0, try $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate ?? .distantPast) }
        .sorted { $0.1 > $1.1 }
      for (index, entry) in previousReports.enumerated() {
        if index >= 4 || entry.1 < cutoff { try FileManager.default.removeItem(at: entry.0) }
      }
      let file = directory.appendingPathComponent("SwiftWhisper-Diagnostics-\(UUID().uuidString).txt")
      try report.write(to: file, atomically: true, encoding: .utf8)
      try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
      let items: [Any] = ["Please describe what happened and how to reproduce it:\n\n", file]
      guard let service = NSSharingService(named: .composeEmail), service.canPerform(withItems: items) else {
        message = "No compatible email app is available. Use Save Report, then attach the file using your email service."
        return
      }
      sharingService = service
      service.delegate = self
      service.recipients = [recipient]
      service.subject = "SwiftWhisper beta diagnostics — \(Self.versionLabel)"
      service.perform(withItems: items)
      message = "Opening an email draft. Review it and send it from your email app."
    } catch {
      DiagnosticsLog.shared.record("diagnostics.email_preparation_failed", error: error)
      message = "Couldn’t prepare the email attachment. Try Save Report instead."
    }
  }

  func sharingService(_ sharingService: NSSharingService, didFailToShareItems items: [Any], error: any Error) {
    DiagnosticsLog.shared.record("diagnostics.email_failed", error: error)
    message = "The email draft couldn’t be opened. Use Save Report and attach it manually."
    self.sharingService = nil
  }

  func sharingService(_ sharingService: NSSharingService, didShareItems items: [Any]) {
    self.sharingService = nil
  }

  func saveReport() {
    guard let report else { return }
    let panel = NSSavePanel()
    panel.allowedContentTypes = [.plainText]
    panel.nameFieldStringValue = "SwiftWhisper-Diagnostics.txt"
    panel.begin { [weak self] response in
      guard response == .OK, let url = panel.url else { return }
      do {
        try report.write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        self?.message = "Report saved. You can attach it to an email or support message."
      } catch {
        DiagnosticsLog.shared.record("diagnostics.export_failed", error: error)
        self?.message = "Couldn’t save the report. Choose another folder and try again."
      }
    }
  }
}

struct DiagnosticsReportView: View {
  @ObservedObject var support: DiagnosticsSupport
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      Text("Review Diagnostics").font(.title2.bold())
      Text("Check the report before sharing. Your words and recordings are never included.")
        .foregroundStyle(.secondary)
      ScrollView {
        Text(support.report ?? "")
          .font(.system(.caption, design: .monospaced))
          .textSelection(.enabled)
          .frame(maxWidth: .infinity, alignment: .leading)
          .padding(12)
      }
      .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 8))
      if let message = support.message {
        Text(message).font(.callout).foregroundStyle(.secondary)
      }
      HStack {
        Button("Close") { dismiss() }.keyboardShortcut(.cancelAction)
        Spacer()
        Button("Save Report…", action: support.saveReport)
        Button("Open Email Draft", action: support.composeEmail)
          .buttonStyle(.borderedProminent)
      }
    }
    .padding(24)
    .frame(width: 640, height: 500)
  }
}

@MainActor
final class DiagnosticsAppDelegate: NSObject, NSApplicationDelegate {
  private let activeSessionKey = "diagnosticsSessionActive"

  func applicationDidFinishLaunching(_ notification: Notification) {
    if UserDefaults.standard.bool(forKey: activeSessionKey) {
      DiagnosticsLog.shared.record("app.previous_session_ended_unexpectedly")
    }
    UserDefaults.standard.set(true, forKey: activeSessionKey)
    DiagnosticsLog.shared.record("app.started")
  }

  func applicationWillTerminate(_ notification: Notification) {
    DiagnosticsLog.shared.record("app.stopped")
    DiagnosticsLog.shared.flush()
    UserDefaults.standard.set(false, forKey: activeSessionKey)
  }
}
