import Foundation

/// One Little Snitch rule, reduced to the fields Glade reads: who, where, which way,
/// allowed or not. Paths have the home folder shortened to `~`.
public struct LittleSnitchRule: Codable, Sendable, Identifiable, Equatable {
  /// Stable within one import: `r1`, `r2`…
  public var id: String
  /// `allow`, `deny` or `ask`.
  public var action: String
  /// `any`, or the executable’s path.
  public var process: String
  /// The app the executable belongs to, such as “Safari”.
  public var app: String?
  public var via: String?
  /// `any`, `local-net`… or the hosts, domains or addresses it names.
  public var remote: String
  public var remoteKind: String
  public var direction: String
  public var ports: String?
  public var proto: String?
  public var disabled: Bool
  public var group: String?
  public var notes: String?

  /// “Allow Safari to reach any server”.
  public var sentence: String {
    let who = process == "any" ? "any process" : (app ?? (process as NSString).lastPathComponent)
    let verb = action == "deny" ? "Deny" : action == "allow" ? "Allow" : "Ask before"
    let target = remoteKind == "any" ? "any server" : remoteKind == "special" ? remote : remote
    let way = direction == "incoming" ? "incoming connections from" : "connecting to"
    return "\(verb) \(who) \(way) \(target)\(ports.map { $0 == "any" ? "" : " on port \($0)" } ?? "")\(disabled ? " (off)" : "")"
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
    }

    public var id: String { kind.rawValue + ruleIDs.joined(separator: ",") }
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

  public var allowCount: Int { rules.filter { $0.action == "allow" }.count }
  public var denyCount: Int { rules.filter { $0.action == "deny" }.count }

  static let home = NSHomeDirectory()

