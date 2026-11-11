import GladeKit
import SwiftUI

/// Where a question is written: one glass container pinned under the conversation,
/// the text on top and, underneath, which AI answers, how hard it thinks, and Send.
struct Composer: View {
  @Environment(AppModel.self) private var model
  @Environment(\.openSettings) private var openSettings
  /// The provider that will answer.
  var active: ProviderStatus
  /// Every provider that could answer.
  var ready: [ProviderStatus]
  var isBusy: Bool
  @State private var text = ""
  @FocusState private var isFocused: Bool

  var body: some View {
    VStack(alignment: .leading, spacing: Metrics.s) {
      TextField("Ask about this Mac", text: $text, axis: .vertical)
        .textFieldStyle(.plain)
        .lineLimit(1...6)
        .focused($isFocused)
        .accessibilityLabel("Question")
        .accessibilityIdentifier("composer.field")
        .padding(.horizontal, Metrics.xs)
        .padding(.top, 2)
        .onKeyPress(.return, phases: .down) { press in
          if press.modifiers.contains(.shift) {
            text.append("\n")
          } else {
            send()
          }
          return .handled
        }

      HStack(spacing: Metrics.m) {
        providerMenu
        if active.supportsEffort {
          effortMenu
        }
        Spacer(minLength: Metrics.s)
        Button("Send", systemImage: "arrow.up") { send() }
          .labelStyle(.iconOnly)
          .buttonStyle(SendButtonStyle())
          .disabled(!canSend)
          .help("Send (Return)")
          .accessibilityIdentifier("composer.send")
      }
      .font(.callout)
    }
    .padding(Metrics.m)
    .glassEffect(.regular, in: .rect(cornerRadius: 20))
    .padding(.horizontal, Metrics.xl)
    .padding(.bottom, Metrics.l)
    .frame(maxWidth: ConversationView.columnWidth + Metrics.xl * 2)
    .frame(maxWidth: .infinity)
    .onAppear { isFocused = true }
  }

  private var providerMenu: some View {
    ChoicePopover(
      "Answers",
      value: active.name,
      selection: Binding(get: { active.id }, set: { model.preferProvider($0) }),
      sections: [ChoiceSection(choices: ready.map {
        Choice($0.id, $0.name, subtitle: $0.isLocal ? "On this Mac" : "Sees names, sizes and dates")
      })],
      footer: ChoiceFooter("Assistant Settings…", symbol: Symbols.settings) {
        openSettings()
        Task {
          // Give the Settings window a moment to start listening.
          try? await Task.sleep(for: .milliseconds(300))
          NotificationCenter.default.post(name: .gladeShowAssistantSettings, object: nil)
        }
      }
    )
    .accessibilityIdentifier("composer.provider")
    .help("Which AI answers")
  }

  private var effortMenu: some View {
    @Bindable var model = model
    return ChoicePopover(
      "Effort",
      value: "\(model.config.assistant.effort.title) effort",
      selection: $model.config.assistant.effort,
      sections: [ChoiceSection(choices: Effort.allCases.map { Choice($0, $0.title, subtitle: $0.consequence) })]
    )
    .accessibilityIdentifier("composer.effort")
    .help("How hard it thinks")
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

/// A 28-point circle filled with the accent, greyed while there's nothing to send.
/// A plain fill, not glass, because it sits on the composer's glass.
private struct SendButtonStyle: ButtonStyle {
  @Environment(\.isEnabled) private var isEnabled

  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .font(.system(size: 13, weight: .bold))
      .foregroundStyle(isEnabled ? AnyShapeStyle(.white) : AnyShapeStyle(.tertiary))
      .frame(width: 28, height: 28)
      .background(isEnabled ? AnyShapeStyle(.tint) : AnyShapeStyle(.fill.secondary), in: .circle)
      .opacity(configuration.isPressed ? 0.8 : 1)
      .contentShape(.circle)
      .animation(.snappy(duration: 0.12), value: isEnabled)
  }
}

extension Effort {
  /// What the effort means, in a few words, for the choice list.
  var consequence: String {
    switch self {
    case .automatic: "The AI’s own setting"
    case .low: "Quickest answers"
    case .medium: "A balance of speed and care"
    case .high: "Thinks longer"
    case .max: "Thinks longest; slowest"
    }
  }
}
