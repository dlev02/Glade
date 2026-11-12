import Foundation
import GladeKit

/// What the whole-disk sheet can offer for one row, worked out by `AppModel`.
struct UsageRowActions: Equatable {
  /// The installed app at this path.
  var app: Finding?
  /// What the last scan lists in Storage at or inside this path, biggest first.
  var listed: Finding?
  /// Whether it may be moved to the Trash by hand, and why not. `nil` for apps and for
  /// rows that aren’t a place on the disk.
  var removal: PickedFolder.Assessment?
  /// Whose folder it is: "Used by Cursor", "No installed app uses this".
  var owner: String?
  /// An app in an Applications folder that the last scan didn’t list.
  var unscannedApp = false
}

extension AppModel {
  /// The installed apps, for saying whose a folder is. Sample data uses its own apps.
  func installedAppsIndex() async -> InstalledApps {
    if isDemo { return InstalledApps.index(from: scan?.findings ?? []) }
    let config = config
    return await InstalledApps.current(config: config)
  }

  /// What a row of the whole-disk sheet can do.
  func usageActions(for node: UsageNode, apps: InstalledApps?) -> UsageRowActions {
    guard let path = node.path.map(Protection.clean) else { return UsageRowActions() }
    let findings = scan?.findings ?? []
    var actions = UsageRowActions()
    if let app = findings.first(where: { $0.isApp && $0.paths.first == path }) {
      actions.app = app
      return actions
    }
    let protection = UsageProtection.current(config)
    let inApplications = protection.applicationFolders.contains { path.hasPrefix($0 + "/") }
    if inApplications, path.hasSuffix(".app") {
      actions.unscannedApp = true
      return actions
    }
    actions.listed = findings.first { !$0.isApp && $0.ruleID != PickedFolder.ruleID && $0.paths.contains(path) }
      ?? findings.filter { finding in
        !finding.isApp && finding.ruleID != PickedFolder.ruleID && finding.within == nil
          && finding.paths.contains { $0.hasPrefix(path + "/") }
      }.max { $0.bytes < $1.bytes }
    actions.removal = PickedFolder.assess(path, protection: protection)
    if let apps { actions.owner = FolderOwner.describe(path, home: protection.home, apps: apps) }
    return actions
  }

  /// Takes what a clean moved to the Trash out of the disk tree, so it doesn’t linger
  /// until the next measurement.
  func pruneUsage(after receipt: Receipt) {
    guard var current = usage else { return }
    var gone: [String] = []
    for entry in receipt.entries {
      if case .trashed(let locations) = entry.outcome { gone += locations.keys.map(Protection.clean) }
      if case .deleted = entry.outcome { gone += entry.paths.map(Protection.clean) }
    }
    guard !gone.isEmpty else { return }
    current.areas = current.areas.map { Self.prune($0, removing: Set(gone)) }
    usage = current
  }

  private static func prune(_ node: UsageNode, removing gone: Set<String>) -> UsageNode {
    var copy = node
    var removed: Int64 = 0
    copy.children = node.children.compactMap { child in
      if let path = child.path.map(Protection.clean), gone.contains(path) {
        removed += child.bytes
        return nil
      }
      let pruned = prune(child, removing: gone)
      removed += child.bytes - pruned.bytes
      return pruned
    }
    copy.bytes = max(0, node.bytes - removed)
    return copy
  }
}

/// One safety policy for the sheet’s rows, made again only when the settings change.
@MainActor
enum UsageProtection {
  private static var cached: (config: GladeConfig, protection: Protection)?

  static func current(_ config: GladeConfig) -> Protection {
    if let cached, cached.config == config { return cached.protection }
    let protection = Protection(config: config)
    cached = (config, protection)
    return protection
  }
}
