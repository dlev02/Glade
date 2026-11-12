import GladeKit
import SwiftUI

/// The heading of one category in the storage list: a checkbox for the whole group,
/// its name (which folds the group away), how much of it is selected, and its size,
/// lined up with the sizes of the rows below.
struct GroupHeader: View {
  @Environment(AppModel.self) private var model
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  var group: FindingGroup
  @Binding var isExpanded: Bool
  @State private var isHovering = false

  var body: some View {
    HStack(spacing: Metrics.m) {
      HStack(spacing: Metrics.s) {
        checkbox
          .frame(width: FindingRow.checkWidth)
        disclosure
      }
      Spacer(minLength: Metrics.s)
      let selected = selectedBytes
      if selected > 0 {
        Text("\(Format.bytes(selected)) selected")
          .font(.callout)
          .foregroundStyle(.secondary)
          .monospacedDigit()
          .lineLimit(1)
          .contentTransition(.numericText())
      }
      Text(Format.bytes(group.totalBytes))
        .font(.headline)
        .monospacedDigit()
        .frame(width: FindingRow.sizeWidth, alignment: .trailing)
    }
    .padding(.vertical, Metrics.xs)
  }

  private var disclosure: some View {
    Button {
      withAnimation(reduceMotion ? nil : .snappy(duration: 0.18)) { isExpanded.toggle() }
    } label: {
      HStack(spacing: Metrics.s) {
        CategoryIcon(group.category, size: 22)
        Text(group.category.title)
          .font(.headline)
          .foregroundStyle(.primary)
          .lineLimit(1)
        Image(systemName: "chevron.right")
          .font(.caption.weight(.semibold))
          .foregroundStyle(.secondary)
          .rotationEffect(.degrees(isExpanded ? 90 : 0))
          .accessibilityHidden(true)
      }
      .padding(.vertical, 2)
      .padding(.leading, 2)
      .padding(.trailing, 6)
      .background(
        Color.primary.opacity(isHovering ? 0.06 : 0),
        in: .rect(cornerRadius: 6)
      )
      .contentShape(.rect)
    }
    .buttonStyle(.plain)
    .onHover { hovering in
      withAnimation(.snappy(duration: 0.12)) { isHovering = hovering }
    }
    .accessibilityLabel(group.category.title)
    .accessibilityValue(isExpanded ? "Expanded" : "Collapsed")
    .accessibilityHint(isExpanded ? "Hides this group’s items" : "Shows this group’s items")
  }

  @ViewBuilder
  private var checkbox: some View {
    if group.category == .installedApps {
      // Apps are chosen one at a time, never all at once.
      Color.clear
    } else if group.selectableIDs.isEmpty {
      Image(systemName: "lock.fill")
        .foregroundStyle(.tertiary)
        .help("Nothing here can be removed right now")
        .accessibilityLabel("Nothing in \(group.category.title) can be removed right now")
    } else {
      let bindings = group.selectableIDs.map { id in
        Binding(get: { model.isSelected(id) }, set: { model.setSelected(id, $0) })
      }
      Toggle("Select all \(group.category.title)", sources: bindings, isOn: \.self)
        .toggleStyle(CheckToggleStyle())
    }
  }

  /// What the group’s selection adds to a clean, with nested findings counted once.
  private var selectedBytes: Int64 {
    let chosen = Set(group.entries.lazy.map(\.id).filter { model.isSelected($0) })
    return group.entries.reduce(0) { sum, entry in
      guard chosen.contains(entry.id) else { return sum }
      if let container = entry.finding.within, chosen.contains(container) { return sum }
      return sum + entry.finding.bytes
    }
  }
}
