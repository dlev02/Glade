import Foundation

/// One finding’s place in a plan.
public struct PlanItem: Codable, Sendable, Identifiable {
  public enum Source: String, Codable, Sendable {
    case rules, assistant, person
  }

  /// The finding’s identifier.
  public var id: String
  public var selected: Bool
  /// Why it is or isn’t selected, in one sentence.
  public var reason: String
  public var source: Source

  public init(id: String, selected: Bool, reason: String, source: Source = .rules) {
    self.id = id
    self.selected = selected
    self.reason = reason
    self.source = source
  }
}

/// A proposal for what to remove. Building one changes nothing.
public struct CleanPlan: Codable, Sendable, Identifiable {
  public var id: String
  public var created: Date
  public var level: CleanLevel
  public var items: [PlanItem]
  /// Space the selected items occupy, with nested folders counted once.
  public var selectedBytes: Int64
  /// How much of that is freed immediately (the rest goes to the Trash first).
  public var immediateBytes: Int64
  /// Personal items worth a look. Never selected; listed so a person can decide.
  public var review: [String]
  /// What the assistant said about the plan as a whole, when one was asked.
  public var summary: String?
  public var provider: String?

  public var selectedIDs: [String] { items.filter(\.selected).map(\.id) }
}

/// Decides what each clean level selects. Rules only; an assistant can adjust the
/// result afterwards but only within what `mayAutoSelect` allows.
public enum Planner {
  /// - Parameter includeRules: Apply the person’s always-clear rules. Only for plans a
  ///   person sees before anything is removed; never for unattended or agent cleans.
  public static func plan(
    scan: ScanResult, level: CleanLevel, config: GladeConfig = ConfigStore.load(), now: Date = Date(), includeRules: Bool = false
  ) -> CleanPlan {
    var items: [PlanItem] = []
    for finding in scan.findings {
      let (selected, reason) = decide(finding, level: level, now: now)
      // The person’s own standing rule ticks what they’d tick themselves.
      if includeRules, !selected, let rule = AlwaysClear.rule(for: finding, rules: config.alwaysClear) {
        items.append(PlanItem(id: finding.id, selected: true, reason: "You asked Glade to always clear \(rule).", source: .person))
        continue
      }
      items.append(PlanItem(id: finding.id, selected: selected, reason: reason))
    }
    var plan = CleanPlan(
      id: UUID().uuidString, created: now, level: level, items: items, selectedBytes: 0, immediateBytes: 0,
      review: scan.findings.filter { $0.risk == .personal && !$0.isBlocked }.prefix(25).map(\.id),
      summary: nil, provider: nil
    )
    total(&plan, scan: scan, config: config)
    return plan
  }

  /// Recomputes a plan’s totals after its selection changes.
  public static func total(_ plan: inout CleanPlan, scan: ScanResult, config: GladeConfig) {
    var bytes: Int64 = 0, immediate: Int64 = 0
    for finding in topLevel(plan.selectedIDs, in: scan) {
      bytes += finding.bytes
      // As the Cleaner decides: only files go to the Trash. Simulators, worktrees and
      // the Trash itself are removed by their own tools, so they free space at once.
      let trashed: Bool
      switch finding.method {
      case .delete, .trash: trashed = finding.method == .trash || config.trashEverything || finding.risk == .personal
      case .uninstallApp: trashed = true
      default: trashed = false
      }
      if !trashed { immediate += finding.bytes }
    }
    plan.selectedBytes = bytes
    plan.immediateBytes = immediate
  }

