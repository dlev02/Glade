import GladeKit
import SwiftUI

/// The floating bar at the foot of the storage screen: what’s selected, how boldly
/// it was chosen, and the one button that frees it (⌘Return). One layer of glass;
/// the button inside it is a plain filled capsule.
struct CleanBar: View {
  @Environment(AppModel.self) private var model
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  var freeUp: () -> Void

  var body: some View {
    let count = model.cleanItems.count
    let free = model.immediateBytes
    let trash = model.trashBytes
    HStack(spacing: Metrics.l) {
      // In a narrower window the shorter wordings keep it on one line.
      ViewThatFits(in: .horizontal) {
        Text(summary(count: count, free: free, trash: trash))
        Text(summary(count: count, free: free, trash: trash, short: true))
        Text(itemCount(count))
      }
      .lineLimit(1)
      .font(.headline)
      .monospacedDigit()
      .contentTransition(.numericText())
      .animation(reduceMotion ? nil : .snappy(duration: 0.18), value: free + trash)
      .layoutPriority(-1)
      Spacer(minLength: 0)
      // On the button’s line, so its popover opens over the list and covers nothing
      // in the bar.
      LevelMenu(arrowEdge: .top)
        .font(.callout)
        .foregroundStyle(.secondary)
      FullDiskAccessGlyph()
      Button(free > 0 ? "Free Up \(Format.bytes(free))" : trash > 0 ? "Move to Trash" : "Free Up", action: freeUp)
        .filledAction()
        .monospacedDigit()
        .keyboardShortcut(.return, modifiers: .command)
        .disabled(count == 0 || model.isScanning || model.isCleaning)
        .help("Review and clean the selected items (⌘Return)")
        .accessibilityIdentifier("cleanBar.freeUp")
    }
    .padding(.leading, Metrics.l + Metrics.xs)
    .padding(.trailing, Metrics.s)
    .padding(.vertical, Metrics.s)
    .glassEffect(.regular, in: .capsule)
    .padding(.horizontal, Metrics.l)
    .padding(.bottom, Metrics.m)
  }

  /// "19 items · 102 GB to free · 12 GB to the Trash": what is freed now comes first,
  /// and the Trash is named separately because it frees nothing until it’s emptied.
  private func summary(count: Int, free: Int64, trash: Int64, short: Bool = false) -> String {
    guard count > 0 else { return "Nothing selected" }
    let items = itemCount(count)
    if short, free > 0, trash > 0 {
      return "\(items) · \(Format.bytes(free)) + \(Format.bytes(trash)) to the Trash"
    }
    var parts = [items]
    if free > 0 { parts.append("\(Format.bytes(free)) to free") }
    if trash > 0 { parts.append("\(Format.bytes(trash)) to the Trash") }
    return parts.joined(separator: " · ")
  }

  private func itemCount(_ count: Int) -> String {
    switch count {
    case 0: "Nothing selected"
    case 1: "1 item"
    default: "\(count) items"
    }
  }
}
