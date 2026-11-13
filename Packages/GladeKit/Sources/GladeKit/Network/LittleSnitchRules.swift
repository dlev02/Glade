import AppKit
import Foundation

/// One Little Snitch rule, reduced to the fields Glade reads: who, where, which way,
/// allowed or not, and when it last mattered. Paths have the home folder shortened to `~`.
public struct LittleSnitchRule: Codable, Sendable, Identifiable, Equatable {
  /// Stable within one import: `r1`, `r2`…
  public var id: String
  /// `allow`, `deny`, `ask`, or `suggestion` (one Little Snitch offers but hasn’t applied).
  public var action: String
  /// `any`, a path, or a code identity such as `identifier.TEAMID/com.apple.Safari`.
  public var process: String
  /// The app it’s for, such as “Safari”.
  public var app: String?
  public var via: String?
  /// `any`, `local-net`… or the hosts, domains or addresses it names.
  public var remote: String
  public var remoteKind: String
  public var direction: String
  public var ports: String?
  public var proto: String?
  public var disabled: Bool
  /// The rule group it came from, for rules a subscription or macOS manages.
  public var group: String?
  public var notes: String?
  /// How Little Snitch made it: `alert` (you answered a prompt), `factory`, `osUpdate`…
  public var origin: String?
  public var lastUsed: Date?
  public var uses: Int?
  /// The executable it was last seen at is no longer on this Mac.
  public var gone: Bool?
  /// The user account it applies to, when it’s for one account only.
  public var uid: Int?

  /// Belongs to a group (a subscription, macOS’s or iCloud’s services), so it’s changed
  /// as a group rather than one by one.
  public var managed: Bool { group != nil }

  /// Little Snitch’s or macOS’s own rather than one the person made.
  public var builtIn: Bool { ["factory", "osUpdate", "monitor", "preLogin"].contains(origin ?? "") }

  /// “Allow Safari connecting to any server”.
  public var sentence: String {
    let who = process == "any" ? "any process" : (app ?? (process as NSString).lastPathComponent)
    let verb = action == "deny" ? "Deny" : action == "allow" ? "Allow" : action == "suggestion" ? "Suggested: allow" : "Ask before"
    let target = remoteKind == "any" ? "any server" : remote
    let way = direction == "incoming" ? "incoming connections from" : "connecting to"
    return "\(verb) \(who) \(way) \(target)\(ports.map { $0 == "any" ? "" : " on port \($0)" } ?? "")\(disabled && action != "suggestion" ? " (off)" : "")"
  }
}

/// A Little Snitch export the person chose: a backup (File › Create Backup) or a rule
/// group exported as `.lsrules`. Read only from a file the person picks; Glade never
/// talks to Little Snitch itself, which needs root and its Terminal access setting.
public struct LittleSnitchRules: Codable, Sendable, Equatable {
  public struct Group: Codable, Sendable, Equatable {
    public var name: String
    public var enabled: Bool?
    public var rules: Int
    /// Kept up to date from a web address.
    public var subscribed: Bool
  }

  /// What Glade notices without asking an AI.
  public struct Finding: Codable, Sendable, Equatable, Identifiable {
    public enum Kind: String, Codable, Sendable {
      /// The app it’s for isn’t on this Mac any more.
      case unusedApp
      /// The same rule twice.
      case duplicate
      /// Allow and deny for the same app and destination.
      case conflict
      /// Any process may reach any server.
      case allowsEverything
      /// One app may reach any server.
      case broadAllow
      /// Not used in over a year.
      case stale
    }

    public var id: String { kind.rawValue + ruleIDs.prefix(3).joined(separator: ",") }
    public var kind: Kind
    public var ruleIDs: [String]
    public var sentence: String
  }

  public var imported: Date
  /// “backup” or “rules file”.
  public var source: String
  public var name: String?
  public var rules: [LittleSnitchRule]
  public var groups: [Group]
  /// Entries in blocklists and compact deny lists, counted rather than listed.
  public var blocklistEntries: Int
  /// Rules Glade couldn’t make sense of.
  public var unreadable: Int
  /// The backup this came from and its fingerprint, so a cleaned copy is only ever made
  /// from that exact file.
  public var sourcePath: String?
  public var sourceHash: String?
  /// The rules the last review suggested deleting, by identifier.
  public var reviewRemovals: [String]?

  public var allowCount: Int { rules.filter { $0.action == "allow" && !$0.disabled }.count }
  public var denyCount: Int { rules.filter { $0.action == "deny" && !$0.disabled }.count }

