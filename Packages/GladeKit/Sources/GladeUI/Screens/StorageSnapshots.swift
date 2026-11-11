import SwiftUI

/// The storage screens that can be drawn to an image with `glade snapshot <name>`.
/// Add an entry for each state worth checking: empty, busy, a sheet, an error.
enum StorageSnapshots {
  static let all: [String: (AppModel) -> AnyView] = [
    "storage": { _ in AnyView(NavigationStack { StorageScreen() }) },
  ]
}
