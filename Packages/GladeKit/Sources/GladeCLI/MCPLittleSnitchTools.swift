import Foundation
import GladeKit

/// Little Snitch, from the person’s own export. Read only.
extension MCPTools {
  static let littleSnitch: [MCPTool] = [
    MCPTool(
      name: "glade_littlesnitch",
      description: "The person's Little Snitch rules from the export they imported into Glade (each rule's action, app path, destination, direction, ports, group), with what Glade noticed: rules for apps that are gone, duplicates, allow/deny conflicts and rules that allow any server. Glade never reads or changes Little Snitch itself. If nothing is imported, tell the person to choose File › Create Backup in Little Snitch and run `glade littlesnitch import <file>`. To change rules, suggest them; the person applies them in Little Snitch or imports a file from `glade littlesnitch review`.",
      schema: #"{"type":"object","properties":{},"additionalProperties":false}"#, readOnly: true
    ) { _ in
      guard let rules = LittleSnitchRules.load() else {
        throw MCPFailure(message: "No Little Snitch rules imported. In Little Snitch choose File › Create Backup, then run `glade littlesnitch import <file>`.")
      }
      struct Report: Encodable {
        var rules: LittleSnitchRules
        var findings: [LittleSnitchRules.Finding]
      }
      // Notes are the person’s own words; the review leaves them out too.
      var shown = rules
      shown.rules = rules.rules.map { rule in
        var rule = rule
        rule.notes = nil
        return rule
      }
      return JSONFiles.string(Report(rules: shown, findings: rules.findings()))
    },
  ]
}
