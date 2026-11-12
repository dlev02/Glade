import GladeKit
import SwiftUI

/// The third column of an app’s row, where other rows say how they come back (every
/// app comes back the same way, by reinstalling): where it came from, or, for an app
/// with its own uninstaller, the button that opens it.
struct AppColumn: View {
  @Environment(AppModel.self) private var model
  var finding: Finding
  var compact: Bool

  var body: some View {
    Group {
      if finding.hasOwnUninstaller, finding.app?.uninstaller != nil {
        Button {
          model.openUninstaller(finding)
        } label: {
          if compact {
            Image(systemName: Symbols.uninstaller)
          } else {
            Text("Open Uninstaller")
          }
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .help(finding.blockers.first { $0.kind == .ownUninstaller }?.detail ?? "")
        .accessibilityLabel("Open Uninstaller for \(finding.title)")
      } else if !compact {
        Text(finding.app?.source.title ?? "")
          .foregroundStyle(.secondary)
          .padding(.leading, 16 + 5)
          .accessibilityLabel(finding.app.map { "From \($0.source.title)" } ?? "")
      }
    }
    .font(.callout)
    .frame(width: compact ? RecoveryColumn.compactWidth + 8 : RecoveryColumn.width, alignment: compact ? .trailing : .leading)
  }
}
