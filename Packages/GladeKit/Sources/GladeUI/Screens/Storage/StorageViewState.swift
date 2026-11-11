import Foundation
import GladeKit
import Observation

/// What the storage screen is showing: its rows, scope, search, highlighted rows,
/// folded groups and whether the inspector is open. The window keeps one of these
/// for as long as it's open, so going back to Storage shows the same list straight
/// away instead of building it again.
@Observable
final class StorageViewState {
  private static let inspectorKey = "storageShowsInspector"

  let list = StorageListModel()
  var scope: StorageScope
  var query = ""
  var highlighted: Set<String>
  var collapsed: Set<StorageCategory> = []
  var showsInspector: Bool {
    didSet { UserDefaults.standard.set(showsInspector, forKey: Self.inspectorKey) }
  }

  /// - Parameter showsInspector: `nil` uses the person's last choice, which starts
  ///   out closed.
  init(scope: StorageScope = .ready, highlighted: String? = nil, showsInspector: Bool? = nil) {
    self.scope = scope
    self.highlighted = highlighted.map { [$0] } ?? []
    // `bool(forKey:)` also reads a launch argument ("-storageShowsInspector YES").
    let defaults = UserDefaults.standard
    let saved: Bool? = defaults.object(forKey: Self.inspectorKey) == nil ? nil : defaults.bool(forKey: Self.inspectorKey)
    self.showsInspector = showsInspector ?? saved ?? false
  }

  /// Brings the rows up to date with the scan, and drops highlights on rows that
  /// are no longer showing. Does nothing when nothing it depends on changed.
  func refresh(scan: ScanResult?) {
    list.update(scan: scan, scope: scope, query: query)
    let visible = Set(list.groups.flatMap { $0.entries.map(\.id) })
    if !highlighted.isSubset(of: visible) { highlighted.formIntersection(visible) }
  }

  /// The one highlighted finding, when exactly one row is highlighted.
  var highlightedFinding: Finding? {
    guard highlighted.count == 1, let id = highlighted.first else { return nil }
    return list.finding(id)
  }
}
