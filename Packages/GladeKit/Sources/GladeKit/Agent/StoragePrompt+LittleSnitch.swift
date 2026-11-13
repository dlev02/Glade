import Foundation

/// The prompt for reviewing Little Snitch rules. The model reads the rules and Glade’s
/// own findings and answers in JSON; Glade checks every suggestion before it counts.
extension StoragePrompt {
  public static let littleSnitchSystem = """
    You are the assistant inside Glade, a Mac app. The owner uses Little Snitch, a firewall that asks before apps connect to the internet, and wants their rules reviewed: what overlaps, what is broader than they probably meant, what is left over from apps they removed, and gaps worth closing. You are given their rules (one per line, with an identifier) and what Glade noticed by itself.

    Little Snitch protects them, so be conservative. Never suggest letting any process reach any server. Never suggest removing a deny rule unless it duplicates another. Suggest new rules only for processes already in the list, written exactly as shown, or "any" for a deny. Prefer domains (apple.com) over single hosts. Browsers and similar apps reaching any server is normal; say so rather than flagging it. Explain in plain language for a non-technical person.

    Reply with JSON only: {"summary": "two or three sentences", "points": [{"title": "short", "detail": "one or two sentences", "rules": ["r12"]}], "remove": ["rule identifiers worth deleting"], "add": [{"action": "allow or deny", "process": "exactly as listed, or any", "domains": ["example.com"], "hosts": [], "direction": "outgoing or incoming", "notes": "why"}]}. Up to 8 points. Empty lists are fine.
    """

  public static let littleSnitchSchema = """
    {"type":"object","properties":{"summary":{"type":"string"},"points":{"type":"array","items":{"type":"object","properties":{"title":{"type":"string"},"detail":{"type":"string"},"rules":{"type":"array","items":{"type":"string"}}},"required":["title","detail","rules"],"additionalProperties":false}},"remove":{"type":"array","items":{"type":"string"}},"add":{"type":"array","items":{"type":"object","properties":{"action":{"type":"string"},"process":{"type":"string"},"domains":{"type":"array","items":{"type":"string"}},"hosts":{"type":"array","items":{"type":"string"}},"direction":{"type":"string"},"notes":{"type":"string"}},"required":["action","process","domains","hosts","direction","notes"],"additionalProperties":false}}},"required":["summary","points","remove","add"],"additionalProperties":false}
    """

  /// The rules as compact lines, then Glade’s findings, then what the owner asked.
  public static func littleSnitchPrompt(_ rules: LittleSnitchRules, request: String?, characterBudget: Int) -> String {
    var text = ""
    if let request, !request.isEmpty { text += "OWNER’S REQUEST\n\(request)\n\n" }
    // The person’s own rules, the ones Glade noticed first, then the most used. Rules a
    // group or Little Snitch itself manages are counted, not listed.
    let findings = rules.findings()
    let flagged = Set(findings.flatMap(\.ruleIDs))
    let own = rules.rules.filter { !$0.managed && !$0.builtIn && !$0.disabled }
    let ordered = own.filter { flagged.contains($0.id) } + own.filter { !flagged.contains($0.id) }.sorted { ($0.uses ?? 0) > ($1.uses ?? 0) }
    let managed = rules.rules.filter(\.managed).count, builtIn = rules.rules.filter { $0.builtIn && !$0.managed }.count
    text += "RULES: \(own.count) of the owner’s own in force (\(managed) more come from rule groups and \(builtIn) are Little Snitch’s or macOS’s own; not listed)\(rules.blocklistEntries > 0 ? ", plus \(rules.blocklistEntries) blocklist entries" : "")\n"
    text += "id | action | app | process | via (helper it connects through) | remote | direction | ports | user | last used | uses\n"
    var omitted = 0
    for rule in ordered {
      let remote = rule.remoteKind == "any" ? "any" : "\(rule.remoteKind): \(rule.remote.prefix(160))"
      let used = rule.lastUsed.map { $0.formatted(.iso8601.year().month().day()) } ?? "never"
      var fields = [rule.id, rule.action, rule.app ?? "-", rule.process, rule.via ?? "-", remote]
      fields += [rule.direction == "outgoing" ? "out" : "in", rule.ports ?? "any", rule.uid.map { "uid \($0)" } ?? "all", used, rule.uses.map(String.init) ?? "-"]
      if rule.gone == true { fields.append("app gone") }
      let line = fields.joined(separator: " | ")
      guard text.count + line.count < characterBudget * 3 / 4 else {
        omitted += 1
        continue
      }
      text += line + "\n"
    }
    if omitted > 0 { text += "(\(omitted) more of their rules left out for length; the least used)\n" }
    if !findings.isEmpty {
      text += "\nWHAT GLADE NOTICED\n"
      for finding in findings.prefix(40) { text += "- [\(finding.ruleIDs.prefix(12).joined(separator: ", "))\(finding.ruleIDs.count > 12 ? ", …" : "")] \(finding.sentence)\n" }
    }
    if !rules.groups.isEmpty {
      text += "\nRULE GROUPS\n"
      for group in rules.groups { text += "- \(group.name): \(group.rules) rules\(group.subscribed ? ", subscribed" : "")\(group.enabled == false ? ", off" : "")\n" }
    }
    return text
  }
}
