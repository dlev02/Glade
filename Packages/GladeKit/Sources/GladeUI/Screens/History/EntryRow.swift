import GladeKit
import SwiftUI

/// One item in a clean: what it was and its size. The group it sits in says what
/// happened to it; only items that weren't removed say why.
struct EntryRow: View {
  var entry: ReceiptEntry
  var showsOutcome = false

  var body: some View {
    HStack(spacing: Metrics.m) {
      CategoryIcon(entry.category)
      VStack(alignment: .leading, spacing: 1) {
        Text(entry.title)
          .lineLimit(1)
          .truncationMode(.middle)
          .help(entry.title)
        if showsOutcome {
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
      }
      Spacer(minLength: Metrics.s)
      Text(Format.bytes(entry.bytes))
        .monospacedDigit()
        .foregroundStyle(entry.outcome.removedSomething ? .primary : .tertiary)
    }
    .padding(.horizontal, Metrics.m)
    .padding(.vertical, Metrics.s)
    .accessibilityElement(children: .combine)
    .accessibilityValue(entry.outcome.title)
  }
}
