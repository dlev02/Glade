import AppKit
import GladeKit

/// Asks for one or more folders with the standard open panel, attached to the front
/// window when there is one. Hands back paths written with `~` for the home folder.
enum FolderPicker {
  static func choose(prompt: String, completion: @escaping ([String]) -> Void) {
    let panel = NSOpenPanel()
    panel.canChooseDirectories = true
    panel.canChooseFiles = false
    panel.allowsMultipleSelection = true
    panel.canCreateDirectories = false
    panel.prompt = prompt
    let finish: (NSApplication.ModalResponse) -> Void = { response in
      guard response == .OK else { return }
      completion(panel.urls.map { Redactor.tilde($0.path) })
    }
    if let window = NSApp.keyWindow {
      panel.beginSheetModal(for: window, completionHandler: finish)
    } else {
      panel.begin(completionHandler: finish)
    }
  }
}
