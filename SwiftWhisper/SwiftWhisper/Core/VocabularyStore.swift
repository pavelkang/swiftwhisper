import Combine
import Foundation

@MainActor
final class VocabularyStore: ObservableObject {
  static let shared = VocabularyStore()

  static let maximumEntryCount = 200
  static let maximumEntryLength = 80

  @Published private(set) var entries: [String]

  private static let storageKey = "customVocabulary"
  private let defaults: UserDefaults

  init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
    let stored = defaults.stringArray(forKey: Self.storageKey) ?? []
    self.entries = Self.normalized(stored).prefix(Self.maximumEntryCount).map { $0 }
  }

  @discardableResult
  func add(from input: String) -> Int {
    guard entries.count < Self.maximumEntryCount else { return 0 }

    let candidates = Self.normalized(
      input.components(separatedBy: CharacterSet(charactersIn: ",\n"))
    )
    let existing = Set(entries.map(Self.comparisonKey))
    var seen = existing
    var additions: [String] = []

    for candidate in candidates {
      guard entries.count + additions.count < Self.maximumEntryCount else { break }
      let key = Self.comparisonKey(candidate)
      guard seen.insert(key).inserted else { continue }
      additions.append(candidate)
    }

    guard !additions.isEmpty else { return 0 }
    entries.append(contentsOf: additions)
    persist()
    return additions.count
  }

  func remove(_ entry: String) {
    let key = Self.comparisonKey(entry)
    entries.removeAll { Self.comparisonKey($0) == key }
    persist()
  }

  private func persist() {
    defaults.set(entries, forKey: Self.storageKey)
  }

  private static func normalized(_ values: [String]) -> [String] {
    values.compactMap { value in
      let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !trimmed.isEmpty else { return nil }
      return String(trimmed.prefix(maximumEntryLength))
    }
  }

  private static func comparisonKey(_ value: String) -> String {
    value.folding(options: [.caseInsensitive], locale: .current)
  }
}
