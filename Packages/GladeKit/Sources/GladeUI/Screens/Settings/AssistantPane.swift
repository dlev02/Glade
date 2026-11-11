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
    Form {
      Section {
        ForEach(ordered) { provider in
          ProviderRow(provider: provider, model: modelBinding(\.models, provider.id))
            .contextMenu {
              Button("Move Up") { move(provider.id, by: -1) }
                .disabled(provider.id == ordered.first?.id)
              Button("Move Down") { move(provider.id, by: 1) }
                .disabled(provider.id == ordered.last?.id)
            }
        }
        .onMove { from, to in
          var ids = ordered.map(\.id)
          ids.move(fromOffsets: from, toOffset: to)
          model.config.assistant.order = ids
        }
      } header: {
        HStack {
          Text("Ask in This Order")
          Spacer()
          if refreshing {
            ProgressView().controlSize(.small)
          } else {
            Button("Refresh", systemImage: "arrow.clockwise") {
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
        Text("The first one that’s ready answers.")
          .foregroundStyle(.secondary)
      }

      Section {
        Picker("Effort", selection: $model.config.assistant.effort) {
          ForEach(Effort.allCases) { effort in
            Text(effort.title).tag(effort)
          }
        }
        Picker("For a closer look, call in", selection: $model.config.assistant.deepProvider) {
          Text("Same").tag(String?.none)
          if !ready.isEmpty { Divider() }
          ForEach(ready) { provider in
            Text(provider.name).tag(Optional(provider.id))
          }
        }
        if let deep = deepProvider {
          LabeledContent("Model") {
            ModelField(title: "\(deep.name) closer look", suggestions: deep.models, value: modelBinding(\.deepModels, deep.id))
          }
        }
      } footer: {
        Text("When the everyday model is unsure, it can ask the stronger one.")
          .foregroundStyle(.secondary)
      }

      Section {
        Toggle("Share short file excerpts with cloud AIs", isOn: Binding(
          get: { model.config.assistant.shareExcerpts },
          set: { share in
            if share { confirmsSharing = true } else { model.config.assistant.shareExcerpts = false }
          }
        ))
      } footer: {
        Text("Without this, they see names, sizes and dates only.")
          .foregroundStyle(.secondary)
      }

      Section {
        Toggle("Check in by itself when a limit is crossed", isOn: $model.config.assistant.proactive)
        Picker("Runs a day", selection: $model.config.assistant.runsPerDay) {
          ForEach(Self.runChoices, id: \.self) { choice in
            Text(choice.map(String.init) ?? "No Limit").tag(choice)
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

  private func move(_ id: String, by offset: Int) {
    var ids = orderedProviders.map(\.id)
    guard let index = ids.firstIndex(of: id), ids.indices.contains(index + offset) else { return }
    ids.swapAt(index, index + offset)
    model.config.assistant.order = ids
  }
}
