import GladeKit
import SwiftUI

/// One item in a clean: what it was, its size, and what happened to it.
struct EntryRow: View {
  var entry: ReceiptEntry

  var body: some View {
    HStack(spacing: Metrics.m) {
      CategoryIcon(entry.category)
      VStack(alignment: .leading, spacing: 2) {
        Text(entry.title)
          .lineLimit(1)
          .truncationMode(.middle)
        Label {
          Text(entry.outcome.title)
            .fixedSize(horizontal: false, vertical: true)
        } icon: {
          Image(systemName: entry.outcome.symbol)
            .foregroundStyle(entry.outcome.tint)
        }
        .font(.callout)
        .foregroundStyle(.secondary)
      }
      Spacer(minLength: Metrics.m)
      Text(Format.bytes(entry.bytes))
        .monospacedDigit()
        .foregroundStyle(entry.outcome == .deleted || entry.outcome.trashedCount > 0 ? .primary : .tertiary)
    }
    .padding(.horizontal, Metrics.l)
    .padding(.vertical, Metrics.m)
    .accessibilityElement(children: .combine)
  }
}
