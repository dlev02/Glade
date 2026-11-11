import SwiftUI

/// The assistant screens that can be drawn to an image with `glade snapshot <name>`.
/// Add an entry for each state worth checking: empty, busy, a sheet, an error.
enum AssistantSnapshots {
  static let all: [String: (AppModel) -> AnyView] = [
    "assistant": { _ in AnyView(NavigationStack { AssistantScreen() }) },
    "history": { _ in AnyView(NavigationStack { HistoryScreen() }) },
  ]
}
