import GladeKit
import SwiftUI

/// The heading of one category in the storage list: a checkbox for the whole group,
/// its name (which folds the group away), how much of it is selected, and its size.
struct GroupHeader: View {
  @Environment(AppModel.self) private var model
  var group: FindingGroup
  @Binding var isExpanded: Bool

  var body: some View {
    HStack(spacing: Metrics.s) {
      checkbox
        .frame(width: 18)
      Button {
        withAnimation(.snappy) { isExpanded.toggle() }
      } label: {
        HStack(spacing: Metrics.s) {
          CategoryIcon(group.category, size: 22)
          Text(group.category.title)
            .font(.headline)
            .foregroundStyle(.primary)
            .lineLimit(1)
          Image(systemName: "chevron.right")
            .font(.caption.weight(.semibold))
            .foregroundStyle(.tertiary)
            .rotationEffect(.degrees(isExpanded ? 90 : 0))
            .accessibilityHidden(true)
        }
        .contentShape(.rect)
      }
      .buttonStyle(.plain)
      .accessibilityLabel(group.category.title)
      .accessibilityValue(isExpanded ? "Expanded" : "Collapsed")
      .accessibilityHint(isExpanded ? "Hides this group’s items" : "Shows this group’s items")
      Spacer(minLength: Metrics.s)
      let selected = selectedBytes
      if selected > 0 {
        Text("\(Format.bytes(selected)) selected")
          .font(.callout)
          .foregroundStyle(.secondary)
          .monospacedDigit()
          .lineLimit(1)
      }
      Text(Format.bytes(group.totalBytes))
        .font(.headline)
        .monospacedDigit()
        .frame(width: FindingRow.sizeWidth, alignment: .trailing)
    }
    .padding(.vertical, Metrics.xs)
  }

  @ViewBuilder
  private var checkbox: some View {
    if group.selectableIDs.isEmpty {
      Image(systemName: "lock.fill")
        .foregroundStyle(.tertiary)
        .help("Nothing here can be removed right now")
        .accessibilityLabel("Nothing in \(group.category.title) can be removed right now")
    } else {
      let bindings = group.selectableIDs.map { id in
        Binding(get: { model.isSelected(id) }, set: { model.setSelected(id, $0) })
      }
      Toggle("Select all \(group.category.title)", sources: bindings, isOn: \.self)
        .toggleStyle(.checkbox)
        .labelsHidden()
    }
  }

  /// What the group's selection adds to a clean, with nested findings counted once.
  private var selectedBytes: Int64 {
    let chosen = Set(group.entries.lazy.map(\.id).filter { model.isSelected($0) })
    return group.entries.reduce(0) { sum, entry in
      guard chosen.contains(entry.id) else { return sum }
      if let container = entry.finding.within, chosen.contains(container) { return sum }
      return sum + entry.finding.bytes
    }
  }
}