  public static func parse(_ data: Data, now: Date = Date()) throws -> LittleSnitchRules {
    guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw LittleSnitchError.notJSON }
    var parsed = LittleSnitchRules(imported: now, source: "rules file", name: json["name"] as? String, rules: [], groups: [], blocklistEntries: 0, unreadable: 0)
    var raw: [([String: Any], String?)] = []
    if let rules = json["rules"] as? [[String: Any]] { raw += rules.map { ($0, nil) } }
    for key in ["denied-remote-domains", "denied-remote-hosts", "denied-remote-addresses"] {
      parsed.blocklistEntries += (json[key] as? [Any])?.count ?? 0
    }
    // A backup also has rule groups, each possibly with its own rules.
    if let groups = json["groups"] as? [String: Any] {
      parsed.source = "backup"
      for case let group as [String: Any] in groups.values {
        let name = (group["name"] as? String) ?? (group["title"] as? String) ?? "Unnamed group"
        let rules = (group["rules"] as? [[String: Any]]) ?? []
        raw += rules.map { ($0, name) }
        let subscribed = group["url"] != nil || group["subscriptionURL"] != nil || group["remoteURL"] != nil
        let enabled = (group["enabled"] as? Bool) ?? (group["disabled"] as? Bool).map { !$0 }
        parsed.groups.append(Group(name: name, enabled: enabled, rules: rules.count, subscribed: subscribed))
      }
    }
    if json["profiles"] != nil || json["globalDefaults"] != nil { parsed.source = "backup" }
    guard !raw.isEmpty || parsed.blocklistEntries > 0 || !parsed.groups.isEmpty else { throw LittleSnitchError.noRules }
    for (index, item) in raw.enumerated() {
      if let rule = rule(item.0, id: "r\(index + 1)", group: item.1) { parsed.rules.append(rule) } else { parsed.unreadable += 1 }
    }
    parsed.groups.sort { $0.name < $1.name }
    return parsed
  }

  static func rule(_ dictionary: [String: Any], id: String, group: String?) -> LittleSnitchRule? {
    func string(_ key: String) -> String? {
      if let value = dictionary[key] as? String { return value }
      if let values = dictionary[key] as? [String] { return values.joined(separator: ", ") }
      if let number = dictionary[key] as? NSNumber { return number.stringValue }
      return nil
    }
    guard let process = string("process") ?? string("processPath") ?? string("executable") else { return nil }
    var remote = "any", kind = "any"
    for (key, name) in [("remote-hosts", "hosts"), ("remote-domains", "domains"), ("remote-addresses", "addresses"), ("remoteHosts", "hosts"), ("remoteDomains", "domains"), ("remoteAddresses", "addresses")] {
      if let value = string(key), !value.isEmpty {
        remote = value
        kind = name
        break
      }
    }
    if kind == "any", let special = string("remote"), special != "any" {
      remote = special
      kind = "special"
    }
    let action = (string("action") ?? "ask").lowercased()
    let disabled = (dictionary["disabled"] as? Bool) ?? (dictionary["enabled"] as? Bool).map { !$0 } ?? false
    let notes = string("notes").map { String(Redactor.scrub($0).prefix(120)) }
    return LittleSnitchRule(
      id: id, action: ["allow", "deny", "ask"].contains(action) ? action : "ask",
      process: process == "any" ? "any" : Redactor.tilde(process), app: appName(process),
      via: string("via").map(Redactor.tilde), remote: remote, remoteKind: kind,
      direction: (string("direction") ?? "outgoing").lowercased(), ports: string("ports"), proto: string("protocol"),
      disabled: disabled, group: group, notes: notes?.isEmpty == true ? nil : notes
    )
  }

  /// “Safari” from `/Applications/Safari.app/Contents/MacOS/Safari`; the tool’s name otherwise.
  static func appName(_ process: String) -> String? {
    guard process != "any" else { return nil }
    if let range = process.range(of: ".app/", options: .backwards) ?? process.range(of: ".app", options: .backwards) {
      return (String(process[..<range.lowerBound]) as NSString).lastPathComponent
    }
    return (process as NSString).lastPathComponent
  }

  /// What Glade notices by itself: rules for apps that are gone, duplicates, conflicts
  /// and rules that allow more than most people mean to.
  public func findings(fileExists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }) -> [Finding] {
    var found: [Finding] = []
    let active = rules.filter { !$0.disabled }
    var seen: [String: String] = [:]
    var byTarget: [String: [LittleSnitchRule]] = [:]
    for rule in active {
      let key = [rule.process, rule.via ?? "", rule.remote, rule.direction, rule.ports ?? "", rule.proto ?? ""].joined(separator: "|")
      if let first = seen[key + "|" + rule.action] {
        found.append(Finding(kind: .duplicate, ruleIDs: [first, rule.id], sentence: "\(rule.sentence) appears twice."))
      } else {
        seen[key + "|" + rule.action] = rule.id
      }
      byTarget[key, default: []].append(rule)
    }
    for list in byTarget.values {
      let actions = Set(list.map(\.action))
      if actions.contains("allow"), actions.contains("deny") {
        found.append(Finding(kind: .conflict, ruleIDs: list.map(\.id), sentence: "\(list[0].app ?? "Any process") is both allowed and denied the same connection."))
      }
    }
    var missingApps: [String: [String]] = [:]
    for rule in active where rule.process != "any" {
      let path = rule.process.hasPrefix("~") ? Self.home + rule.process.dropFirst() : rule.process
      guard path.hasPrefix("/"), !path.hasPrefix("/System/"), !path.hasPrefix("/usr/"), !path.hasPrefix("/bin/"), !path.hasPrefix("/sbin/") else { continue }
      if !fileExists(path) { missingApps[rule.app ?? rule.process, default: []].append(rule.id) }
    }
    for (app, ids) in missingApps.sorted(by: { $0.key < $1.key }) {
      found.append(Finding(kind: .unusedApp, ruleIDs: ids, sentence: "\(app) isn’t on this Mac any more, but \(ids.count == 1 ? "a rule for it remains" : "\(ids.count) rules for it remain")."))
    }
    for rule in active where rule.action == "allow" && rule.remoteKind == "any" && rule.direction == "outgoing" {
      if rule.process == "any" {
        found.append(Finding(kind: .allowsEverything, ruleIDs: [rule.id], sentence: "Any process may connect to any server, which lets anything through."))
      } else {
        found.append(Finding(kind: .broadAllow, ruleIDs: [rule.id], sentence: "\(rule.app ?? rule.process) may connect to any server."))
      }
    }
    // The ones that weaken the firewall first.
    let order: [Finding.Kind] = [.allowsEverything, .conflict, .duplicate, .unusedApp, .broadAllow]
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
