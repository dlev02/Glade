import AppKit
import GladeKit
import SwiftUI

/// One run in full: exactly what was sent and what came back, as plain monospaced
/// text, so a person can check the AI saw names and sizes, not file contents.
struct RunSheet: View {
  @Environment(AppModel.self) private var model
  @Environment(\.dismiss) private var dismiss
  var run: AssistantRun
  @State private var part: RunPart = .prompt
  @State private var showsRefused = false

  var body: some View {
    VStack(alignment: .leading, spacing: Metrics.m) {
      header

      if let error = run.error {
        Label {
          Text(verbatim: error)
            .textSelection(.enabled)
        } icon: {
          Image(systemName: "exclamationmark.triangle")
            .foregroundStyle(Palette.warning)
        }
        .font(.callout)
      }

      if !run.rejected.isEmpty {
        AdviceDisclosure(isExpanded: $showsRefused) {
          Text(run.rejected.count == 1 ? "1 suggestion refused" : "\(run.rejected.count) suggestions refused")
            .font(.callout)
            .foregroundStyle(.secondary)
        } content: {
          VStack(alignment: .leading, spacing: Metrics.xs) {
            ForEach(Array(run.rejected.enumerated()), id: \.offset) { _, line in
              Text(verbatim: line)
                .font(.callout.monospaced())
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
            }
          }
        }
      }

      Picker("Show", selection: $part) {
        ForEach(RunPart.allCases) { part in
          Text(part.title).tag(part)
        }
      }
      .pickerStyle(.segmented)
      .labelsHidden()
      .fixedSize()

      ScrollView {
        Text(verbatim: text.isEmpty ? "—" : text)
          .font(.callout.monospaced())
          .textSelection(.enabled)
          .frame(maxWidth: .infinity, alignment: .leading)
          .padding(Metrics.m)
      }
      .background(Palette.card, in: .rect(cornerRadius: Metrics.innerRadius))

      HStack {
        CopyButton { text }
          .disabled(text.isEmpty)
          .secondaryAction()
        Spacer()
        Button("Done") { dismiss() }
          .keyboardShortcut(.defaultAction)
          .principalAction()
      }
      .controlSize(.large)
    }
    .padding(Metrics.l)
    .frame(minWidth: 560, idealWidth: 720, minHeight: 440, idealHeight: 600, alignment: .topLeading)
  }

  private var header: some View {
    VStack(alignment: .leading, spacing: 2) {
      HStack(alignment: .firstTextBaseline, spacing: Metrics.s) {
        Text(run.purposeTitle)
          .font(.title3.weight(.semibold))
        if run.proactive {
          Image(systemName: "bolt.badge.automatic")
            .foregroundStyle(.secondary)
            .help("Started by Glade")
            .accessibilityLabel("Started by Glade")
        }
      }
      Text(([provider, run.date.formatted(date: .abbreviated, time: .shortened)] + run.figures).joined(separator: " · "))
        .font(.callout)
        .foregroundStyle(.secondary)
        .monospacedDigit()
    }
  }

  private var provider: String {
    let name = model.responderName(run.provider)
    return run.model.map { "\(name) · \($0)" } ?? name
  }

  private var text: String {
    switch part {
    case .system: run.system
    case .prompt: run.prompt
    case .reply: run.reply ?? ""
    }
  }

}

/// The three texts a run holds.
private enum RunPart: String, CaseIterable, Identifiable {
  case prompt, system, reply

  var id: String { rawValue }

  var title: String {
    switch self {
    case .prompt: "Prompt"
    case .system: "System"
    case .reply: "Reply"
    }
  }
}
