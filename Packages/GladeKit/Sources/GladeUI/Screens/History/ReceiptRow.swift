import GladeKit
import SwiftUI

/// One clean in the list: who started it, when, how many items, and how much it freed.
struct ReceiptRow: View {
  @Environment(AppModel.self) private var model
  var receipt: Receipt

  var body: some View {
    let name = receipt.initiator.name(providerName: { model.providerName($0) })
    let items = receipt.entries.count == 1 ? "1 item" : "\(receipt.entries.count) items"
    let amount = [
      receipt.freedBytes > 0 ? "\(Format.bytes(receipt.freedBytes)) freed" : nil,
      receipt.trashedBytes > 0 ? "\(Format.bytes(receipt.trashedBytes)) moved to the Trash" : nil,
    ].compactMap(\.self).joined(separator: ", ")
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
      // What it freed; a clean that only moved things to the Trash shows that amount
      // beside the Trash symbol instead.
      HStack(spacing: Metrics.xs) {
        if receipt.freedBytes == 0, receipt.trashedBytes > 0 {
          Image(systemName: "trash")
            .font(.callout)
            .foregroundStyle(.secondary)
        }
        Text(Format.bytes(receipt.freedBytes > 0 ? receipt.freedBytes : receipt.trashedBytes))
          .font(.figure(15))
      }
    }
    .padding(.vertical, Metrics.xs)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel("\(name), \(receipt.date.formatted(date: .omitted, time: .shortened)), \(items), \(amount)")
  }
}
