import Foundation

@main
struct DiagnosticsSmoke {
  static func require(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    if !condition() { throw NSError(domain: "DiagnosticsSmoke", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
  }

  static func main() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let log = DiagnosticsLog(directory: root.appendingPathComponent("private"))
    let secret = "private transcript /Users/test/private.wav user@example.com"
    log.record("test.failure", error: NSError(domain: secret, code: 42,
      userInfo: [NSLocalizedDescriptionKey: secret, NSFilePathErrorKey: secret,
        NSUnderlyingErrorKey: NSError(domain: NSCocoaErrorDomain, code: 1,
          userInfo: [NSLocalizedDescriptionKey: secret])]))
    log.record("test.cancelled", error: CancellationError())
    let privateSnapshot = try await log.snapshot()
    try require(!privateSnapshot.contains(secret), "Sensitive error details leaked")
    try require(!privateSnapshot.contains("test.cancelled"), "Cancellation logged as an error")
    try require(privateSnapshot.contains("42") && privateSnapshot.contains("test.failure"), "Error context missing")
    let attributes = try FileManager.default.attributesOfItem(atPath: log.directory.appendingPathComponent("diagnostics.jsonl").path)
    try require((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o600, "Log file is not private")

    let concurrent = DiagnosticsLog(directory: root.appendingPathComponent("concurrent"))
    await withTaskGroup(of: Void.self) { group in
      for _ in 0..<200 { group.addTask { concurrent.record("test.concurrent") } }
    }
    let lines = try await concurrent.snapshot().split(separator: "\n")
    try require(lines.count == 200, "Concurrent events were lost")
    for line in lines { _ = try JSONSerialization.jsonObject(with: Data(line.utf8)) }

    let rotating = DiagnosticsLog(directory: root.appendingPathComponent("rotating"), maximumBytes: 700)
    for _ in 0..<100 { rotating.record("test.rotation") }
    _ = try await rotating.snapshot()
    let files = try FileManager.default.contentsOfDirectory(at: rotating.directory, includingPropertiesForKeys: [.fileSizeKey])
    try require(files.count == 4, "Rotation did not cap file count")
    for file in files {
      let size = try file.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
      try require(size <= 700, "Rotation exceeded size cap")
      try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(-8 * 86_400)], ofItemAtPath: file.path)
    }
    let expired = try await rotating.snapshot()
    try require(expired.isEmpty, "Expired files were retained")

    let blockedDirectory = root.appendingPathComponent("not-a-directory")
    try Data("file".utf8).write(to: blockedDirectory)
    let blocked = DiagnosticsLog(directory: blockedDirectory)
    blocked.record("test.unwritable")
    var readFailed = false
    do { _ = try await blocked.snapshot() } catch { readFailed = true }
    try require(readFailed, "Storage failure was silently exported as an empty report")
    print("Diagnostics checks passed: privacy, permissions, concurrent writes, rotation, expiry, and disk failure.")
  }
}
