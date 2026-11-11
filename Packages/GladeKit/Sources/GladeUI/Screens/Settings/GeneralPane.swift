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
        // Outside an Applications folder macOS won't register a login item; the
        // tooltip says so.
        Toggle("Open at login", isOn: Binding(get: { opensAtLogin }, set: setOpensAtLogin))
          .disabled(!LoginItem.isAvailable && overrides.opensAtLogin == nil)
          .help(!LoginItem.isAvailable && overrides.opensAtLogin == nil ? "Available in the installed app" : "")
        Toggle("Show free space in the menu bar", isOn: $model.menuBarShowsFreeSpace)
      } footer: {
        if let loginProblem {
          Text(loginProblem).foregroundStyle(.secondary)
        }
      }

      Section {
        LabeledContent("Clean level") {
          LevelMenu(offersReset: false)
            .tint(.secondary)
        }
        Toggle("Use the Trash where possible", isOn: $model.config.trashEverything)
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