  public static func parse(
    _ data: Data, now: Date = Date(), fileExists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }
  ) throws -> LittleSnitchRules {
    guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw LittleSnitchError.notJSON }
    var parsed = LittleSnitchRules(imported: now, source: "rules file", name: json["name"] as? String, rules: [], groups: [], blocklistEntries: 0, unreadable: 0)
    parsed.sourceHash = LittleSnitchBackup.fingerprint(data)
    for key in ["denied-remote-domains", "denied-remote-hosts", "denied-remote-addresses"] {
      parsed.blocklistEntries += (json[key] as? [Any])?.count ?? 0
    }
    // A backup names its groups by identifier, and each rule says which group it’s in.
    var groupNames: [String: (name: String, active: Bool, subscribed: Bool)] = [:]
    var groupCounts: [String: Int] = [:]
    var raw: [([String: Any], String?)] = []
    if let groups = json["groups"] as? [String: Any] {
      parsed.source = "backup"
      for case let (id, group as [String: Any]) in groups {
        let active = (group["isActive"] as? Bool) ?? (group["enabled"] as? Bool) ?? (group["disabled"] as? Bool).map { !$0 } ?? true
        let subscribed = (group["type"] as? String) == "loadedFromURL" || group["url"] != nil
        groupNames[id] = (groupName(group), active, subscribed)
        // Older exports keep a group’s rules inside it.
        for rule in (group["rules"] as? [[String: Any]]) ?? [] { raw.append((rule, id)) }
      }
    }
    if let rules = json["rules"] as? [[String: Any]] { raw += rules.map { ($0, $0["group"] as? String) } }
    if json["profiles"] != nil || json["globalDefaults"] != nil { parsed.source = "backup" }
    guard !raw.isEmpty || parsed.blocklistEntries > 0 || !groupNames.isEmpty else { throw LittleSnitchError.noRules }

    // Where each code identity’s executable was last seen, to tell whether it’s gone.
    let lastSeen = json["lastSeenExecutableByCodeIdentifier"] as? [String: String] ?? [:]
    for (index, item) in raw.enumerated() {
      let group = item.1.flatMap { groupNames[$0] }
      if let id = item.1, group != nil { groupCounts[id, default: 0] += 1 }
      guard var rule = rule(item.0, id: "r\(index + 1)", group: group?.name, lastSeen: lastSeen, fileExists: fileExists) else {
        parsed.unreadable += 1
        continue
      }
      // A switched-off group’s rules aren’t in force, whatever each says.
      if group?.active == false { rule.disabled = true }
      parsed.rules.append(rule)
    }
    parsed.groups = groupNames.map { id, group in
      Group(name: group.name, enabled: group.active, rules: groupCounts[id] ?? 0, subscribed: group.subscribed)
    }.sorted { $0.name < $1.name }
    return parsed
  }

  static func groupName(_ group: [String: Any]) -> String {
    if let name = (group["userProvidedName"] as? String) ?? (group["name"] as? String) ?? (group["title"] as? String), !name.isEmpty { return name }
    switch group["type"] as? String {
    case "builtinMacOSServices": return "macOS Services"
    case "builtinICloudServices": return "iCloud Services"
    case "loadedFromURL": return "Subscription"
    case "loadedFromFile": return "Imported group"
    default: return "Rule group"
    }
  }

  static func rule(
    _ dictionary: [String: Any], id: String, group: String?, lastSeen: [String: String] = [:],
    fileExists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }
  ) -> LittleSnitchRule? {
    func string(_ key: String) -> String? {
      if let value = dictionary[key] as? String { return value }
      if let values = dictionary[key] as? [String] { return values.joined(separator: ", ") }
      if let number = dictionary[key] as? NSNumber { return number.stringValue }
      return nil
    }
    guard let rawAction = string("action") else { return nil }
    // Little Snitch’s own protective rules name no process: they cover any.
    let process = string("process") ?? string("processPath") ?? string("executable") ?? "any"
    // Every remote field the rule has, so two rules only match when all of them do.
    var parts: [(kind: String, value: String)] = []
    for (key, name) in [("remote-hosts", "hosts"), ("remote-domains", "domains"), ("remote-addresses", "addresses"), ("remoteHosts", "hosts"), ("remoteDomains", "domains"), ("remoteAddresses", "addresses")] {
      if let value = string(key), !value.isEmpty, !parts.contains(where: { $0.kind == name }) { parts.append((name, value)) }
    }
    var remote = "any", kind = "any"
    if parts.count == 1 {
      (kind, remote) = (parts[0].kind, parts[0].value)
    } else if parts.count > 1 {
      kind = "mixed"
      remote = parts.map { "\($0.kind): \($0.value)" }.joined(separator: "; ")
    }
    if kind == "any", let special = string("remote"), special != "any" {
      remote = special == "list" ? "a blocklist" : special
      kind = "special"
    }
    let action = rawAction.lowercased()
    let disabled = action == "suggestion" || ((dictionary["disabled"] as? Bool) ?? (dictionary["enabled"] as? Bool).map { !$0 } ?? false)
    let notes = string("notes").map { String(Redactor.scrub($0).prefix(120)) }
    let executable = executablePath(process, lastSeen: lastSeen)
    return LittleSnitchRule(
      id: id, action: ["allow", "deny", "ask", "suggestion"].contains(action) ? action : "ask",
      process: process == "any" ? "any" : Redactor.tilde(process), app: appName(process, executable: executable),
      via: string("via").map(Redactor.tilde), remote: remote, remoteKind: kind,
      direction: (string("direction") ?? "outgoing").lowercased(), ports: string("ports"), proto: string("protocol"),
      disabled: disabled, group: group, notes: notes?.isEmpty == true ? nil : notes,
      origin: string("origin"),
      lastUsed: (dictionary["lastUsed"] as? NSNumber).map { Date(timeIntervalSinceReferenceDate: $0.doubleValue) },
      uses: (dictionary["useCount"] as? NSNumber)?.intValue,
      gone: gone(process, executable: executable, fileExists: fileExists),
      uid: (dictionary["uid"] as? NSNumber)?.intValue
    )
  }

  /// Whether what a rule is for has left this Mac. A rule naming an app by identity covers
  /// any copy, so it’s gone only when no app with that identifier is installed and its
  /// last-seen file is missing too.
  static func gone(_ process: String, executable: String?, fileExists: (String) -> Bool) -> Bool? {
    guard let executable, !isSystemPath(executable) else { return nil }
    if fileExists(executable) { return false }
    if process.hasPrefix("identifier."), let bundleID = process.split(separator: "/").last,
      NSWorkspace.shared.urlForApplication(withBundleIdentifier: String(bundleID)) != nil
    {
      return false
    }
    return true
  }

  /// macOS’s own executables move between updates, so a missing one isn’t a removed app.
  static func isSystemPath(_ path: String) -> Bool {
    ["/System/", "/usr/", "/bin/", "/sbin/", "/Library/Apple/", "/private/", "/Library/Developer/CoreSimulator/"].contains { path.hasPrefix($0) }
  }

  /// The executable a rule is for: its path, or where a code identity was last seen.
  /// Patterns (`*`) and simulator or script identities have no single file to check.
  static func executablePath(_ process: String, lastSeen: [String: String]) -> String? {
    if process.hasPrefix("/") { return process.contains("*") ? nil : process }
    // Only a plain path; simulator and script entries (`iOSSimulator./…`) aren’t files to check.
    if process.hasPrefix("identifier."), let seen = lastSeen[String(process.dropFirst("identifier.".count))], seen.hasPrefix("/") { return seen }
    return nil
  }

  /// “Safari” from its executable’s path, or from the identity’s last part.
  static func appName(_ process: String, executable: String?) -> String? {
    guard process != "any" else { return nil }
    let path = executable ?? process
    if let range = path.range(of: ".app/", options: .backwards) ?? path.range(of: ".app", options: .backwards), path.hasPrefix("/") {
      return (String(path[..<range.lowerBound]) as NSString).lastPathComponent
    }
    if process.hasPrefix("identifier.") {
      return executable.map(toolName) ?? process.split(separator: "/").last.map(String.init)
    }
    return toolName(path)
  }

  /// A tool’s name from its path; a version folder (`claude/versions/2.1.3`) gives way to
  /// the tool it belongs to.
  static func toolName(_ path: String) -> String {
    let parts = path.split(separator: "/").map(String.init)
    guard let last = parts.last else { return path }
    if last.allSatisfy({ $0.isNumber || $0 == "." }), parts.count >= 3 { return parts[parts.count - 3] }
    return last
  }

  /// What Glade notices by itself, worst first: rules that let anything through,
  /// conflicts, duplicates, rules for apps that are gone, ones unused for a year, and
  /// apps allowed to reach any server. Rules a group manages are left to the group.
  public func findings(now: Date = Date()) -> [Finding] {
    var found: [Finding] = []
    let active = rules.filter { !$0.disabled }
    let own = active.filter { !$0.managed }
    // Rules for different user accounts aren’t duplicates of each other.
    var copies: [String: [LittleSnitchRule]] = [:]
    var byTarget: [String: [LittleSnitchRule]] = [:]
    for rule in own {
      let key = [rule.process, rule.via ?? "", rule.remoteKind, rule.remote, rule.direction, rule.ports ?? "", rule.proto ?? "", rule.uid.map(String.init) ?? "*"].joined(separator: "|")
      copies[key + "|" + rule.action, default: []].append(rule)
      byTarget[key, default: []].append(rule)
    }
    for list in copies.values where list.count > 1 {
      found.append(Finding(kind: .duplicate, ruleIDs: list.map(\.id), sentence: "\(list[0].sentence) appears \(list.count == 2 ? "twice" : "\(list.count) times")."))
    }
    for list in byTarget.values {
      let actions = Set(list.map(\.action))
      if actions.contains("allow"), actions.contains("deny") {
        found.append(Finding(kind: .conflict, ruleIDs: list.map(\.id), sentence: "\(list[0].app ?? "Any process") is both allowed and denied the same connection."))
      }
    }
    var missingApps: [String: [String]] = [:]
    for rule in own where rule.gone == true && !rule.builtIn {
      missingApps[rule.app ?? rule.process, default: []].append(rule.id)
    }
    if missingApps.count > 6 {
      let ids = missingApps.values.flatMap { $0 }
      let names = missingApps.keys.sorted().prefix(6).joined(separator: ", ")
      found.append(Finding(kind: .unusedApp, ruleIDs: ids, sentence: "\(ids.count) rules are for \(missingApps.count) apps no longer on this Mac, including \(names)."))
    } else {
      for (app, ids) in missingApps.sorted(by: { $0.key < $1.key }) {
        found.append(Finding(kind: .unusedApp, ruleIDs: ids, sentence: "\(app) isn’t on this Mac any more, but \(ids.count == 1 ? "a rule for it remains" : "\(ids.count) rules for it remain")."))
      }
    }
    let yearAgo = now.addingTimeInterval(-365 * 86_400)
    let stale = own.filter { $0.action == "allow" && !$0.builtIn && $0.gone != true && ($0.lastUsed.map { $0 < yearAgo } ?? false) }
    if !stale.isEmpty {
      found.append(Finding(kind: .stale, ruleIDs: stale.map(\.id), sentence: "\(stale.count == 1 ? "One allow rule hasn’t" : "\(stale.count) allow rules haven’t") been used in over a year."))
    }
    var broad: [LittleSnitchRule] = []
    for rule in active where rule.action == "allow" && rule.remoteKind == "any" && rule.process == "any" && rule.via == nil && rule.direction == "incoming" && !rule.builtIn {
      found.append(Finding(kind: .allowsEverything, ruleIDs: [rule.id], sentence: "Any process may accept incoming connections from anywhere\(rule.ports.map { $0 == "any" ? "" : " on port \($0)" } ?? "")."))
    }
    for rule in active where rule.action == "allow" && rule.remoteKind == "any" && rule.direction == "outgoing" {
      if rule.process == "any", rule.via == nil {
        found.append(Finding(kind: .allowsEverything, ruleIDs: [rule.id], sentence: "Any process may connect to any server, which lets anything through."))
      } else if rule.process != "any", !rule.builtIn, !rule.managed {
        broad.append(rule)
      }
    }
    // Many apps reaching any server is common (browsers, chat); one line says how many.
    if broad.count > 5 {
      let names = Array(Set(broad.compactMap(\.app))).sorted().prefix(6).joined(separator: ", ")
      found.append(Finding(kind: .broadAllow, ruleIDs: broad.map(\.id), sentence: "\(broad.count) apps may connect to any server, including \(names)."))
    } else {
      for rule in broad { found.append(Finding(kind: .broadAllow, ruleIDs: [rule.id], sentence: "\(rule.app ?? rule.process) may connect to any server.")) }
    }
    // The ones that weaken the firewall first.
    let order: [Finding.Kind] = [.allowsEverything, .conflict, .duplicate, .unusedApp, .stale, .broadAllow]
    return found.enumerated().sorted {
      (order.firstIndex(of: $0.element.kind) ?? 9, $0.offset) < (order.firstIndex(of: $1.element.kind) ?? 9, $1.offset)
    }.map(\.element)
  }

  // MARK: Kept on this Mac

  public static var url: URL { GladePaths.support.appendingPathComponent("little-snitch-rules.json") }

  public static func load() -> LittleSnitchRules? { JSONFiles.read(LittleSnitchRules.self, from: url) }

  public func save() throws { try JSONFiles.write(self, to: Self.url) }

  public static var isInstalled: Bool { FileManager.default.fileExists(atPath: "/Applications/Little Snitch.app") }
}

public enum LittleSnitchError: Error, LocalizedError {
  case notJSON, noRules, unreadableFile(String)

  public var errorDescription: String? {
    switch self {
    case .notJSON: "That isn’t a Little Snitch export. In Little Snitch, choose File › Create Backup, or export a rule group."
    case .noRules: "There are no rules in that file."
    case .unreadableFile(let reason): "The file couldn’t be read: \(reason)"
    }
  }
}
