import Foundation

/// A review of the person’s Little Snitch rules: points in words, rules worth deleting
/// by hand, and new rules as an `.lsrules` file they can import as a group that starts
/// switched off. Glade never changes Little Snitch itself.
public struct LittleSnitchReview: Codable, Sendable {
  public struct Point: Codable, Sendable, Identifiable {
    public var id: String { title }
    public var title: String
    public var detail: String
    public var ruleIDs: [String]
  }

  public struct NewRule: Codable, Sendable {
    public var action: String
    /// The full path, or `any`.
    public var process: String
    public var domains: [String]
    public var hosts: [String]
    public var direction: String
    public var notes: String
  }

  public var summary: String
  public var points: [Point]
  /// Rules worth deleting, each as a sentence the person can find in Little Snitch.
  public var remove: [LittleSnitchRule]
  public var add: [NewRule]
  /// Suggestions Glade refused, and why.
  public var rejected: [String]
  public var provider: String
  public var model: String?
  public var runID: String

  /// The new rules as a Little Snitch rule group file, or `nil` when there are none.
  public func rulesFile(now: Date = Date()) -> Data? {
    guard !add.isEmpty else { return nil }
    var rules: [[String: Any]] = []
    for rule in add {
      var item: [String: Any] = ["action": rule.action, "process": rule.process, "direction": rule.direction]
      if !rule.domains.isEmpty { item["remote-domains"] = rule.domains }
      if !rule.hosts.isEmpty { item["remote-hosts"] = rule.hosts }
      if !rule.notes.isEmpty { item["notes"] = rule.notes }
      rules.append(item)
    }
    let file: [String: Any] = [
      "name": "Suggested by Glade, \(now.formatted(date: .abbreviated, time: .omitted))",
      "description": "Rules Glade’s Assistant suggested. Review each before turning the group on.",
      "rules": rules,
    ]
    return try? JSONSerialization.data(withJSONObject: file, options: [.prettyPrinted, .sortedKeys])
  }
}
