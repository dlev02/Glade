import AppKit
import Foundation

/// A known place where removable data collects, and how safe it is to remove.
public struct LocationRule: Sendable {
  public enum Split: Sendable {
    /// One finding covering every match.
    case whole
    /// One finding per match.
    case each
  }

  public enum TitleStyle: Sendable {
    case fixed
    /// "Title – child name"
    case child
    /// Xcode's `Project-hash` folder names, shown as the project.
    case derivedData
    /// The match is named after a bundle identifier; show the app's name.
    case bundleID
    /// The match sits inside `~/Library/Containers/<bundle id>`; show that app's name.
    case container
    /// Hugging Face's `models--org--name` folders, shown as `org/name`.
    case huggingFace
  }

  /// When a clean level may select the finding by itself.
  public enum Auto: Sendable {
    /// Worked out from how it's recovered and how risky it is.
    case derived
    case never
    case at(CleanLevel)
  }

  public var id: String
  public var category: StorageCategory
  public var title: String
  public var detail: String
  /// `~` is home, `$TMP` and `$CACHE` are the per-user temporary and cache folders,
  /// and `*` matches within one path component.
  public var paths: [String]
  public var split: Split = .whole
  public var titleStyle: TitleStyle = .fixed
  public var recovery: Recovery = .automatic
  public var risk: Risk = .safe
  public var owner: Owner?
  /// Don't offer this while the owning app is open.
  public var blockWhileRunning = false
  public var method: RemovalMethod = .delete
  public var contentsOnly = false
  /// Only count matches untouched for at least this many days.
  public var olderThanDays: Int?
  public var auto: Auto = .derived
  public var idleDays = 0
  /// Match names (shell patterns) to leave alone.
  public var skip: [String] = []
  /// Leave out matches whose path contains any of these.
  public var skipContaining: [String] = []
  public var minimumBytes: Int64 = 5_000_000
  /// Show it but never remove it; `reportOnly` explains what to use instead.
  public var reportOnly: String?
}

extension LocationRule {
  /// The level and idle time a finding of this kind gets when the rule doesn't say.
  static func automation(recovery: Recovery, risk: Risk, auto: Auto, idleDays: Int) -> (CleanLevel?, Int) {
    if risk == .personal { return (nil, idleDays) }
    switch auto {
    case .never: return (nil, idleDays)
    case .at(let level): return (level, idleDays)
    case .derived:
      switch (risk, recovery) {
      case (.safe, .automatic): return (.careful, idleDays)
      case (.safe, .redownload), (.safe, .reinstall): return (.balanced, idleDays)
      case (.caution, .permanent), (.safe, .permanent): return (nil, idleDays)
      case (.caution, _): return (.balanced, max(idleDays, 30))
      default: return (nil, idleDays)
      }
    }
  }
}

/// Finds everything listed in the catalog of known locations.
public struct CatalogScanner: StorageScanner {
  public let id = "catalog"
  public let title = "Known locations"
  let rules: [LocationRule]

  public init(rules: [LocationRule] = Catalog.rules) {
    self.rules = rules
  }

  public func scan(_ context: ScanContext) async -> [Finding] {
    await withTaskGroup(of: [Finding].self) { group in
      for rule in rules where !context.config.ignoredCategories.contains(rule.category) {
        group.addTask { await scan(rule, context) }
      }
      var all: [Finding] = []
      for await findings in group { all += findings }
      return all
    }
  }

  private func scan(_ rule: LocationRule, _ context: ScanContext) async -> [Finding] {
    if context.cancel.isCancelled { return [] }
    let matches = Self.expand(rule, context)
    guard !matches.isEmpty else { return [] }

    switch rule.split {
    case .whole:
      if let days = rule.olderThanDays {
        // Measure each match, keep the stale ones, report them together.
        let measured = await measureEach(matches, context)
        let stale = measured.filter { (context.days(since: $0.1.lastUsed) ?? 0) >= days && !$0.1.containsStrict }
        guard !stale.isEmpty else { return [] }
        let total = stale.map(\.1).reduce(Measure(), +)
        return make(rule, paths: stale.map(\.0), measure: total, name: nil, context: context).map { [$0] } ?? []
      }
      let measure = await context.measure(matches)
      return make(rule, paths: matches, measure: measure, name: nil, context: context).map { [$0] } ?? []
    case .each:
      let measured = await measureEach(matches, context)
      return measured.compactMap { path, measure in
        if let days = rule.olderThanDays, (context.days(since: measure.lastUsed) ?? 0) < days { return nil }
        return make(rule, paths: [path], measure: measure, name: (path as NSString).lastPathComponent, context: context)
      }
    }
  }

  private func measureEach(_ paths: [String], _ context: ScanContext) async -> [(String, Measure)] {
    await withTaskGroup(of: (String, Measure).self) { group in
      for path in paths {
        group.addTask { (path, await context.measure([path])) }
      }
      var results: [(String, Measure)] = []
      for await result in group { results.append(result) }
      return results.sorted { $0.0 < $1.0 }
    }
  }

