import GladeKit
import SwiftUI

/// The floating bar at the foot of the storage screen: what's selected, how boldly
/// it was chosen, and the one button that frees it (⌘Return). One layer of glass;
/// the button inside it is a plain filled capsule.
struct CleanBar: View {
  @Environment(AppModel.self) private var model
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  var freeUp: () -> Void

  var body: some View {
    let count = model.selectedIDs.count
    let total = model.selectedBytes
    HStack(spacing: Metrics.l) {
      VStack(alignment: .leading, spacing: 0) {
        Text(count == 0 ? "Nothing selected" : "\(count) \(count == 1 ? "item" : "items") · \(Format.bytes(total))")
          .font(.headline)
          .monospacedDigit()
          .contentTransition(.numericText())
          .animation(reduceMotion ? nil : .snappy(duration: 0.18), value: total)
        LevelMenu()
          .font(.callout)
          .foregroundStyle(.secondary)
      }
      Spacer(minLength: Metrics.m)
      Button(total > 0 ? "Free Up \(Format.bytes(total))" : "Free Up", action: freeUp)
        .filledAction()
        .monospacedDigit()
        .keyboardShortcut(.return, modifiers: .command)
        .disabled(count == 0 || model.isScanning || model.isCleaning)
        .help("Free up the selected items (⌘Return)")
        .accessibilityIdentifier("cleanBar.freeUp")
    }
    .padding(.leading, Metrics.l + Metrics.xs)
    .padding(.trailing, Metrics.s)
    .padding(.vertical, Metrics.s)
    .glassEffect(.regular, in: .capsule)
    .padding(.horizontal, Metrics.l)
    .padding(.bottom, Metrics.m)
  }
}
