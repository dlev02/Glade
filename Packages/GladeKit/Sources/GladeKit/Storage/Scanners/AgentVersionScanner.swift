import Foundation

/// Old releases of command-line agents that update themselves and keep every version
/// they have downloaded. The version the command runs, anything newer (an update
/// waiting to switch over) and the one before it are always kept.
///
/// When the command’s link can’t be followed into the versions folder, nothing is
/// reported: without knowing which version is live, none is safe to remove.
public struct AgentVersionScanner: StorageScanner {
  public let id = "agent-versions"
  public let title = "Old agent versions"

  static let minimumBytes: Int64 = 20_000_000

  struct Tool: Sendable {
    var name: String
    /// The folder holding one entry per version, relative to home.
    var versions: String
    /// The command on the PATH that links into it, relative to home.
    var command: String
  }

  static let tools: [Tool] = [
    Tool(name: "Claude Code", versions: ".local/share/claude/versions", command: ".local/bin/claude"),
    Tool(name: "Cursor Agent", versions: ".local/share/cursor-agent/versions", command: ".local/bin/cursor-agent"),
  ]

  public init() {}

  public func scan(_ context: ScanContext) async -> [Finding] {
    guard !context.config.ignoredCategories.contains(.sdks) else { return [] }
    var findings: [Finding] = []
    for tool in Self.tools {
      if context.cancel.isCancelled { break }
      let root = context.home + "/" + tool.versions
      guard FileFacts.isDirectory(root), context.protection.canScan(root) else { continue }
      guard let plan = Self.plan(root: root, command: context.home + "/" + tool.command) else {
        Log.debug(.scan, "Kept every \(tool.name) version: couldn’t tell which one is in use")
        continue
      }
      let stale = plan.remove.filter { context.protection.verdict(forRemoving: $0).isAllowed }
      guard !stale.isEmpty else { continue }
      let measure = await context.measure(stale)
      guard !measure.cancelled, measure.bytes >= Self.minimumBytes else { continue }
      findings.append(make(tool, root: root, plan: plan, stale: stale, measure: measure, context: context))
    }
    return findings
  }

  struct Plan: Equatable {
    var active: String
    var keep: [String]
    var remove: [String]
  }

  /// Which versions stay and which can go, judged from names, link targets and dates.
  static func plan(root: String, command: String) -> Plan? {
    var info = stat()
    guard lstat(command, &info) == 0, (info.st_mode & S_IFMT) == S_IFLNK else { return nil }
    let target = URL(fileURLWithPath: command).resolvingSymlinksInPath().path
    let cleanRoot = Protection.clean(URL(fileURLWithPath: root).resolvingSymlinksInPath().path)
    let cleanTarget = Protection.clean(target)
    guard cleanTarget.hasPrefix(cleanRoot + "/") else { return nil }
    guard let activeName = cleanTarget.dropFirst(cleanRoot.count + 1).split(separator: "/").first.map(String.init) else { return nil }

    var entries: [(path: String, modified: Date)] = []
    for path in DiskWalk.children(of: root) {
      let name = (path as NSString).lastPathComponent
      guard !name.hasPrefix(".") else { continue }
      var entry = stat()
      // Links and anything that isn’t a plain file or folder are left alone.
      guard lstat(path, &entry) == 0 else { continue }
      let kind = entry.st_mode & S_IFMT
      guard kind == S_IFREG || kind == S_IFDIR else { continue }
      entries.append((path, Date(timeIntervalSince1970: TimeInterval(entry.st_mtimespec.tv_sec))))
    }
    guard let active = entries.first(where: { ($0.path as NSString).lastPathComponent == activeName }) else { return nil }

    var keep = [active.path]
    // A newer entry is an update downloaded ahead of switching over.
    keep += entries.filter { $0.path != active.path && $0.modified >= active.modified }.map(\.path)
    // The newest older one, to go back to.
    if let previous = entries.filter({ $0.modified < active.modified }).max(by: { $0.modified < $1.modified }) {
      keep.append(previous.path)
    }
    let remove = entries.map(\.path).filter { !keep.contains($0) }.sorted()
    return Plan(active: active.path, keep: keep, remove: remove)
  }

  private func make(_ tool: Tool, root: String, plan: Plan, stale: [String], measure: Measure, context: ScanContext) -> Finding {
    let name = { (path: String) in (path as NSString).lastPathComponent }
    let others = plan.keep.filter { $0 != plan.active }.map(name)
    var evidence = [
      "`\((tool.command as NSString).lastPathComponent)` runs \(name(plan.active))"
        + (others.isEmpty ? ", which stays." : "; it and \(others.joined(separator: ", ")) stay."),
      stale.count == 1 ? "1 older version: \(name(stale[0]))." : "\(stale.count) older versions: \(stale.map(name).joined(separator: ", ")).",
    ]
    if measure.unreadable > 0 {
      evidence.append("\(measure.unreadable) items couldn’t be read, so the real size may be larger.")
    }
    var blockers: [Blocker] = []
    if let program = stale.lazy.compactMap({ InUse.runningExecutable(inside: $0, executables: context.running.executablePaths) }).first {
      blockers.append(Blocker(.inUse, "An older \(tool.name) (\(program)) is still running."))
    }
    let (level, idle) = LocationRule.automation(recovery: .redownload, risk: .safe, auto: .derived, idleDays: 0)
    return Finding(
      id: Finding.makeID(rule: "agent.old-versions", path: root),
      ruleID: "agent.old-versions", category: .sdks, title: "Old \(tool.name) versions",
      detail: "Earlier releases \(tool.name) kept after updating itself. The version you use and the one before it stay; an older one can be installed again if you ever need it.",
      paths: stale, bytes: measure.bytes, fileCount: measure.files, lastUsed: measure.lastUsed,
      recovery: .redownload, risk: .safe, blockers: blockers, method: .delete, evidence: evidence,
      autoLevel: level, idleDaysRequired: idle
    )
  }
}