  static func expand(_ rule: LocationRule, _ context: ScanContext) -> [String] {
    var matches: [String] = []
    for pattern in rule.paths {
      var resolved = pattern
      if pattern.hasPrefix("$TMP") || pattern.hasPrefix("$CACHE") {
        let roots = context.protection.scopes.dropFirst()
        let wanted = pattern.hasPrefix("$TMP") ? "/T" : "/C"
        guard let root = roots.first(where: { $0.hasSuffix(wanted) }) else { continue }
        resolved = root + pattern.drop { $0 != "/" }
      }
      for path in DiskWalk.expand(resolved, home: context.home) {
        let name = (path as NSString).lastPathComponent
        if rule.skip.contains(where: { fnmatch($0, name, FNM_CASEFOLD) == 0 }) { continue }
        if rule.skipContaining.contains(where: { path.contains($0) }) { continue }
        guard context.protection.canScan(path) else { continue }
        matches.append(path)
      }
    }
    return matches
  }

  private func make(_ rule: LocationRule, paths: [String], measure: Measure, name: String?, context: ScanContext) -> Finding? {
    guard measure.bytes >= rule.minimumBytes, !measure.cancelled else { return nil }
    var owner = rule.owner
    var title = rule.title
    if let name {
      switch rule.titleStyle {
      case .container:
        let parts = paths[0].components(separatedBy: "/")
        if let index = parts.firstIndex(of: "Containers"), index + 1 < parts.count {
          let bundleID = parts[index + 1]
          let appName = AppNames.name(forBundleID: bundleID)
          title = "\(appName ?? bundleID) \(rule.title)"
          owner = Owner(appName ?? bundleID, bundleIDs: [bundleID])
        }
      case .fixed: break
      case .child: title = "\(rule.title) – \(name)"
      case .derivedData:
        title = "\(rule.title) – \(Self.stripHash(name))"
      case .bundleID:
        let appName = AppNames.name(forBundleID: name)
        title = "\(appName ?? name) \(rule.title)"
        owner = Owner(appName ?? name, bundleIDs: [name])
      case .huggingFace:
        let parts = name.components(separatedBy: "--")
        title = parts.count >= 3 ? "\(parts[1...].joined(separator: "/"))" : name
      }
    }

    var blockers: [Blocker] = []
    var evidence: [String] = []
    if let reportOnly = rule.reportOnly {
      blockers.append(Blocker(.reportOnly, reportOnly))
    }
    if measure.containsStrict {
      blockers.append(Blocker(.inUse, "Contains a library or backup that must stay whole."))
    }
    if rule.blockWhileRunning, let owner, let running = context.running.runningName(of: owner) {
      blockers.append(Blocker(.appRunning, "\(running) is open."))
    }
    for path in paths {
      let verdict = context.protection.verdict(forRemoving: path)
      if case .outOfScope = verdict {
        if rule.reportOnly == nil { blockers.append(Blocker(.needsAdmin, "Outside your home folder; needs an administrator.")) }
        break
      } else if !verdict.isAllowed, rule.reportOnly == nil, !rule.contentsOnly {
        blockers.append(Blocker(.inUse, verdict.explanation))
        break
      }
    }
    if measure.unreadable > 0 {
      evidence.append("\(measure.unreadable) items couldn’t be read, so the real size may be larger.")
    }
    if let days = context.days(since: measure.lastUsed) {
      evidence.append(days == 0 ? "Used today." : "Last touched \(Format.age(measure.lastUsed, now: context.now)).")
    }

    let (level, idle) = LocationRule.automation(recovery: rule.recovery, risk: rule.risk, auto: rule.auto, idleDays: rule.idleDays)
    return Finding(
      id: Finding.makeID(rule: rule.id, path: paths.count == 1 ? paths[0] : rule.id),
      ruleID: rule.id, category: rule.category, title: title, detail: rule.detail,
      paths: paths, contentsOnly: rule.contentsOnly, bytes: measure.bytes, fileCount: measure.files,
      lastUsed: measure.lastUsed, recovery: rule.recovery, risk: rule.risk, owner: owner,
      blockers: blockers, method: rule.method, evidence: evidence,
      autoLevel: blockers.contains { $0.kind == .reportOnly } ? nil : level, idleDaysRequired: idle
    )
  }

  static func stripHash(_ name: String) -> String {
    guard let dash = name.lastIndex(of: "-") else { return name }
    let suffix = name[name.index(after: dash)...]
    return suffix.count >= 20 && suffix.allSatisfy({ $0.isLowercase && $0.isLetter }) ? String(name[..<dash]) : name
  }
}

/// Looks up app names from bundle identifiers, remembering the answers.
public enum AppNames {
  private static let cache = NameCache()

  public static func name(forBundleID id: String) -> String? {
    if let known = cache.get(id) { return known.isEmpty ? nil : known }
    var result = ""
    if id.contains("."), let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) {
      result = url.deletingPathExtension().lastPathComponent
    }
    cache.set(id, result)
    return result.isEmpty ? nil : result
  }

  private final class NameCache: @unchecked Sendable {
    private let lock = NSLock()
    private var names: [String: String] = [:]
    func get(_ key: String) -> String? { lock.withLock { names[key] } }
    func set(_ key: String, _ value: String) { lock.withLock { names[key] = value } }
  }
}
