import GladeKit
import SwiftUI

/// One finding in the storage list: whether it's in the clean, what it is, when it
/// was last used and where it lives, how it comes back, and its size.
struct FindingRow: View {
  @Environment(AppModel.self) private var model
  var entry: FindingEntry
  /// The list is narrow, so the recovery badge shows only its symbol.
  var compact = false

  /// Wide enough for "999 GB" so sizes line up down the list.
  static let sizeWidth: CGFloat = 64

  var body: some View {
    let finding = entry.finding
    HStack(spacing: Metrics.s) {
      HStack(spacing: Metrics.s) {
        leading(finding)
          .frame(width: 18)
        VStack(alignment: .leading, spacing: 2) {
          Text(finding.title)
            .lineLimit(1)
            .truncationMode(.middle)
          secondLine(finding)
            .font(.callout)
            .foregroundStyle(.secondary)
            .lineLimit(1)
        }
        .alignmentGuide(.listRowSeparatorLeading) { $0[.leading] }
      }
      .padding(.leading, CGFloat(entry.depth) * Metrics.xl)
      .opacity(finding.isBlocked ? 0.55 : 1)
      Spacer(minLength: Metrics.s)
      if compact {
        Image(systemName: finding.recovery.symbol)
          .font(.callout)
          .foregroundStyle(finding.recovery.color)
          .frame(width: 22, height: 22)
          .background(finding.recovery.color.opacity(0.12), in: .circle)
          .help("\(finding.recovery.title). \(finding.recovery.explanation)")
          .accessibilityLabel(finding.recovery.title)
      } else {
        RecoveryBadge(finding.recovery)
          .fixedSize()
      }
      Text(Format.bytes(finding.bytes))
        .monospacedDigit()
        .foregroundStyle(finding.isBlocked ? .secondary : .primary)
        .frame(width: Self.sizeWidth, alignment: .trailing)
    }
    .padding(.vertical, 3)
  }

  @ViewBuilder
  private func leading(_ finding: Finding) -> some View {
    if let blocker = finding.blockers.first {
      Image(systemName: "lock.fill")
        .foregroundStyle(.secondary)
        .help(blocker.detail)
        .accessibilityLabel("Can’t be removed: \(blocker.detail)")
    } else {
      Toggle(finding.title, isOn: Binding(
        get: { model.isSelected(finding.id) },
        set: { model.setSelected(finding.id, $0) }
      ))
      .toggleStyle(.checkbox)
      .labelsHidden()
    }
  }

  @ViewBuilder
  private func secondLine(_ finding: Finding) -> some View {
    if let blocker = finding.blockers.first {
      Text(blocker.detail)
        .truncationMode(.tail)
    } else {
      HStack(spacing: 0) {
        if let used = finding.lastUsedText {
          Text(used)
            .fixedSize()
          if finding.locationText != nil { Text(" · ").fixedSize() }
        }
        if let location = finding.locationText {
          Text(location)
            .truncationMode(.middle)
            .foregroundStyle(.tertiary)
        }
      }
    }
  }
}
