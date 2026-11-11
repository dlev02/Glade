import GladeKit
import SwiftUI

/// A clean in the History list, drawn like Storage’s rows: a soft fill under the
/// pointer and a tinted fill, not a solid slab, when it’s the one open in the receipt.
struct HistoryRow: View {
  var receipt: Receipt
  var isSelected: Bool
  var select: () -> Void
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var hovering = false

  var body: some View {
    Button(action: select) {
      ReceiptRow(receipt: receipt)
        .padding(.horizontal, Metrics.s)
        .padding(.vertical, 2)
        .background(fill, in: .rect(cornerRadius: Metrics.s))
        .contentShape(.rect(cornerRadius: Metrics.s))
    }
    .buttonStyle(.plain)
    .onHover { hovering = $0 }
    .animation(reduceMotion ? nil : .snappy(duration: 0.12), value: hovering)
    .accessibilityAddTraits(isSelected ? .isSelected : [])
  }

  private var fill: AnyShapeStyle {
    if isSelected { return AnyShapeStyle(.tint.opacity(0.16)) }
    return hovering ? AnyShapeStyle(.fill.quaternary) : AnyShapeStyle(.clear)
  }
}
