import GladeKit
import SwiftUI

/// How Glade looks, when it opens, and how boldly it cleans by default.
struct GeneralPane: View {
  @Environment(AppModel.self) private var model
  @Environment(\.screenOverrides) private var overrides
  @State private var opensAtLogin = false
  @State private var loginProblem: String?

  var body: some View {
    @Bindable var model = model
    Form {
      Section {
        Picker("Appearance", selection: $model.appearance) {
          ForEach(Appearance.allCases) { appearance in
            Text(appearance.title).tag(appearance)
          }
        }
        .pickerStyle(.segmented)
        LabeledContent("Accent") {
          AccentSwatches()
        }
      }

      Section {
        Toggle("Open at Login", isOn: Binding(get: { opensAtLogin }, set: setOpensAtLogin))
          .disabled(!LoginItem.isAvailable && overrides.opensAtLogin == nil)
        Toggle("Show Free Space in Menu Bar", isOn: $model.menuBarShowsFreeSpace)
      } footer: {
        if let loginProblem {
          Text(loginProblem).foregroundStyle(.secondary)
        } else if !LoginItem.isAvailable, overrides.opensAtLogin == nil {
          Text("Open at Login is available in the installed app.").foregroundStyle(.secondary)
        }
      }

      Section {
        Picker("Clean level", selection: $model.config.level) {
          ForEach(CleanLevel.allCases) { level in
            Text(level.title).tag(level)
          }
        }
        Toggle("Move Everything to the Trash First", isOn: $model.config.trashEverything)
      } footer: {
        Text("Otherwise, things that rebuild themselves are removed straight away.")
          .foregroundStyle(.secondary)
      }
    }
    .onAppear {
      opensAtLogin = overrides.opensAtLogin ?? LoginItem.isEnabled
    }
  }

  private func setOpensAtLogin(_ enabled: Bool) {
    do {
      try LoginItem.set(enabled)
      opensAtLogin = LoginItem.isEnabled
      loginProblem = LoginItem.needsApproval ? "Allow \(Brand.name) in System Settings › General › Login Items." : nil
    } catch {
      opensAtLogin = LoginItem.isEnabled
      loginProblem = "Couldn’t change this: \(error.localizedDescription)"
    }
  }
}
