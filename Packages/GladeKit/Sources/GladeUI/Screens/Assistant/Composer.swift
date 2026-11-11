import GladeKit
import SwiftUI

/// Where a question is written, pinned under the conversation in a floating glass
/// capsule, with which AI will answer and how hard it should think.
struct Composer: View {
  @Environment(AppModel.self) private var model
  /// The provider that will answer.
  var active: ProviderStatus
  /// Every provider that could answer.
  var ready: [ProviderStatus]
  var isBusy: Bool
  @State private var text = ""
  @FocusState private var isFocused: Bool

  var body: some View {
    @Bindable var model = model
    VStack(alignment: .leading, spacing: Metrics.s) {
      HStack(spacing: Metrics.l) {
        Picker("Answers", selection: Binding(get: { active.id }, set: { model.preferProvider($0) })) {
          ForEach(ready) { provider in
            Text(provider.isLocal ? "\(provider.name) · on this Mac" : provider.name).tag(provider.id)
          }
        }
        .pickerStyle(.menu)
        .labelsHidden()
        .fixedSize()
        .help("Which AI answers")
        if active.supportsEffort {
          Picker("Effort", selection: $model.config.assistant.effort) {
            ForEach(Effort.allCases) { effort in
              Text(effort.title).tag(effort)
            }
          }
          .pickerStyle(.menu)
          .fixedSize()
        }
      }
      .controlSize(.small)
      .font(.callout)
      .padding(.leading, Metrics.s)

      HStack(alignment: .bottom, spacing: Metrics.s) {
        TextField("Ask about this Mac…", text: $text, axis: .vertical)
          .textFieldStyle(.plain)
          .lineLimit(1...6)
          .focused($isFocused)
          .padding(.vertical, 7)
          .onKeyPress(.return, phases: .down) { press in
            if press.modifiers.contains(.shift) {
              text.append("\n")
            } else {
              send()
            }
            return .handled
          }
        Button("Send", systemImage: "arrow.up") { send() }
          .labelStyle(.iconOnly)
          .buttonStyle(.borderedProminent)
          .buttonBorderShape(.circle)
          .disabled(!canSend)
          .help("Send")
      }
      .padding(.leading, Metrics.l)
      .padding(.trailing, 6)
      .padding(.vertical, 6)
      .glassEffect(.regular, in: .rect(cornerRadius: 20))
    }
    .padding(.horizontal, Metrics.xl)
    .padding(.bottom, Metrics.l)
    .frame(maxWidth: ConversationView.columnWidth)
    .frame(maxWidth: .infinity)
    .onAppear { isFocused = true }
  }

  private var canSend: Bool {
    !isBusy && !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }

  private func send() {
    guard canSend else { return }
    let question = text
    text = ""
    Task { await model.ask(question) }
  }
}
