import GladeKit
import SwiftUI

/// Which AIs Glade asks, in what order, with which models, and how much they may see.
struct AssistantPane: View {
  @Environment(AppModel.self) private var model
  @State private var refreshing = false
  @State private var confirmsSharing = false

  /// Runs-a-day choices; `nil` is no limit.
  private static let runChoices: [Int?] = [1, 3, 6, 12, 24, nil]

  var body: some View {
    @Bindable var model = model
    let ordered = orderedProviders
    let ready = ordered.filter(\.isReady)
    let unavailable = ordered.filter { !$0.isReady }
    Form {
      Section {
        ForEach(ready) { provider in
          ProviderRow(provider: provider, model: modelBinding(\.models, provider.id), showsHandle: ready.count > 1)
            .contextMenu {
              Button("Move Up") { move(provider.id, by: -1) }
                .disabled(provider.id == ready.first?.id)
              Button("Move Down") { move(provider.id, by: 1) }
                .disabled(provider.id == ready.last?.id)
            }
            .accessibilityActions {
              Button("Move Up") { move(provider.id, by: -1) }
              Button("Move Down") { move(provider.id, by: 1) }
            }
        }
        .onMove { from, to in
          var ids = ready.map(\.id)
          ids.move(fromOffsets: from, toOffset: to)
          model.config.assistant.order = ids + unavailable.map(\.id)
        }
        if ready.isEmpty {
          Text("None yet")
            .foregroundStyle(.secondary)
        }
      } header: {
        HStack {
          Text("Available")
          Spacer()
          if refreshing {
            ProgressView().controlSize(.small)
          } else {
            Button("Look Again", systemImage: Symbols.scan) {
              refreshing = true
              Task {
                await model.refreshProviders()
                refreshing = false
              }
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.borderless)
            .help("Look for AIs again")
          }
        }
      } footer: {
        // Up here, where it’s always in view, rather than at the foot of the pane.
        Label("Cloud AIs see names, sizes and dates only", systemImage: Symbols.protected)
          .foregroundStyle(.secondary)
      }

      if !unavailable.isEmpty {
        Section("Unavailable") {
          ForEach(unavailable) { provider in
            ProviderRow(provider: provider, model: modelBinding(\.models, provider.id), showsHandle: false, reservesHandle: ready.count > 1)
          }
        }
      }

      Section {
        // The same choices, with the same lines under them, as the composer’s.
        choicePicker(
          "Effort", value: model.config.assistant.effort.title, selection: $model.config.assistant.effort,
          choices: Effort.allCases.map { Choice($0, $0.title, subtitle: $0.consequence) }
        )
        // Who gives the second opinion and with which model, in one row, so its model
        // can’t be taken for the everyday one chosen in each AI’s row above. It reads
        // and writes only the second-opinion setting.
        LabeledContent("Second opinion") {
          HStack(spacing: Metrics.l) {
            ChoicePopover(
              "Second opinion from", value: deepTitle, selection: $model.config.assistant.deepProvider,
              sections: [
                ChoiceSection(choices: [Choice(String?.none, "Same AI", subtitle: "The AI that answered")]),
                ChoiceSection(choices: ready.map { Choice(Optional($0.id), $0.name) }),
              ].filter { !$0.choices.isEmpty }
            )
            if let deep = deepProvider, deep.takesModel {
              ModelField(
                title: "second opinions", suggestions: deep.models,
                value: modelBinding(\.deepModels, deep.id),
                // The same AI with its everyday model would only repeat itself, so
                // that pairing means no second opinion.
                emptyTitle: model.config.assistant.deepProvider == nil ? "None" : "Default"
              )
            }
          }
        }
      }

      Section {
        Toggle("Ask AI at alert thresholds", isOn: $model.config.assistant.proactive)
        choicePicker(
          "Daily limit", value: runsTitle(model.config.assistant.runsPerDay), selection: $model.config.assistant.runsPerDay,
          choices: Self.runChoices.map { Choice($0, runsTitle($0)) }
        )
        .disabled(!model.config.assistant.proactive)
      }

      Section {
        Toggle("Use notes", isOn: $model.config.assistant.useNotes)
        if model.config.assistant.useNotes { NoteRows() }
      } header: {
        Text("Notes")
      } footer: {
        Text("Sent with every question, to whichever AI answers.")
          .foregroundStyle(.secondary)
      }
    }
    .confirmationDialog("Share file excerpts with cloud AIs?", isPresented: $confirmsSharing) {
      Button("Share Excerpts") { model.config.assistant.shareExcerpts = true }
    } message: {
      Text("AIs that run online will see a few lines from inside some files. AIs on this Mac always may.")
    }
  }

  /// A setting chosen from a quiet popover, like the composer’s and the clean level’s:
  /// the label on the left, "Medium ⌄" on the right.
  private func choicePicker<Value: Hashable>(
    _ title: String, value: String, selection: Binding<Value>, choices: [Choice<Value>]
  ) -> some View {
    choicePicker(title, value: value, selection: selection, sections: [ChoiceSection(choices: choices)])
  }

  private func choicePicker<Value: Hashable>(
    _ title: String, value: String, selection: Binding<Value>, sections: [ChoiceSection<Value>]
  ) -> some View {
    LabeledContent(title) {
      ChoicePopover(title, value: value, selection: selection, sections: sections)
    }
  }

  private var deepTitle: String {
    guard let id = model.config.assistant.deepProvider else { return "Same AI" }
    return model.providerName(id)
  }

  private func runsTitle(_ choice: Int?) -> String {
    choice.map(String.init) ?? "No Limit"
  }

  /// Every provider, in the person’s order, with any new ones at the end.
  private var orderedProviders: [ProviderStatus] {
    let order = model.config.assistant.order
    return order.compactMap { id in model.providers.first { $0.id == id } }
      + model.providers.filter { !order.contains($0.id) }
  }

  /// The provider asked for a closer look: the chosen one, or the one that would answer.
  private var deepProvider: ProviderStatus? {
    if let id = model.config.assistant.deepProvider { return model.providers.first { $0.id == id } }
    return model.activeProvider
  }

  private func modelBinding(_ key: WritableKeyPath<AssistantSettings, [String: String]>, _ id: String) -> Binding<String> {
    Binding(
      get: { model.config.assistant[keyPath: key][id] ?? "" },
      set: { name in model.config.assistant[keyPath: key][id] = name.isEmpty ? nil : name }
    )
  }

  /// Moves a ready provider up or down among the ready ones.
  private func move(_ id: String, by offset: Int) {
    let ordered = orderedProviders
    var ready = ordered.filter(\.isReady).map(\.id)
    guard let index = ready.firstIndex(of: id), ready.indices.contains(index + offset) else { return }
    ready.swapAt(index, index + offset)
    model.config.assistant.order = ready + ordered.filter { !$0.isReady }.map(\.id)
  }
}
