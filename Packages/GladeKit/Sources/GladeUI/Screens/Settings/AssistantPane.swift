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
        // Up here, where it's always in view, rather than at the foot of the pane.
        Label("Cloud AIs see names, sizes and dates only", systemImage: "lock.shield")
          .foregroundStyle(.secondary)
      }

      if !unavailable.isEmpty {
        Section("Unavailable") {
          ForEach(unavailable) { provider in
            ProviderRow(provider: provider, model: modelBinding(\.models, provider.id), showsHandle: false)
          }
        }
      }

      Section {
        menuPicker("Effort", selection: $model.config.assistant.effort, value: model.config.assistant.effort.title) {
          ForEach(Effort.allCases) { effort in
            Text(effort.title).tag(effort)
          }
        }
        menuPicker("For a closer look, call in", selection: $model.config.assistant.deepProvider, value: deepTitle) {
          Text("Same").tag(String?.none)
          if !ready.isEmpty { Divider() }
          ForEach(ready) { provider in
            Text(provider.name).tag(Optional(provider.id))
          }
        }
        if let deep = deepProvider, deep.takesModel {
          LabeledContent("Model") {
            ModelField(title: "\(deep.name) closer look", suggestions: deep.models, value: modelBinding(\.deepModels, deep.id))
          }
        }
      }

      Section {
        Toggle("Check in by itself when a limit is crossed", isOn: $model.config.assistant.proactive)
        menuPicker("Runs a day", selection: $model.config.assistant.runsPerDay, value: runsTitle(model.config.assistant.runsPerDay)) {
          ForEach(Self.runChoices, id: \.self) { choice in
            Text(runsTitle(choice)).tag(choice)
          }
        }
        .disabled(!model.config.assistant.proactive)
      }

    }
    .confirmationDialog("Share file excerpts with cloud AIs?", isPresented: $confirmsSharing) {
      Button("Share Excerpts") { model.config.assistant.shareExcerpts = true }
    } message: {
      Text("AIs that run online will see a few lines from inside some files. AIs on this Mac always may.")
    }
  }

  /// A setting chosen from a quiet menu: the label on the left, "Default ⌄" on the right.
  private func menuPicker<Value: Hashable, Choices: View>(
    _ title: String, selection: Binding<Value>, value: String, @ViewBuilder choices: () -> Choices
  ) -> some View {
    LabeledContent(title) {
      Menu {
        Picker(title, selection: selection, content: choices)
          .pickerStyle(.inline)
          .labelsHidden()
      } label: {
        Text(value)
      }
      .menuStyle(.borderlessButton)
      .menuIndicator(.visible)
      .fixedSize()
      .tint(.secondary)
      .accessibilityLabel(title)
      .accessibilityValue(value)
    }
  }

  private var deepTitle: String {
    guard let id = model.config.assistant.deepProvider else { return "Same" }
    return model.providerName(id)
  }

  private func runsTitle(_ choice: Int?) -> String {
    choice.map(String.init) ?? "No Limit"
  }

  /// Every provider, in the person's order, with any new ones at the end.
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
