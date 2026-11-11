import GladeKit
import SwiftUI

/// What happened to one item in a clean, in words and a symbol, never colour alone.
extension RemovalOutcome {
  var title: String {
    switch self {
    case .deleted: "Deleted"
    case .trashed: "In the Trash"
    case .skipped(let reason): "Skipped: \(reason)"
    case .failed(let reason): "Failed: \(reason)"
    case .wouldRemove: "Would be removed"
    }
  }

  var symbol: String {
    switch self {
    case .deleted: "checkmark"
    case .trashed: "trash"
    case .skipped: "minus.circle"
    case .failed: "exclamationmark.triangle"
    case .wouldRemove: "eye"
    }
  }

  var tint: Color {
    if case .failed = self { return Palette.warning }
    return .secondary
  }

  /// How many things sit in the Trash for this item.
  var trashedCount: Int {
    if case .trashed(let locations) = self { return locations.count }
    return 0
  }

  /// Whether the item left its place, removed or moved to the Trash.
  var removedSomething: Bool {
    switch self {
    case .deleted, .trashed: true
    default: false
    }
  }
}