  /// The findings a clean of these identifiers works through, each once: a finding
  /// inside another chosen one goes with it, so it is neither counted nor removed on
  /// its own. Every total and every count of items uses this one rule.
  public static func topLevel(_ ids: [String], in scan: ScanResult) -> [Finding] {
    // Looked up by identifier once, rather than searching the scan for each one.
    let byID = Dictionary(scan.findings.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    let chosen = ids.compactMap { byID[$0] }
    let roots = chosen.flatMap { finding in finding.paths.map { ($0 + "/", finding.id) } }
    // An app takes its data folders with it, so one of them chosen as well (its cache)
    // goes with the app rather than on its own.
    let appFolders = chosen.filter { $0.category == .installedApps }.flatMap { app in app.paths.dropFirst().map { ($0, app.id) } }
    return chosen.filter { finding in
      let nested = !finding.paths.isEmpty && finding.paths.allSatisfy { path in
        roots.contains { root, owner in owner != finding.id && path.hasPrefix(root) }
          || appFolders.contains { folder, owner in owner != finding.id && path == folder }
      }
      return !nested
    }
  }

  /// The hard limit on automatic selection. Neither a clean level nor an assistant
  /// may select a finding for which this returns false; only a person can.
  public static func mayAutoSelect(_ finding: Finding) -> Bool {
    finding.risk != .personal && !finding.isBlocked && finding.autoLevel != nil
  }

  public static func decide(_ finding: Finding, level: CleanLevel, now: Date = Date()) -> (Bool, String) {
    if let blocker = finding.blockers.first { return (false, blocker.detail) }
    if finding.category == .installedApps { return (false, "Apps are only removed when you choose one.") }
    if finding.risk == .personal { return (false, "Yours to decide. Glade never selects personal files.") }
    guard let autoLevel = finding.autoLevel else { return (false, "Can’t be recreated, so it’s left for you to choose.") }
    guard autoLevel <= level else { return (false, "Included from \(autoLevel.title) up.") }

    let required = requiredIdleDays(finding, level: level)
    if required > 0 {
      guard let idle = finding.idleDays(asOf: now) else { return (false, "Not sure when it was last used.") }
      guard idle >= required else {
        return (false, idle == 0 ? "Used today." : "Used \(idle) days ago; \(level.title) waits \(required).")
      }
    }
    if let newer = finding.newerVersion { return (true, "Version \(newer) has taken its place.") }
    switch finding.recovery {
    case .automatic: return (true, "Rebuilds itself when needed.")
    case .redownload: return (true, "Downloads again when needed.")
    case .reinstall: return (true, "Comes back with a reinstall or rebuild.")
    case .permanent: return (true, "Stale, and marked for clearing at this level.")
    }
  }

  /// A bolder level is worth mentioning when it frees at least this much more, and at
  /// least twice as much in all.
  static let hintMinimumBytes: Int64 = 5_000_000_000

  /// One or two plain sentences for when this plan frees little and a bolder level
  /// would free a lot more: what this level frees, what the gentlest such level would,
  /// and the biggest kinds of thing it adds. `nil` when no bolder level would add much.
  /// Shown by `glade plan`, by `glade doctor` when space is low, and meant for the
  /// low-storage alert.
  public static func bolderLevelHint(
    scan: ScanResult, plan: CleanPlan, config: GladeConfig = ConfigStore.load(), now: Date = Date()
  ) -> String? {
    let order: [CleanLevel] = [.careful, .balanced, .aggressive]
    guard let index = order.firstIndex(of: plan.level) else { return nil }
    let chosen = Set(plan.selectedIDs)
    for bolder in order.dropFirst(index + 1) {
      let other = Self.plan(scan: scan, level: bolder, config: config, now: now)
      guard other.selectedBytes - plan.selectedBytes >= hintMinimumBytes,
            other.selectedBytes >= 2 * plan.selectedBytes else { continue }
      let added = topLevel(other.selectedIDs, in: scan).filter { !chosen.contains($0.id) }
      var byCategory: [StorageCategory: Int64] = [:]
      for finding in added { byCategory[finding.category, default: 0] += finding.bytes }
      let biggest = byCategory.sorted { $0.value > $1.value }.prefix(2)
        .map { "\(Self.prose($0.key)) (\(Format.bytes($0.value)))" }
      var text = "\(plan.level.title) frees \(Format.bytes(plan.selectedBytes)). \(bolder.title) would free \(Format.bytes(other.selectedBytes))"
      if !biggest.isEmpty { text += ", including \(biggest.joined(separator: " and "))" }
      return text + "."
    }
    return nil
  }

  /// A category’s name for the middle of a sentence: "Xcode build data", "AI models".
  static func prose(_ category: StorageCategory) -> String {
    category.title.split(separator: " ").map { word in
      word != "Xcode" && word.dropFirst().allSatisfy(\.isLowercase) ? word.lowercased() : String(word)
    }.joined(separator: " ")
  }

  /// How long an older version waits once a newer one beside it is the one in use:
  /// long enough that two projects taking turns on different versions keep both.
  static let supersededIdleDays = 3

  /// Bolder levels wait less: half as long one level up, not at all two levels up.
  /// An older version a newer one has taken the place of waits a few days at most.
  static func requiredIdleDays(_ finding: Finding, level: CleanLevel) -> Int {
    let base = finding.newerVersion == nil ? finding.idleDaysRequired : min(finding.idleDaysRequired, supersededIdleDays)
    guard let autoLevel = finding.autoLevel else { return base }
    let order: [CleanLevel] = [.careful, .balanced, .aggressive]
    let gap = (order.firstIndex(of: level) ?? 0) - (order.firstIndex(of: autoLevel) ?? 0)
    switch gap {
    case ...0: return base
    case 1: return base / 2
    default: return 0
    }
  }
}
