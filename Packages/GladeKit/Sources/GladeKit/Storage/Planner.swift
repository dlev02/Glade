import Foundation

/// One finding's place in a plan.
public struct PlanItem: Codable, Sendable, Identifiable {
  public enum Source: String, Codable, Sendable {
    case rules, assistant, person
  }

  /// The finding's identifier.
  public var id: String
  public var selected: Bool
  /// Why it is or isn't selected, in one sentence.
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
  public static func plan(scan: ScanResult, level: CleanLevel, config: GladeConfig = ConfigStore.load(), now: Date = Date()) -> CleanPlan {
    var items: [PlanItem] = []
    for finding in scan.findings {
      let (selected, reason) = decide(finding, level: level, now: now)
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

  /// Recomputes a plan's totals after its selection changes.
  public static func total(_ plan: inout CleanPlan, scan: ScanResult, config: GladeConfig) {
    let selected = plan.selectedIDs.compactMap { scan.finding($0) }
    let paths = selected.flatMap { finding in finding.paths.map { ($0, finding.id) } }
    var bytes: Int64 = 0, immediate: Int64 = 0
    for finding in selected {
      // A folder inside another selected folder is already counted by its parent.
      let nested = finding.paths.allSatisfy { path in
        paths.contains { other, owner in owner != finding.id && path.hasPrefix(other + "/") }
      }
      if nested { continue }
      bytes += finding.bytes
      let trashed = finding.method == .trash || config.trashEverything || finding.risk == .personal
      if !trashed { immediate += finding.bytes }
    }
    plan.selectedBytes = bytes
    plan.immediateBytes = immediate
  }

  /// The hard limit on automatic selection. Neither a clean level nor an assistant
  /// may select a finding for which this returns false; only a person can.
  public static func mayAutoSelect(_ finding: Finding) -> Bool {
    finding.risk != .personal && !finding.isBlocked && finding.autoLevel != nil
  }

  public static func decide(_ finding: Finding, level: CleanLevel, now: Date = Date()) -> (Bool, String) {
    if let blocker = finding.blockers.first { return (false, blocker.detail) }
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
    switch finding.recovery {
    case .automatic: return (true, "Rebuilds itself when needed.")
    case .redownload: return (true, "Downloads again when needed.")
    case .reinstall: return (true, "Comes back with a reinstall or rebuild.")
    case .permanent: return (true, "Stale, and marked for clearing at this level.")
    }
  }

  /// Bolder levels wait less: half as long one level up, not at all two levels up.
  static func requiredIdleDays(_ finding: Finding, level: CleanLevel) -> Int {
    guard let autoLevel = finding.autoLevel else { return finding.idleDaysRequired }
    let order: [CleanLevel] = [.careful, .balanced, .aggressive]
    let gap = (order.firstIndex(of: level) ?? 0) - (order.firstIndex(of: autoLevel) ?? 0)
    switch gap {
    case ...0: return finding.idleDaysRequired
    case 1: return finding.idleDaysRequired / 2
    default: return 0
    }
  }
}
