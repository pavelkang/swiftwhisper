import Foundation

struct InlineTextDiff {
  enum Change: Equatable {
    case unchanged
    case removed
    case added
  }

  struct Segment: Equatable {
    let text: String
    let change: Change
  }

  static func segments(from original: String, to corrected: String) -> [Segment] {
    let originalTokens = tokens(in: original)
    let correctedTokens = tokens(in: corrected)
    let difference = correctedTokens.difference(from: originalTokens)

    var removedOffsets = Set<Int>()
    var addedOffsets = Set<Int>()
    for change in difference {
      switch change {
      case .remove(let offset, _, _):
        removedOffsets.insert(offset)
      case .insert(let offset, _, _):
        addedOffsets.insert(offset)
      }
    }

    var result: [Segment] = []
    var originalOffset = 0
    var correctedOffset = 0

    while originalOffset < originalTokens.count || correctedOffset < correctedTokens.count {
      if originalOffset < originalTokens.count, removedOffsets.contains(originalOffset) {
        append(originalTokens[originalOffset], as: .removed, to: &result)
        originalOffset += 1
      } else if correctedOffset < correctedTokens.count, addedOffsets.contains(correctedOffset) {
        append(correctedTokens[correctedOffset], as: .added, to: &result)
        correctedOffset += 1
      } else if originalOffset < originalTokens.count, correctedOffset < correctedTokens.count {
        append(correctedTokens[correctedOffset], as: .unchanged, to: &result)
        originalOffset += 1
        correctedOffset += 1
      } else if originalOffset < originalTokens.count {
        append(originalTokens[originalOffset], as: .removed, to: &result)
        originalOffset += 1
      } else {
        append(correctedTokens[correctedOffset], as: .added, to: &result)
        correctedOffset += 1
      }
    }

    return result
  }

  private static func tokens(in text: String) -> [String] {
    guard !text.isEmpty else { return [] }

    let expression = try! NSRegularExpression(
      pattern: #"\s+|[\p{L}\p{M}\p{N}]+(?:['’][\p{L}\p{M}\p{N}]+)*|."#,
      options: [.dotMatchesLineSeparators]
    )
    let range = NSRange(text.startIndex..<text.endIndex, in: text)
    return expression.matches(in: text, range: range).compactMap { match in
      guard let tokenRange = Range(match.range, in: text) else { return nil }
      return String(text[tokenRange])
    }
  }

  private static func append(_ text: String, as change: Change, to result: inout [Segment]) {
    guard !text.isEmpty else { return }

    if let last = result.last, last.change == change {
      result[result.count - 1] = Segment(text: last.text + text, change: change)
    } else {
      result.append(Segment(text: text, change: change))
    }
  }
}
