import GladeKit

/// Words and symbols for showing a finding to a person.
extension Finding {
  /// Where it is: the path with the home folder as `~`, "3 locations", or nothing.
  var locationText: String? {
    switch paths.count {
    case 0: nil
    case 1: Redactor.tilde(paths[0])
    default: "\(paths.count) locations"
    }
  }

  /// "Used 3 days ago", or nothing when the scan couldn’t tell.
  var lastUsedText: String? {
    lastUsed.map { "Used \(Format.age($0))" }
  }

  /// Whether a clean sends it to the Trash rather than removing it straight away.
  func goesToTrash(_ config: GladeConfig) -> Bool {
    switch method {
    case .delete, .trash: method == .trash || config.trashEverything || risk == .personal
    case .uninstallApp: true
    default: false
    }
  }

  /// How a clean removes it, in plain words.
  func removalText(_ config: GladeConfig) -> String {
    switch method {
    case .simulatorDevice, .simulatorErase, .unavailableSimulators, .simulatorSet, .simulatorRuntime:
      "Handled by Xcode’s own tool"
    case .gitWorktree:
      "Removed by git; its branch and commits stay"
    case .emptyTrash:
      "Emptied from the Trash for good"
    case .uninstallApp:
      "The app and its data go to the Trash; you can put them back"
    case .delete, .trash:
      goesToTrash(config) ? "Moved to the Trash; you can put it back" : "Removed straight away"
    }
  }

  func removalSymbol(_ config: GladeConfig) -> String {
    switch method {
    case .simulatorDevice, .simulatorErase, .unavailableSimulators, .simulatorSet, .simulatorRuntime: "hammer"
    case .gitWorktree: "arrow.trianglehead.branch"
    case .emptyTrash: "trash.slash"
    case .uninstallApp: "trash"
    case .delete, .trash: goesToTrash(config) ? "trash" : "bolt"
    }
  }
}
