import GladeKit
import SwiftUI

/// One finding in the storage list, in columns: whether it’s in the clean, what it
/// is and when it was last used, how it comes back, and its size. Where it lives is
/// in the tooltip and the inspector, and search still finds it by path.
struct FindingRow: View {
  @Environment(AppModel.self) private var model
  var entry: FindingEntry
  /// The list is narrow, so the recovery column shows only its symbol.
  var compact = false

  /// Wide enough for "999 GB" so sizes line up down the list.
  static let sizeWidth: CGFloat = 64
  /// The checkbox column, shared with group headers so everything lines up.
  static let checkWidth: CGFloat = 18
  /// An app’s icon beside its name: the height of the name and its second line.
  static let appIconSize: CGFloat = 26

  var body: some View {
    let finding = entry.finding
    HStack(spacing: Metrics.m) {
      HStack(spacing: Metrics.s) {
        leading(finding)
          .frame(width: Self.checkWidth)
        if finding.isApp {
          AppIconView(path: finding.paths.first, size: Self.appIconSize)
        }
        VStack(alignment: .leading, spacing: 1) {
          Text(finding.title)
            .lineLimit(1)
            .truncationMode(.middle)
          if let second = secondLine(finding) {
            Text(second)
              .font(.callout)
              .foregroundStyle(.secondary)
              .lineLimit(1)
          }
        }
        .alignmentGuide(.listRowSeparatorLeading) { $0[.leading] }
      }
      .padding(.leading, CGFloat(entry.depth) * Metrics.xl)
      .opacity(finding.isBlocked ? 0.55 : 1)
      Spacer(minLength: Metrics.s)
      if finding.isApp {
        AppColumn(finding: finding, compact: compact)
      } else {
        RecoveryColumn(recovery: finding.recovery, compact: compact)
      }
      Text(Format.bytes(finding.bytes))
        .monospacedDigit()
        .foregroundStyle(finding.isBlocked ? .secondary : .primary)
        .frame(width: Self.sizeWidth, alignment: .trailing)
    }
    .padding(.vertical, 2)
    .help(finding.paths.map(Redactor.tilde).joined(separator: "\n"))
  }

  @ViewBuilder
  private func leading(_ finding: Finding) -> some View {
    if finding.hasOwnUninstaller {
      // Its button is in the row; nothing here to tick.
      Image(systemName: Symbols.uninstaller)
        .foregroundStyle(.secondary)
        .help(finding.blockers.first?.detail ?? "")
        .accessibilityLabel(finding.blockers.first { $0.kind == .ownUninstaller }?.detail ?? "")
    } else if let blocker = finding.blockers.first {
      Image(systemName: "lock.fill")
        .foregroundStyle(.secondary)
        .help(blocker.detail)
        .accessibilityLabel("Can’t be removed: \(blocker.detail)")
    } else {
      Toggle(finding.title, isOn: Binding(
        get: { model.isSelected(finding.id) },
        set: { model.setSelected(finding.id, $0) }
      ))
      .toggleStyle(CheckToggleStyle())
    }
  }

  /// Why it can’t be removed, or when it was last used. An app says when it was last
  /// opened; why it can’t be ticked is in the tooltip and the inspector.
  private func secondLine(_ finding: Finding) -> String? {
    if finding.isApp { return finding.openedText }
    return finding.blockers.first?.detail ?? finding.lastUsedText
  }
}
