import Foundation

/// What a model is told about the things a removal request may refer to. Installed apps
/// are only ever described here, and only when the person asked to remove something:
/// name, size, when it was last opened, where it came from, how it can be removed and
/// whether it is open. Findings by title, category, size and how they come back. Never
/// a path, never file contents.
extension MacDescription {
  public struct Candidates: Sendable {
    public var text: String
    /// The identifiers that fitted. Proposals of anything else are thrown out.
    public var ids: [String]
  }

  /// One line per candidate, most relevant first, as many as fit the budget.
  public static func removalCandidates(_ findings: [Finding], characterBudget: Int, now: Date = Date()) -> Candidates {
    var lines: [String] = []
    var ids: [String] = []
    var used = 0
    for finding in findings {
      let line = candidateLine(finding, now: now)
      guard used + line.count + 1 <= characterBudget else { break }
      used += line.count + 1
      lines.append(line)
      ids.append(finding.id)
    }
    let header = "CANDIDATES (id | kind | name | size | last opened or used | facts)"
    return Candidates(text: ([header] + (lines.isEmpty ? ["(nothing on this Mac matches)"] : lines)).joined(separator: "\n"), ids: ids)
  }

  /// "k3j2 | app | Adobe Photoshop 2025 | 6.1 GB | opened 6 weeks ago | downloaded | developer adobe | has its own uninstaller"
  static func candidateLine(_ finding: Finding, now: Date) -> String {
    var parts = [finding.id]
    let kinds = Set(finding.blockers.map(\.kind))
    if let app = finding.app {
      parts.append("app")
      parts.append(app.name)
      parts.append(Format.bytes(finding.bytes) + (app.dataBytes > 0 ? " (\(Format.bytes(app.dataBytes)) of it data)" : ""))
      parts.append(kinds.contains(.appRunning) ? "open now" : finding.lastUsed.map { "opened \(Format.age($0, now: now))" } ?? "never recorded as opened")
      parts.append(app.source == .other ? "downloaded" : "from \(app.source.title)")
      let vendors = RemovalRequest.vendors(of: finding)
      if !vendors.isEmpty { parts.append("developer \(vendors.sorted().joined(separator: "/"))") }
      if kinds.contains(.ownUninstaller) {
        parts.append("has its own uninstaller")
      } else if kinds.contains(.needsAdmin) {
        parts.append("needs Finder and the owner’s password")
      } else if kinds.contains(.reportOnly) {
        parts.append("can’t be removed by Glade")
      } else {
        parts.append("Glade can move it to the Trash")
      }
    } else {
      parts.append(finding.category.title)
      parts.append(finding.title)
      parts.append(Format.bytes(finding.bytes))
      parts.append(finding.lastUsed.map { "used \(Format.age($0, now: now))" } ?? "last use unknown")
      parts.append(finding.recovery.title.lowercased())
      if finding.risk == .personal { parts.append("personal") }
      if let owner = finding.owner?.name, owner != finding.title { parts.append("belongs to \(owner)") }
      let vendors = RemovalRequest.vendors(of: finding)
      if !vendors.isEmpty { parts.append("developer \(vendors.sorted().joined(separator: "/"))") }
      if let kind = finding.blockers.first?.kind { parts.append("blocked: \(blockerWords(kind))") }
    }
    return parts.joined(separator: " | ")
  }

  static func blockerWords(_ kind: Blocker.Kind) -> String {
    switch kind {
    case .appRunning: "its app is open"
    case .uncommittedWork: "holds unsaved work"
    case .needsAdmin: "needs the owner’s password"
    case .needsFullDiskAccess: "needs Full Disk Access"
    case .inUse: "in use"
    case .reportOnly: "can’t be removed by Glade"
    case .ownUninstaller: "has its own uninstaller"
    }
  }

  /// The same facts, shorter, for the second opinion, with the other apps still
  /// installed from the same developer (they may share its data).
  static func reviewLine(_ finding: Finding, scan: ScanResult, now: Date) -> String {
    var line = candidateLine(finding, now: now)
    let vendors = RemovalRequest.vendors(of: finding)
    if !vendors.isEmpty {
      let siblings = scan.findings.filter {
        $0.category == .installedApps && $0.id != finding.id && !RemovalRequest.vendors(of: $0).isDisjoint(with: vendors)
      }
      if !siblings.isEmpty {
        line += " | also installed from this developer: \(siblings.prefix(6).map(\.title).joined(separator: ", "))"
      }
    }
    return line
  }
}
