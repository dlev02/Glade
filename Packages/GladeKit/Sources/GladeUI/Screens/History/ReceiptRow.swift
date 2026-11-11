import GladeKit
import SwiftUI

/// One clean in the list: who started it, when, how many items, and how much it freed.
struct ReceiptRow: View {
  @Environment(AppModel.self) private var model
  var receipt: Receipt

  var body: some View {
    let name = receipt.initiator.name(providerName: { model.providerName($0) })
    let items = receipt.entries.count == 1 ? "1 item" : "\(receipt.entries.count) items"
    HStack(spacing: Metrics.m) {
      Image(systemName: receipt.initiator.symbol)
        .font(.system(size: 13, weight: .medium))
        .foregroundStyle(.secondary)
        .frame(width: 28, height: 28)
        .background(.fill.tertiary, in: .circle)
        .accessibilityHidden(true)
      VStack(alignment: .leading, spacing: 1) {
        Text(name)
          .lineLimit(1)
        Text("\(receipt.date.formatted(date: .omitted, time: .shortened)) · \(items)")
          .font(.callout)
          .foregroundStyle(.secondary)
          .monospacedDigit()
      }
      Spacer(minLength: Metrics.m)
      Text(Format.bytes(receipt.removedBytes))
        .font(.figure(15))
    }
    .padding(.vertical, Metrics.xs)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel("\(name), \(receipt.date.formatted(date: .omitted, time: .shortened)), \(items), \(Format.bytes(receipt.removedBytes))")
  }
}
