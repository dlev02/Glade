import GladeKit

/// The findings of one category, in the order the list shows them, with the
/// figures its header needs worked out once.
struct FindingGroup: Identifiable, Hashable {
  var category: StorageCategory
  var entries: [FindingEntry]
  /// Space the group takes, with findings inside other findings counted once.
  var totalBytes: Int64
  /// Findings a person may tick; blocked ones are left out.
  var selectableIDs: [String]

  var id: StorageCategory { category }

  init(category: StorageCategory, entries: [FindingEntry]) {
    self.category = category
    self.entries = entries
    let ids = Set(entries.map(\.id))
    totalBytes = entries.reduce(0) { sum, entry in
      // A nested finding is already inside its container’s figure.
      if let container = entry.finding.within, ids.contains(container) { return sum }
      return sum + entry.finding.bytes
    }
    selectableIDs = entries.filter { !$0.finding.isBlocked }.map(\.id)
  }
}
