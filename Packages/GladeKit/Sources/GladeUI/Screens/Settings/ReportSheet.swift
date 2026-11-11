import AppKit
import GladeKit
import SwiftUI

/// A problem report the person reads before sharing: saved to the Desktop, then
/// attached to a GitHub issue by hand. Nothing is sent anywhere by Glade.
struct ReportSheet: View {
  @Environment(AppModel.self) private var model
  @Environment(\.dismiss) private var dismiss
  @State private var includeNames = false
  @State private var text: String?
  @State private var saved: URL?
  @State private var problem: String?

  var body: some View {
    VStack(alignment: .leading, spacing: Metrics.m) {
      Text("Report a Problem")
        .font(.title2.bold())
      Toggle("Include file and folder names", isOn: $includeNames)

      ScrollView {
        Text(text ?? "")
          .font(.caption.monospaced())
          .textSelection(.enabled)
          .frame(maxWidth: .infinity, alignment: .leading)
          .padding(Metrics.m)
      }
      .overlay {
        if text == nil { ProgressView() }
      }
      .background(Color(nsColor: .textBackgroundColor), in: .rect(cornerRadius: Metrics.innerRadius))
      .overlay {
        RoundedRectangle(cornerRadius: Metrics.innerRadius)
          .strokeBorder(Palette.hairline, lineWidth: Metrics.hairline)
      }

      HStack(spacing: Metrics.s) {
        if let saved {
          Label("Saved to the Desktop as “\(saved.lastPathComponent)”", systemImage: "checkmark.circle.fill")
            .font(.callout)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .truncationMode(.middle)
        } else if let problem {
          Text(problem)
            .font(.callout)
            .foregroundStyle(.secondary)
            .lineLimit(2)
        }
        Spacer(minLength: Metrics.s)
        Button("Cancel", role: .cancel) { dismiss() }
          .secondaryAction()
          .keyboardShortcut(.cancelAction)
        Button("Save to Desktop", action: save)
          .secondaryAction()
          .disabled(text == nil)
        Button("Open GitHub Issue") {
          if let url = DiagnosticReport.issueURL() { NSWorkspace.shared.open(url) }
        }
        .principalAction()
        .keyboardShortcut(.defaultAction)
      }
    }
    .padding(Metrics.xl)
    .frame(width: 640, height: 540)
    .task(id: includeNames) { await build() }
  }

  private func build() async {
    text = nil
    saved = nil
    let options = DiagnosticReport.Options(includeFindings: includeNames)
    let extra = [(title: "Assistants", body: assistantSummary)]
    text = await Task.detached { DiagnosticReport.build(options: options, extra: extra) }.value
  }

  private var assistantSummary: String {
    guard !model.providers.isEmpty else { return "Not checked yet." }
    return model.providers.map { provider in
      let state = switch provider.state {
      case .ready: "ready"
      case .notInstalled: "not installed"
      case .needsSignIn: "needs sign-in"
      case .unavailable(let reason): "unavailable (\(reason))"
      }
      return "\(provider.name): \(state)\(provider.version.map { ", version \($0)" } ?? "")"
    }.joined(separator: "\n")
  }

  private func save() {
    guard let text else { return }
    do {
      let url = try DiagnosticReport.save(text)
      saved = url
      problem = nil
      NSWorkspace.shared.activateFileViewerSelecting([url])
    } catch {
      problem = "Couldn’t save the report: \(error.localizedDescription)"
    }
  }
}
