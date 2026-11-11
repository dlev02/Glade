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
        LabeledContent("Appearance") {
          AppearanceTiles(selection: $model.appearance)
        }
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
        LabeledContent("Clean level") {
          LevelMenu(offersReset: false)
            .tint(.secondary)
        }
        Toggle("Move everything to Trash", isOn: $model.config.trashEverything)
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
