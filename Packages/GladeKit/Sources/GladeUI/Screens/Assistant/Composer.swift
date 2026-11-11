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
  @State private var typesModel = false
  @State private var typedModel = ""
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
        if active.takesModel, !active.models.isEmpty {
          modelMenu
        }
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
    .alert("Model for \(active.name)", isPresented: $typesModel) {
      TextField("Model name", text: $typedModel)
      Button("Use") { setModel(typedModel.trimmingCharacters(in: .whitespacesAndNewlines)) }
        .keyboardShortcut(.defaultAction)
      Button("Cancel", role: .cancel) {}
    } message: {
      Text("The name \(active.name) knows it by.")
    }
  }

  private var providerMenu: some View {
    ChoicePopover(
      "Answers",
      value: active.name,
      selection: Binding(get: { active.id }, set: { model.preferProvider($0) }),
      sections: [
        ChoiceSection("On this Mac", choices: ready.filter(\.isLocal).map { Choice($0.id, $0.name, subtitle: "Nothing leaves this Mac") }),
        ChoiceSection("Cloud", choices: ready.filter { !$0.isLocal }.map { Choice($0.id, $0.name, subtitle: "Sees names, sizes and dates") }),
      ].filter { !$0.choices.isEmpty },
      footer: ChoiceFooter("Assistant Settings…") {
        openSettings()
        Task {
          // Give the Settings window a moment to start listening.
          try? await Task.sleep(for: .milliseconds(300))
          NotificationCenter.default.post(name: .gladeShowAssistantSettings, object: nil)
        }
      },
      arrowEdge: .top
    )
    .accessibilityIdentifier("composer.provider")
    .help("Which AI answers")
  }

  /// The model the chosen AI uses, from its own suggestions, kept in the same setting
  /// as Settings › Assistant so the two always agree.
  private var modelMenu: some View {
    let current = model.config.assistant.models[active.id] ?? ""
    let suggestions = active.models
    let names = current.isEmpty || suggestions.contains(current) ? suggestions : suggestions + [current]
    return ChoicePopover(
      "Model",
      value: current.isEmpty ? "Default model" : ModelName.display(current),
      selection: Binding(get: { current }, set: { setModel($0) }),
      sections: [
        ChoiceSection(choices: [Choice("", "Default", subtitle: "\(active.name)’s own choice")]),
        ChoiceSection(choices: names.map { Choice($0, ModelName.display($0)) }),
      ],
      footer: ChoiceFooter("Other…") {
        typedModel = current
        typesModel = true
      },
      arrowEdge: .top
    )
    .accessibilityIdentifier("composer.model")
    .help("Which model answers")
  }

  private func setModel(_ name: String) {
    model.config.assistant.models[active.id] = name.isEmpty ? nil : name
  }

  private var effortMenu: some View {
    @Bindable var model = model
    return ChoicePopover(
      "Effort",
      value: "\(model.config.assistant.effort.title) effort",
      selection: $model.config.assistant.effort,
      sections: [ChoiceSection(choices: Effort.allCases.map { Choice($0, $0.title, subtitle: $0.consequence) })],
      arrowEdge: .top
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
