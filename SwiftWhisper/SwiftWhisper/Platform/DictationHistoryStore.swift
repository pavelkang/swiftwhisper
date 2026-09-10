import AVFoundation
import Combine
import Foundation
#if os(macOS)
import AppKit
#elseif os(iOS)
import UIKit
#endif

enum DictationHistorySetting {
  static let storageKey = "dictationHistoryEnabled"
  static let defaultEnabled = true

  static var isEnabled: Bool {
    guard UserDefaults.standard.object(forKey: storageKey) != nil else {
      return defaultEnabled
    }
    return UserDefaults.standard.bool(forKey: storageKey)
  }
}

struct DictationHistoryEntry: Codable, Identifiable, Equatable {
  let id: UUID
  let createdAt: Date
  let transcript: String
  let correctedTranscript: String?
  let correctedAt: Date?
  let audioFilename: String
  let duration: TimeInterval

  var displayTranscript: String {
    correctedTranscript ?? transcript
  }

  var hasCorrection: Bool {
    correctedTranscript != nil
  }
}

@MainActor
final class DictationHistoryStore: ObservableObject {
  static let shared = DictationHistoryStore()
  static let maximumEntryCount = 100

  @Published private(set) var entries: [DictationHistoryEntry] = []
  @Published private(set) var playingEntryID: UUID?
  @Published private(set) var isUsingICloud = false

  private let directoryURL: URL
  private let indexURL: URL
  private var player: AVAudioPlayer?
  private var playbackTask: Task<Void, Never>?
  private var changeObserver: NSObjectProtocol?
  private var foregroundObserver: NSObjectProtocol?
  private static let iCloudContainerIdentifier = "iCloud.com.swiftwhisper.app"
  private static let iCloudChangeKey = "historyChangeToken"

  private init() {
    if let container = FileManager.default.url(
      forUbiquityContainerIdentifier: Self.iCloudContainerIdentifier
    ) {
      directoryURL = container
        .appendingPathComponent("Documents", isDirectory: true)
        .appendingPathComponent("History", isDirectory: true)
      isUsingICloud = true
    } else {
      let applicationSupport = FileManager.default.urls(
        for: .applicationSupportDirectory,
        in: .userDomainMask
      ).first!
      directoryURL = applicationSupport
        .appendingPathComponent("SwiftWhisper", isDirectory: true)
        .appendingPathComponent("History", isDirectory: true)
    }
    indexURL = directoryURL.appendingPathComponent("history.json")

    do {
      try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
    } catch {
      DiagnosticsLog.shared.record("history.directory_failed", error: error)
    }
    if isUsingICloud { migrateLocalHistoryIfNeeded() }
    loadEntries()

    NSUbiquitousKeyValueStore.default.synchronize()
    changeObserver = NotificationCenter.default.addObserver(
      forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
      object: NSUbiquitousKeyValueStore.default,
      queue: .main
    ) { [weak self] _ in
      Task { @MainActor in self?.reloadFromDisk() }
    }
#if os(macOS)
    foregroundObserver = NotificationCenter.default.addObserver(
      forName: NSApplication.didBecomeActiveNotification,
      object: nil,
      queue: .main
    ) { [weak self] _ in
      Task { @MainActor in self?.reloadFromDisk() }
    }
#elseif os(iOS)
    foregroundObserver = NotificationCenter.default.addObserver(
      forName: UIApplication.didBecomeActiveNotification,
      object: nil,
      queue: .main
    ) { [weak self] _ in
      Task { @MainActor in self?.reloadFromDisk() }
    }
#endif
  }

  func add(transcript: String, samples: [Float]) {
    guard DictationHistorySetting.isEnabled, !samples.isEmpty else { return }

    let id = UUID()
    let filename = "\(id.uuidString).wav"
    let audioURL = directoryURL.appendingPathComponent(filename)

    do {
      try writeWAV(samples: samples, to: audioURL)
      let entry = DictationHistoryEntry(
        id: id,
        createdAt: Date(),
        transcript: transcript,
        correctedTranscript: nil,
        correctedAt: nil,
        audioFilename: filename,
        duration: Double(samples.count) / 16_000
      )
      entries.insert(entry, at: 0)
      pruneIfNeeded()
      persistEntries()
    } catch {
      DiagnosticsLog.shared.record("history.audio_write_failed", error: error)
      try? FileManager.default.removeItem(at: audioURL)
    }
  }

  func play(_ entry: DictationHistoryEntry) {
    if playingEntryID == entry.id {
      stopPlayback()
      return
    }

    stopPlayback()
    let audioURL = directoryURL.appendingPathComponent(entry.audioFilename)
    do {
      player = try AVAudioPlayer(contentsOf: audioURL)
      playingEntryID = entry.id
      player?.play()
    } catch {
      DiagnosticsLog.shared.record("history.playback_failed", error: error)
      player = nil
      playingEntryID = nil
      return
    }

    playbackTask = Task { [weak self] in
      try? await Task.sleep(for: .seconds(entry.duration))
      guard !Task.isCancelled, self?.playingEntryID == entry.id else { return }
      self?.stopPlayback()
    }
  }

  func delete(_ entry: DictationHistoryEntry) {
    if playingEntryID == entry.id { stopPlayback() }
    entries.removeAll { $0.id == entry.id }
    try? FileManager.default.removeItem(
      at: directoryURL.appendingPathComponent(entry.audioFilename)
    )
    persistEntries()
  }

