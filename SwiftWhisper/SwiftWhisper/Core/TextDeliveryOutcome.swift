enum TextDeliveryOutcome: Sendable, Equatable {
  case inserted
  case duplicateSuppressed
  case notInserted
}
