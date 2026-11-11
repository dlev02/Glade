import GladeKit

/// Which of the table's sometimes-empty columns are showing. A column appears as soon
/// as any row has a value in it, and goes only after several refreshes without one, so
/// it doesn't flicker as readings come and go.
struct OptionalColumns: Equatable {
  var graphics = false
  var lastUsed = false
  private var emptyGraphics = 0
  private var emptyLastUsed = 0

  /// Refreshes in a row with nothing in a column before it hides.
  private static let patience = 5

  static var memory: OptionalColumns { AppsTableMemory.columns }

  mutating func update(_ rows: [UsageRow]) {
    // A share that shows as "0%" counts as nothing.
    let hasGraphics = rows.contains { $0.graphics >= 0.05 }
    let hasLastUsed = rows.contains { !$0.app.isFrontmost && $0.app.lastActive != nil }
    (graphics, emptyGraphics) = Self.step(showing: graphics, has: hasGraphics, empty: emptyGraphics)
    (lastUsed, emptyLastUsed) = Self.step(showing: lastUsed, has: hasLastUsed, empty: emptyLastUsed)
  }

  private static func step(showing: Bool, has: Bool, empty: Int) -> (Bool, Int) {
    if has { return (true, 0) }
    guard showing else { return (false, 0) }
    return empty + 1 >= patience ? (false, 0) : (true, empty + 1)
  }
}
