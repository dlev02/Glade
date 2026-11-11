import GladeKit
import SwiftUI

/// Whether Glade learns what files contain, so they can be found by what’s in them,
/// and which folders it reads.
struct SearchPane: View {
  @Environment(AppModel.self) private var model

  var body: some View {
    @Bindable var model = model
    Form {
      Section {
        Toggle("Search file contents", isOn: $model.config.index.enabled)
      }

      Section("Folders") {
        FolderRows(paths: $model.config.index.folders, prompt: "Add")
      }
      .disabled(!model.config.index.enabled)

      Section {
        Toggle("Read text in images", isOn: $model.config.index.readTextInImages)
          .disabled(!model.config.index.enabled)
      } footer: {
        Text("Everything stays on this Mac.")
          .foregroundStyle(.secondary)
      }
    }
  }
}
