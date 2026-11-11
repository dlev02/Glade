import GladeKit
import SwiftUI

/// One reason the assistant gave, with what it did to the selection and the finding.
struct AdviceNote: Identifiable {
  enum Kind: CaseIterable {
    case added, leftAlone, review

    var title: String {
      switch self {
      case .added: "Added"
      case .leftAlone: "Left alone"
      case .review: "To review"
      }
    }

    /// "+2 added", "1 left alone", "1 to review".
    func count(_ count: Int) -> String {
      switch self {
      case .added: "+\(count) added"
      case .leftAlone: "\(count) left alone"
      case .review: "\(count) to review"
      }
    }

    var symbol: String {
      switch self {
      case .added: "plus.circle.fill"
      case .leftAlone: "minus.circle"
      case .review: "eye.circle"
      }
    }

    /// The accent for what was added, grey for what was left, orange for a look.
    func style(mark: Color) -> AnyShapeStyle {
      switch self {
      case .added: AnyShapeStyle(mark)
      case .leftAlone: AnyShapeStyle(.secondary)
      case .review: AnyShapeStyle(Palette.warning)
      }
    }

    func notes(in advice: StorageAdvice) -> [StorageAdvice.Note] {
      switch self {
      case .added: advice.select
      case .leftAlone: advice.deselect
      case .review: advice.review
      }
    }
  }

  var kind: Kind
  var note: StorageAdvice.Note
  /// The finding’s title from the scan, if it’s one Glade knows.
  var title: String?
  /// The finding’s size, if it’s one Glade knows.
  var bytes: Int64?

  var id: String { "\(kind)-\(note.id)" }
}
