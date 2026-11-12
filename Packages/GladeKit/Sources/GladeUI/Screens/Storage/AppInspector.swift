import AppKit
import GladeKit
import SwiftUI

/// The inspector for an installed app: what goes to the Trash (the app and each of its
/// data folders, with their sizes), what stays and why, and how to remove it: the tick
/// box, or the app’s own uninstaller, or Finder when macOS needs the person’s password.
struct AppInspector: View {
  @Environment(AppModel.self) private var model
  var finding: Finding

  var body: some View {
    let app = finding.app
    VStack(alignment: .leading, spacing: Metrics.l) {
      VStack(alignment: .leading, spacing: Metrics.s) {
        AppIconView(path: finding.paths.first, size: 48)
        Text(finding.title)
          .font(.title3.weight(.semibold))
          .fixedSize(horizontal: false, vertical: true)
          .textSelection(.enabled)
        if let subtitle = subtitle(app) {
          Text(subtitle)
            .font(.callout)
            .foregroundStyle(.secondary)
        }
        Text(Format.bytes(finding.bytes))
          .font(.figure(26))
      }

      section("Uninstall") { removal }

      if !finding.hasOwnUninstaller, let app {
        // Only what Glade would move is "going"; otherwise it’s just what it takes up.
        section(finding.isBlocked ? "Takes up" : "Goes to the Trash") {
          part(symbolPath: finding.paths.first, title: "The app", bytes: app.bundleBytes, path: app.bundlePath)
          ForEach(app.parts, id: \.path) { item in
            part(symbolPath: nil, title: item.label, bytes: item.bytes, path: item.path)
          }
        }
      }

      if let kept = app?.kept, !kept.isEmpty, !finding.hasOwnUninstaller {
        section("Stays") {
          ForEach(kept, id: \.path) { item in
            VStack(alignment: .leading, spacing: 1) {
              Text(item.label)
              Text(item.reason)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }
            .help(Redactor.tilde(item.path))
            .accessibilityElement(children: .combine)
          }
        }
      }

      if let opened = lastOpenedNote {
        section("Details") {
          Text(opened)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
      }
    }
  }

  /// "Version 10.4.5 · App Store".
  private func subtitle(_ app: AppDetails?) -> String? {
    guard let app else { return nil }
    return [app.version.map { "Version \($0)" }, app.source == .other ? nil : app.source.title]
      .compactMap { $0 }.joined(separator: " · ")
  }

  /// The tick box, or the one thing that removes it instead, with the reason.
  @ViewBuilder
  private var removal: some View {
    if finding.hasOwnUninstaller {
      note(finding.blockers.first { $0.kind == .ownUninstaller }?.detail)
      if finding.app?.uninstaller != nil {
        Button("Open Uninstaller", systemImage: Symbols.uninstaller) { model.openUninstaller(finding) }
          .secondaryAction()
          .accessibilityIdentifier("app.openUninstaller")
        note("Scan again afterwards to clear anything it leaves.")
      }
    } else if finding.isAppOpen {
      note(finding.blockers.first { $0.kind == .appRunning }?.detail)
    } else if finding.needsFinder {
      note(finding.blockers.first { $0.kind == .needsAdmin }?.detail)
      Button("Show in Finder", systemImage: Symbols.showInFinder) { model.showInFinder(finding.paths.first ?? "") }
        .secondaryAction()
    } else if let blocker = finding.blockers.first {
      note(blocker.detail)
    } else {
      Toggle("Include in clean", isOn: Binding(
        get: { model.isSelected(finding.id) },
        set: { model.setSelected(finding.id, $0) }
      ))
      .toggleStyle(.checkbox)
    }
  }

  private var lastOpenedNote: String? {
    finding.evidence.first { $0.hasPrefix("Last ") || $0.hasPrefix("Its program") || $0.hasPrefix("macOS hasn’t") }
  }

  private func part(symbolPath: String?, title: String, bytes: Int64, path: String) -> some View {
    HStack(spacing: Metrics.s) {
      Group {
        if let symbolPath {
          AppIconView(path: symbolPath, size: 18)
        } else {
          Image(systemName: "folder")
            .foregroundStyle(.secondary)
        }
      }
      .frame(width: 18)
      Text(title)
        .lineLimit(1)
      Spacer(minLength: Metrics.s)
      Text(Format.bytes(bytes))
        .monospacedDigit()
        .foregroundStyle(.secondary)
    }
    .help(Redactor.tilde(path))
    .contextMenu {
      Button("Show in Finder", systemImage: Symbols.showInFinder) { model.showInFinder(path) }
    }
    .accessibilityElement(children: .combine)
  }

  @ViewBuilder
  private func note(_ text: String?) -> some View {
    if let text {
      Text(text)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
    }
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
