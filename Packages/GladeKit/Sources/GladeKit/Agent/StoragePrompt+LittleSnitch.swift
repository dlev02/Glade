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
    text += "RULES (\(rules.rules.count) from a \(rules.source)\(rules.blocklistEntries > 0 ? ", plus \(rules.blocklistEntries) blocklist entries not listed" : ""))\n"
    text += "id | action | process | via | remote | direction | ports | protocol | off | group\n"
    var omitted = 0
    for rule in rules.rules {
      let line = [rule.id, rule.action, rule.process, rule.via ?? "-", "\(rule.remoteKind == "any" ? "any" : "\(rule.remoteKind): \(rule.remote)")", rule.direction, rule.ports ?? "any", rule.proto ?? "any", rule.disabled ? "off" : "on", rule.group ?? "-"].joined(separator: " | ")
      guard text.count + line.count < characterBudget * 3 / 4 else {
        omitted += 1
        continue
      }
      text += line + "\n"
    }
    if omitted > 0 { text += "(\(omitted) more rules left out for length)\n" }
    let findings = rules.findings()
    if !findings.isEmpty {
      text += "\nWHAT GLADE NOTICED\n"
      for finding in findings.prefix(40) { text += "- [\(finding.ruleIDs.joined(separator: ", "))] \(finding.sentence)\n" }
    }
    if !rules.groups.isEmpty {
      text += "\nRULE GROUPS\n"
      for group in rules.groups { text += "- \(group.name): \(group.rules) rules\(group.subscribed ? ", subscribed" : "")\(group.enabled == false ? ", off" : "")\n" }
    }
    return text
  }
}
