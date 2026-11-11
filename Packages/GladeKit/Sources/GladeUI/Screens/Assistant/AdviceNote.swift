import GladeKit
import SwiftUI

/// One reason the assistant gave, with what it did to the plan and the finding's name.
struct AdviceNote: Identifiable {
  enum Kind {
    case added, leftAlone, review

    var title: String {
      switch self {
      case .added: "Added"
      case .leftAlone: "Left alone"
      case .review: "To review"
      }
    }

    var symbol: String {
      switch self {
      case .added: "plus.circle"
      case .leftAlone: "minus.circle"
      case .review: "eye"
      }
    }

    var style: AnyShapeStyle {
      switch self {
      case .added: AnyShapeStyle(.tint)
      case .leftAlone: AnyShapeStyle(.secondary)
      case .review: AnyShapeStyle(Palette.warning)
      }
    }
  }

  var kind: Kind
  var note: StorageAdvice.Note
  /// The finding's title from the scan, if it's one Glade knows.
  var title: String?

  var id: String { "\(kind)-\(note.id)" }
}
