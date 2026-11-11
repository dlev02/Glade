import GladeKit
import SwiftUI

/// The floating bar at the foot of the storage screen: what's selected, how much of
/// it goes to the Trash, and the one button that frees it.
struct CleanBar: View {
  @Environment(AppModel.self) private var model
  var freeUp: () -> Void

  var body: some View {
    let count = model.selectedIDs.count
    let total = model.selectedBytes
    let trash = max(0, total - model.immediateBytes)
    HStack(spacing: Metrics.l) {
      VStack(alignment: .leading, spacing: 2) {
        Text(count == 0 ? "Nothing selected" : "\(count) \(count == 1 ? "item" : "items") · \(Format.bytes(total))")
          .font(.headline)
          .contentTransition(.numericText())
        if trash > 0 {
          Text("\(Format.bytes(trash)) to Trash")
            .font(.callout)
            .foregroundStyle(.secondary)
            .contentTransition(.numericText())
        }
      }
      .monospacedDigit()
      .accessibilityElement(children: .combine)
      Spacer(minLength: Metrics.m)
      Button(total > 0 ? "Free Up \(Format.bytes(total))" : "Free Up", action: freeUp)
        .buttonStyle(.glassProminent)
        .controlSize(.large)
        .disabled(count == 0 || model.isScanning || model.isCleaning)
    }
    .padding(.leading, Metrics.l)
    .padding(.trailing, Metrics.s)
    .padding(.vertical, Metrics.s)
    .glassEffect(.regular, in: .capsule)
    .padding(.horizontal, Metrics.l)
    .padding(.bottom, Metrics.m)
    .animation(.snappy, value: total)
  }
}
