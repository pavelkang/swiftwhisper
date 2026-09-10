import Foundation
import OSLog

/// Serializes disk access; only immutable, privacy-filtered values cross the queue boundary.
final class DiagnosticsLog: @unchecked Sendable {
  static let shared = DiagnosticsLog()
  static let maximumFileBytes = 256 * 1_024
  static let retainedFileCount = 4
  static let retentionDays = 7

  let directory: URL
  private let queue = DispatchQueue(label: "com.swiftwhisper.diagnostics", qos: .utility)
  private let maximumBytes: Int
  private let fallback = Logger(subsystem: "com.swiftwhisper.app", category: "Diagnostics")

  init(directory: URL? = nil, maximumBytes: Int = DiagnosticsLog.maximumFileBytes) {
    self.directory = directory ?? FileManager.default.urls(
      for: .applicationSupportDirectory, in: .userDomainMask
    )[0].appendingPathComponent("SwiftWhisper/Diagnostics", isDirectory: true)
    self.maximumBytes = maximumBytes
  }

  /// Call sites supply literal event names, never transcripts, paths, or arbitrary messages.
  func record(_ event: StaticString, error: (any Error)? = nil) {
    if error is CancellationError { return }
    var fields: [String: String] = [
      "timestamp": ISO8601DateFormatter().string(from: Date()),
      "event": String(describing: event),
      "level": error == nil ? "info" : "error",
      "version": Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown",
      "build": Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown",
    ]
    if let error {
      let nsError = error as NSError
      fields["errorType"] = String(reflecting: type(of: error))
      fields["errorCode"] = String(nsError.code)
      // NSError descriptions, userInfo, underlying errors, and arbitrary domains can carry
      // dictated text, filenames, URLs, and account details. Never serialize them.
      let safeDomains = [NSCocoaErrorDomain, NSURLErrorDomain, NSPOSIXErrorDomain, NSOSStatusErrorDomain]
      fields["errorDomain"] = safeDomains.contains(nsError.domain) ? nsError.domain : "other"
    }
    guard var data = try? JSONSerialization.data(withJSONObject: fields, options: [.sortedKeys]) else { return }
    data.append(0x0A)
    let line = data
    queue.async { [self] in
      do {
        try prepareDirectory()
        try pruneExpiredFiles()
        let current = logURL(0)
        let size = (try? current.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        if size + line.count > maximumBytes { try rotate() }
        if !FileManager.default.fileExists(atPath: current.path) {
          try Data().write(to: current, options: .atomic)
          try protect(current, mode: 0o600)
        }
        let handle = try FileHandle(forWritingTo: current)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: line)
      } catch {
        // Do not recursively log a disk failure or leak its paths into the system log.
        fallback.error("Unable to write local diagnostic log")
      }
    }
  }

  /// Waits for pending entries and propagates read errors so an empty report cannot mask failure.
  func snapshot() async throws -> String {
    try await withCheckedThrowingContinuation { continuation in
      queue.async { [self] in
        do {
          try prepareDirectory()
          try pruneExpiredFiles()
          var parts: [String] = []
          for index in (0..<Self.retainedFileCount).reversed() {
            let url = logURL(index)
            guard FileManager.default.fileExists(atPath: url.path) else { continue }
            parts.append(try String(contentsOf: url, encoding: .utf8))
          }
          continuation.resume(returning: parts.joined())
        } catch {
          continuation.resume(throwing: error)
        }
      }
    }
  }

  /// Used only during orderly application termination to flush queued writes.
  func flush() { queue.sync {} }

  private func prepareDirectory() throws {
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    try protect(directory, mode: 0o700)
    var url = directory
    var values = URLResourceValues()
    values.isExcludedFromBackup = true
    try url.setResourceValues(values)
  }

  private func protect(_ url: URL, mode: Int) throws {
    try FileManager.default.setAttributes([.posixPermissions: mode], ofItemAtPath: url.path)
  }

  private func logURL(_ index: Int) -> URL {
    directory.appendingPathComponent(index == 0 ? "diagnostics.jsonl" : "diagnostics.\(index).jsonl")
  }

  private func pruneExpiredFiles() throws {
    let cutoff = Date().addingTimeInterval(-Double(Self.retentionDays) * 86_400)
    for index in 0..<Self.retainedFileCount {
      let url = logURL(index)
      guard FileManager.default.fileExists(atPath: url.path) else { continue }
      if let modified = try url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate,
        modified < cutoff
      { try FileManager.default.removeItem(at: url) }
    }
  }

  private func rotate() throws {
    let oldest = logURL(Self.retainedFileCount - 1)
    if FileManager.default.fileExists(atPath: oldest.path) {
      try FileManager.default.removeItem(at: oldest)
    }
    for index in (0..<(Self.retainedFileCount - 1)).reversed() {
      let source = logURL(index)
      if FileManager.default.fileExists(atPath: source.path) {
        try FileManager.default.moveItem(at: source, to: logURL(index + 1))
      }
    }
  }
}
