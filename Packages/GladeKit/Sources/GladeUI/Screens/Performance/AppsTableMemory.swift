import SwiftUI

/// What the apps table showed when the person last left Performance: its rows, order
/// and filter. Coming back draws them on the first frame instead of starting empty
/// and rebuilding, so switching sections feels instant.
@MainActor
enum AppsTableMemory {
  static var rows: [UsageRow] = []
  static var filter: AppFilter = .apps
  static var sortOrder = [KeyPathComparator(\UsageRow.memory, order: .reverse)]
  static var columns = OptionalColumns()
}
