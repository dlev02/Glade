import GladeKit
import SwiftUI

/// One clean in the list: who started it, when, how much and how many items.
struct ReceiptRow: View {
  @Environment(AppModel.self) private var model
  var receipt: Receipt

  var body: some View {
    HStack(spacing: Metrics.m) {
      Image(systemName: receipt.initiator.symbol)
        .foregroundStyle(.secondary)
        .frame(width: 20)
        .accessibilityHidden(true)
      VStack(alignment: .leading, spacing: 2) {
        Text(model.initiatorTitle(receipt.initiator))
          .lineLimit(1)
        Text("\(receipt.date.formatted(date: .omitted, time: .shortened)) · \(receipt.entries.count == 1 ? "1 item" : "\(receipt.entries.count) items")")
          .font(.caption)
          .foregroundStyle(.secondary)
          .monospacedDigit()
      }
      Spacer(minLength: Metrics.s)
      Text(Format.bytes(receipt.removedBytes))
        .monospacedDigit()
    }
    .padding(.vertical, 3)
    .accessibilityElement(children: .combine)
  }
}
