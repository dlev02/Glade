import GladeKit
import SwiftUI

/// How a finding comes back, as a column in the storage list: a coloured symbol and
/// one grey word. When the list is narrow the word goes, except for "Can’t be undone",
/// which always shows, because nothing brings it back. Its red is on the glyph: red
/// words at this size are too faint to read.
struct RecoveryColumn: View {
  var recovery: Recovery
  var compact: Bool

  /// Wide enough for the longest word, so the symbols line up down the list.
  static let width: CGFloat = 132
  static let compactWidth: CGFloat = 22

  var body: some View {
    let showsWord = !compact || recovery == .permanent
    HStack(spacing: 5) {
      Image(systemName: recovery.symbol)
        .foregroundStyle(recovery.color)
        .frame(width: 16)
      if showsWord {
        Text(recovery.shortTitle)
          .foregroundStyle(recovery == .permanent ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
          .fixedSize()
      }
    }
    .font(.callout)
    // A narrow "Can’t be undone" keeps its own width rather than spilling over the title.
    .frame(width: compact ? (showsWord ? nil : Self.compactWidth) : Self.width, alignment: compact ? .trailing : .leading)
    .help(recovery.explanation)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(recovery.title)
  }
}

extension Recovery {
  /// One word for the list column; `title` says it in full.
  var shortTitle: String {
    switch self {
    case .automatic: "Rebuilds"
    case .redownload: "Downloads again"
    case .reinstall: "Needs reinstall"
    case .permanent: "Can’t be undone"
    }
  }
}
