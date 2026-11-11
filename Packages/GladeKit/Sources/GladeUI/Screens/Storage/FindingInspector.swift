import AppKit
import GladeKit
import SwiftUI

/// Everything about the highlighted finding: what it is, what happens when it's
/// removed, why it is or isn't selected, the facts behind that, and where it lives.
struct FindingInspector: View {
  @Environment(AppModel.self) private var model
  var finding: Finding?
  /// The highlighted findings when more than one row is highlighted; their totals
  /// show instead of a single finding.
  var highlightedFindings: [Finding] = []

  var body: some View {
    ScrollView {
      Group {
        if let finding {
          content(finding)
        } else if highlightedFindings.count > 1 {
          SelectionTotals(title: "\(highlightedFindings.count) Items", findings: highlightedFindings)
        } else {
          // The clean bar already says how many and how much; here, only how it splits.
          SelectionTotals(title: "Selected", findings: model.cleanItems, showsTotal: false)
        }
      }
      .padding(Metrics.l)
      .frame(maxWidth: .infinity, alignment: .leading)
    }
  }

  private func content(_ finding: Finding) -> some View {
    VStack(alignment: .leading, spacing: Metrics.l) {
      VStack(alignment: .leading, spacing: Metrics.s) {
        HStack(spacing: Metrics.s) {
          CategoryIcon(finding.category, size: 22)
          Text(finding.category.title)
            .font(.callout)
            .foregroundStyle(.secondary)
        }
        Text(finding.title)
          .font(.title3.weight(.semibold))
          .fixedSize(horizontal: false, vertical: true)
          .textSelection(.enabled)
        Text(Format.bytes(finding.bytes))
          .font(.figure(26))
        Text(finding.detail)
          .fixedSize(horizontal: false, vertical: true)
      }

      // The badge says how it comes back (its tooltip says more); the description
      // above usually says it in words already.
      section("After removal") {
        RecoveryBadge(finding.recovery)
      }

      section("How it’s removed") {
        Label(finding.removalText(model.config), systemImage: finding.removalSymbol(model.config))
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
      }

      section(finding.isBlocked ? "Can’t be removed now" : "Selection") {
        if finding.isBlocked {
          ForEach(finding.blockers, id: \.self) { blocker in
            Label(blocker.detail, systemImage: "lock.fill")
              .fixedSize(horizontal: false, vertical: true)
          }
        } else {
          Toggle("Include in clean", isOn: Binding(
            get: { model.isSelected(finding.id) },
            set: { model.setSelected(finding.id, $0) }
          ))
          .toggleStyle(.checkbox)
          if let reason = selectionNote(finding) {
            Text(reason)
              .foregroundStyle(.secondary)
              .fixedSize(horizontal: false, vertical: true)
          }
        }
      }

      if !facts(finding).isEmpty {
        section("Details") {
          ForEach(facts(finding), id: \.self) { line in
            HStack(alignment: .firstTextBaseline, spacing: Metrics.s) {
              Text("•").foregroundStyle(.tertiary).accessibilityHidden(true)
              Text(line).fixedSize(horizontal: false, vertical: true)
            }
            .foregroundStyle(.secondary)
          }
        }
      }

      if !finding.paths.isEmpty {
        section(finding.paths.count == 1 ? "Location" : "Locations") {
          ForEach(finding.paths, id: \.self) { path in
            HStack(spacing: Metrics.s) {
              Text(Redactor.tilde(path))
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .truncationMode(.middle)
                .textSelection(.enabled)
              Spacer(minLength: 0)
              Button("Show in Finder", systemImage: Symbols.showInFinder) {
                NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
              }
              .labelStyle(.iconOnly)
              .buttonStyle(.borderless)
              .help("Show in Finder")
            }
          }
        }
      }
    }
  }

  /// Why it is or isn't in the clean, unless the reason is only that it rebuilds or
  /// downloads again, which the badge above already says.
  private func selectionNote(_ finding: Finding) -> String? {
    guard let reason = model.reason(for: finding.id) else { return nil }
    let (selected, rule) = Planner.decide(finding, level: model.level)
    if selected, rule == reason, finding.recovery != .permanent { return nil }
    return reason
  }

  /// The evidence lines, plus the copy a duplicate keeps and its project. Each is a
  /// sentence with a full stop, like the evidence the scanners write.
  private func facts(_ finding: Finding) -> [String] {
    var lines = finding.evidence
    if let keeps = finding.keeps { lines.append("Keeps the copy at \(Redactor.tilde(keeps)).") }
    if let project = finding.project { lines.append("Part of \(project).") }
    if finding.fileCount > 0 { lines.append(finding.fileCount == 1 ? "1 file." : "\(finding.fileCount.formatted()) files.") }
    return lines.map { $0.hasSuffix(".") || $0.hasSuffix("?") || $0.hasSuffix("!") ? $0 : $0 + "." }
  }

  private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
    VStack(alignment: .leading, spacing: Metrics.s) {
      Text(title)
        .font(.subheadline.weight(.semibold))
        .accessibilityAddTraits(.isHeader)
      content()
    }
  }
}
