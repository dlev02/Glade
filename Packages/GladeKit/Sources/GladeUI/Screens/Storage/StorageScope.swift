import GladeKit

/// Which findings the storage list shows: what a clean could take, everything the
/// scan found, or the things only a person should decide on.
enum StorageScope: String, CaseIterable, Identifiable {
  case ready, everything, review

  var id: String { rawValue }

  var title: String {
    switch self {
    case .ready: "Ready"
    case .everything: "Everything"
    case .review: "Review"
    }
  }

  func includes(_ finding: Finding) -> Bool {
    switch self {
    case .ready: !finding.isBlocked && finding.risk != .personal
    case .everything: true
    // Every app is the person’s to decide on, including ones removed another way.
    case .review: finding.category == .installedApps || (!finding.isBlocked && (finding.risk == .personal || finding.autoLevel == nil))
    }
  }
}