  func saveCorrection(for entry: DictationHistoryEntry, correctedTranscript: String) {
    let corrected = correctedTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !corrected.isEmpty,
      let index = entries.firstIndex(where: { $0.id == entry.id })
    else { return }

    let current = entries[index]
    let isChanged = corrected != current.transcript
    entries[index] = DictationHistoryEntry(
      id: current.id,
      createdAt: current.createdAt,
      transcript: current.transcript,
      correctedTranscript: isChanged ? corrected : nil,
      correctedAt: isChanged ? Date() : nil,
      audioFilename: current.audioFilename,
      duration: current.duration
    )
    persistEntries()
  }

  func clear() {
    stopPlayback()
    for entry in entries {
      try? FileManager.default.removeItem(
        at: directoryURL.appendingPathComponent(entry.audioFilename)
      )
    }
    entries.removeAll()
    persistEntries()
  }

  private func stopPlayback() {
    playbackTask?.cancel()
    playbackTask = nil
    player?.stop()
    player = nil
    playingEntryID = nil
  }

  private func loadEntries() {
    guard FileManager.default.fileExists(atPath: indexURL.path) else { return }
    let decoded: [DictationHistoryEntry]
    do {
      decoded = try JSONDecoder().decode([DictationHistoryEntry].self, from: Data(contentsOf: indexURL))
    } catch {
      DiagnosticsLog.shared.record("history.index_read_failed", error: error)
      return
    }

    // An iCloud recording may not have downloaded yet. Reading history must not
    // delete its transcript or rewrite the shared index with a partial local view.
    entries = decoded.sorted { $0.createdAt > $1.createdAt }
  }

  private func migrateLocalHistoryIfNeeded() {
    guard !FileManager.default.fileExists(atPath: indexURL.path) else { return }
    let localDirectory = FileManager.default.urls(
      for: .applicationSupportDirectory,
      in: .userDomainMask
    ).first!
      .appendingPathComponent("SwiftWhisper", isDirectory: true)
      .appendingPathComponent("History", isDirectory: true)
    let localIndex = localDirectory.appendingPathComponent("history.json")
    guard FileManager.default.fileExists(atPath: localIndex.path),
      let files = try? FileManager.default.contentsOfDirectory(
        at: localDirectory,
        includingPropertiesForKeys: nil
      )
    else { return }

    for source in files {
      let destination = directoryURL.appendingPathComponent(source.lastPathComponent)
      guard !FileManager.default.fileExists(atPath: destination.path) else { continue }
      try? FileManager.default.copyItem(at: source, to: destination)
    }
  }

  func refresh() {
    reloadFromDisk()
  }

  private func reloadFromDisk() {
    guard FileManager.default.fileExists(atPath: indexURL.path),
      let data = coordinatedRead(from: indexURL) else { return }
    do {
      let decoded = try JSONDecoder().decode([DictationHistoryEntry].self, from: data)
        .sorted { $0.createdAt > $1.createdAt }
      if decoded != entries { entries = decoded }
    } catch {
      DiagnosticsLog.shared.record("history.decode_failed", error: error)
    }
  }

  private func pruneIfNeeded() {
    guard entries.count > Self.maximumEntryCount else { return }
    let removed = entries.dropFirst(Self.maximumEntryCount)
    for entry in removed {
      try? FileManager.default.removeItem(
        at: directoryURL.appendingPathComponent(entry.audioFilename)
      )
    }
    entries = Array(entries.prefix(Self.maximumEntryCount))
  }

  private func persistEntries() {
    guard let data = try? JSONEncoder().encode(entries) else { return }
    coordinatedWrite(data, to: indexURL)
    if isUsingICloud {
      NSUbiquitousKeyValueStore.default.set(UUID().uuidString, forKey: Self.iCloudChangeKey)
      NSUbiquitousKeyValueStore.default.synchronize()
    }
  }

  private func coordinatedRead(from url: URL) -> Data? {
    var result: Data?
    var coordinationError: NSError?
    NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: &coordinationError) {
      do { result = try Data(contentsOf: $0) }
      catch { DiagnosticsLog.shared.record("history.read_failed", error: error) }
    }
    if let coordinationError {
      DiagnosticsLog.shared.record("history.read_coordination_failed", error: coordinationError)
    }
    return result
  }

  private func coordinatedWrite(_ data: Data, to url: URL) {
    var coordinationError: NSError?
    NSFileCoordinator().coordinate(
      writingItemAt: url,
      options: .forReplacing,
      error: &coordinationError
    ) { coordinatedURL in
      do { try data.write(to: coordinatedURL, options: .atomic) }
      catch { DiagnosticsLog.shared.record("history.write_failed", error: error) }
    }
    if let coordinationError {
      DiagnosticsLog.shared.record("history.write_coordination_failed", error: coordinationError)
    }
  }

  private func writeWAV(samples: [Float], to url: URL) throws {
    guard let format = AVAudioFormat(
      commonFormat: .pcmFormatFloat32,
      sampleRate: 16_000,
      channels: 1,
      interleaved: false
    ),
      let buffer = AVAudioPCMBuffer(
        pcmFormat: format,
        frameCapacity: AVAudioFrameCount(samples.count)
      ),
      let channel = buffer.floatChannelData?[0]
    else {
      throw DictationFailure.transcriptionFailed(reason: "Could not save history audio.")
    }

    buffer.frameLength = AVAudioFrameCount(samples.count)
    samples.withUnsafeBufferPointer { source in
      guard let baseAddress = source.baseAddress else { return }
      channel.update(from: baseAddress, count: samples.count)
    }

    let file = try AVAudioFile(
      forWriting: url,
      settings: format.settings,
      commonFormat: .pcmFormatFloat32,
      interleaved: false
    )
    try file.write(from: buffer)
  }
}
