import GladeKit

/// A symbol for who started a clean. Every name is checked against the catalog.
extension Initiator {
  var symbol: String {
    switch self {
    case .user: "person"
    case .commandLine: "apple.terminal"
    case .assistant: "sparkles"
    case .automation: "gearshape.arrow.trianglehead.2.clockwise.rotate.90"
    }
  }
}
