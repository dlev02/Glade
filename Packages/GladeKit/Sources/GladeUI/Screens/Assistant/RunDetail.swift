import AppKit
import GladeKit
import SwiftUI

/// One run in full: the exact system prompt, prompt and reply as plain monospaced
/// text, what it cost, and anything Glade refused from it.
struct RunDetail: View {
  @Environment(AppModel.self) private var model
  var run: AssistantRun
  @State private var part: RunPart = .prompt
  @State private var showsRefused = true

  var body: some View {
    VStack(alignment: .leading, spacing: Metrics.m) {
      VStack(alignment: .leading, spacing: Metrics.xs) {
        HStack(alignment: .firstTextBaseline, spacing: Metrics.s) {
          Text(run.purposeTitle)
            .font(.title3.weight(.semibold))
          if run.proactive {
            Label("Started by Glade", systemImage: "bolt.badge.automatic")
              .font(.caption)
              .foregroundStyle(.secondary)
              .padding(.horizontal, 7)
              .padding(.vertical, 2)
              .background(Palette.track, in: .capsule)
          }
          Spacer()
          Text(run.date.formatted(date: .abbreviated, time: .standard))
            .font(.callout)
            .foregroundStyle(.secondary)
        }
        Text(([provider] + run.figures).joined(separator: " · "))
          .font(.callout)
          .foregroundStyle(.secondary)
          .monospacedDigit()
      }

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
        DisclosureGroup(isExpanded: $showsRefused) {
          VStack(alignment: .leading, spacing: Metrics.xs) {
            ForEach(Array(run.rejected.enumerated()), id: \.offset) { _, line in
              Text(verbatim: line)
                .font(.callout.monospaced())
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
            }
          }
          .padding(.top, Metrics.xs)
        } label: {
          Label(run.rejected.count == 1 ? "Glade refused 1 suggestion" : "Glade refused \(run.rejected.count) suggestions", systemImage: "hand.raised")
            .font(.callout)
        }
      }

      HStack {
        Picker("Show", selection: $part) {
          ForEach(RunPart.allCases) { part in
            Text(part.title).tag(part)
          }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .fixedSize()
        Spacer()
        Text("\(text.count.formatted()) characters")
          .font(.caption)
          .foregroundStyle(.tertiary)
          .monospacedDigit()
        Button("Copy", systemImage: "document.on.document") { copy() }
          .disabled(text.isEmpty)
      }

      ScrollView {
        Text(verbatim: text.isEmpty ? "—" : text)
          .font(.callout.monospaced())
          .textSelection(.enabled)
          .frame(maxWidth: .infinity, alignment: .leading)
          .padding(Metrics.m)
      }
      .background(Palette.card, in: .rect(cornerRadius: Metrics.innerRadius))
      .overlay {
        RoundedRectangle(cornerRadius: Metrics.innerRadius)
          .strokeBorder(Palette.hairline.opacity(0.6), lineWidth: Metrics.hairline)
      }
    }
    .padding(Metrics.l)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
  }

  private var provider: String {
    let name = model.providerName(run.provider)
    return run.model.map { "\(name) · \($0)" } ?? name
  }

  private var text: String {
    switch part {
    case .system: run.system
    case .prompt: run.prompt
    case .reply: run.reply ?? ""
    }
  }

  private func copy() {
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(text, forType: .string)
  }
}

/// The three texts a run holds.
private enum RunPart: String, CaseIterable, Identifiable {
  case prompt, system, reply

  var id: String { rawValue }

  var title: String {
    switch self {
    case .prompt: "Prompt"
    case .system: "System Prompt"
    case .reply: "Reply"
    }
  }
}
