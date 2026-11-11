import Foundation

/// Finds stale session transcripts kept by coding agents: the conversations
/// themselves, which pile up fast. Memory, skills, settings and sign-in files are a
/// protected zone and are never seen here.
public struct AgentHistoryScanner: StorageScanner {
  public let id = "agent-history"
  public let title = "Agent sessions"

  /// A place where an agent keeps one folder (or file) per session, grouped somehow.
  struct Source: Sendable {
    var id: String
    var agent: String
    /// Folders whose children are sessions. `*` matches one path component.
    var groups: [String]
    var detail: String
    /// How to label a group folder.
    var label: @Sendable (String) -> String
  }

  static let sources: [Source] = [
    Source(
      id: "claude.sessions", agent: "Claude Code", groups: ["~/.claude/projects/*"],
      detail: "Conversation transcripts from Claude Code sessions in this folder. Removing them means those sessions can no longer be resumed; your memory and skills are untouched.",
      label: { claudeProjectName($0) }
    ),
    Source(
      id: "codex.sessions", agent: "Codex", groups: ["~/.codex/sessions/*/*", "~/.codex/archived_sessions"],
      detail: "Conversation transcripts from Codex sessions. Removing them means those sessions can no longer be resumed.",
      label: { path in
        let parts = path.components(separatedBy: "/")
        return parts.last == "archived_sessions" ? "archived" : parts.suffix(2).joined(separator: "-")
      }
    ),
    Source(
      id: "cursor.sessions", agent: "Cursor", groups: ["~/.cursor/chats", "~/.cursor/projects/*", "~/.cursor/ai-tracking"],
      detail: "Conversation history from Cursor’s agent. Removing it means those conversations can no longer be reopened.",
      label: { ($0 as NSString).lastPathComponent }
    ),
    Source(
      id: "opencode.sessions", agent: "OpenCode",
      groups: ["~/.local/share/opencode/storage/*", "~/.local/share/opencode/snapshot", "~/.local/share/opencode/log", "~/.local/share/opencode/tool-output"],
      detail: "Session data from OpenCode. Removing it means those sessions can no longer be resumed.",
      label: { ($0 as NSString).lastPathComponent }
    ),
    Source(
      id: "claude-desktop.sessions", agent: "Claude",
      groups: [
        "~/Library/Application Support/Claude/local-agent-mode-sessions/*/*",
        "~/Library/Application Support/Claude/claude-code-sessions/*/*",
      ],
      detail: "Working files from Claude desktop’s agent sessions. Removing them means those sessions can no longer be reopened.",
      label: { path in
        let parts = path.components(separatedBy: "/")
        let kind = parts.contains("claude-code-sessions") ? "code" : "agent mode"
        return "\(kind) \((path as NSString).lastPathComponent.prefix(8))"
      }
    ),
  ]

  public init() {}

  public func scan(_ context: ScanContext) async -> [Finding] {
    guard !context.config.ignoredCategories.contains(.agentHistory) else { return [] }
    var findings: [Finding] = []
    for source in Self.sources {
      for pattern in source.groups {
        for group in DiskWalk.expand(pattern, home: context.home) where context.protection.canScan(group) {
          if context.cancel.isCancelled { return findings }
          if let finding = await scan(group: group, source: source, context: context) {
            findings.append(finding)
          }
        }
      }
    }
    return findings
  }

  private func scan(group: String, source: Source, context: ScanContext) async -> Finding? {
    let staleDays = Catalog.staleAgentDays
    let children = DiskWalk.children(of: group).filter { context.protection.canScan($0) }
    guard !children.isEmpty else { return nil }
    let protection = context.protection
    let now = context.now

    // Sessions are many small files, so measure the whole group in one background pass.
    let result: (paths: [String], measure: Measure, kept: Int) = await context.background {
      var stale: [String] = []
      var total = Measure()
      var kept = 0
      for child in children {
        let measure = DiskWalk.measure([child], protection: protection)
        guard let last = measure.newestModification else { continue }
        if now.timeIntervalSince(last) >= Double(staleDays) * 86_400, !measure.containsStrict {
          stale.append(child)
          total = total + measure
        } else {
          kept += 1
        }
      }
      return (stale, total, kept)
    }
    guard result.measure.bytes >= 1_000_000 else { return nil }

    var evidence = ["\(result.paths.count) sessions untouched for \(staleDays) days or more."]
    if result.kept > 0 { evidence.append("\(result.kept) recent sessions are kept.") }
    if let last = result.measure.newestModification {
      evidence.append("Newest of these last changed \(Format.age(last, now: now)).")
    }
    return Finding(
      id: Finding.makeID(rule: source.id, path: group), ruleID: source.id, category: .agentHistory,
      title: "\(source.agent) sessions – \(source.label(group))", detail: source.detail,
      paths: result.paths, bytes: result.measure.bytes, fileCount: result.measure.files,
      lastUsed: result.measure.newestModification, recovery: .permanent, risk: .caution,
      method: .delete, evidence: evidence, autoLevel: .balanced, idleDaysRequired: 0
    )
  }

  /// Claude names project folders after the path with slashes turned into dashes
  /// (`-Users-name-Developer-App`). Show the part after the home folder.
  static func claudeProjectName(_ path: String) -> String {
    let name = (path as NSString).lastPathComponent
    let home = NSHomeDirectory().replacingOccurrences(of: "/", with: "-")
    if name == home { return "home folder" }
    if name.hasPrefix(home + "-") {
      return String(name.dropFirst(home.count + 1))
    }
    return name
  }
}
