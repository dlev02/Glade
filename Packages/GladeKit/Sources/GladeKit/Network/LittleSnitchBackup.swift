import CryptoKit
import Foundation

/// A cleaned copy of the person’s Little Snitch backup: the same file with only the rules
/// they chose to drop taken out, everything else untouched, for Little Snitch’s own
/// Restore from Backup. Little Snitch backs up the current setup before it restores, so
/// the change can be undone there, and the original file is never changed.
public enum LittleSnitchBackup {
  public enum Problem: Error, LocalizedError, Equatable {
    case notTheSameFile, unsupportedFormat, nothingToRemove, refused(String), checkFailed

    public var errorDescription: String? {
      switch self {
      case .notTheSameFile: "That isn’t the backup Glade read (it has changed since). Import it again first."
      case .unsupportedFormat: "This backup keeps rules inside its groups, which Glade can’t clean safely. Delete the rules in Little Snitch instead."
      case .nothingToRemove: "There’s nothing to remove."
      case .refused(let reason): reason
      case .checkFailed: "The cleaned copy didn’t check out, so Glade didn’t save it."
      }
    }
  }

  public static func fingerprint(_ data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
  }

  /// The backup without the rules named, after checking each may go: never a rule a group
  /// or Little Snitch manages, and never a deny rule unless it’s an exact duplicate.
  /// - Returns: The new file and how many rules it leaves out.
  public static func cleaned(_ original: Data, removing ids: Set<String>, expected: LittleSnitchRules) throws -> (data: Data, removed: Int) {
    guard fingerprint(original) == expected.sourceHash else { throw Problem.notTheSameFile }
    guard !ids.isEmpty else { throw Problem.nothingToRemove }
    guard var json = try JSONSerialization.jsonObject(with: original) as? [String: Any], let rules = json["rules"] as? [Any] else {
      throw Problem.unsupportedFormat
    }
    // Identifiers count top-level rules only when no group holds its own.
    if let groups = json["groups"] as? [String: Any], groups.values.contains(where: { ($0 as? [String: Any])?["rules"] != nil }) {
      throw Problem.unsupportedFormat
    }
    let parsed = try LittleSnitchRules.parse(original)
    guard parsed.rules.count == rules.count, parsed.unreadable == 0 else { throw Problem.unsupportedFormat }
    let duplicates = Set(parsed.findings().filter { $0.kind == .duplicate }.flatMap { $0.ruleIDs.dropFirst() })
    var drop = Set<Int>()
    for id in ids {
      guard let index = Int(id.dropFirst()).map({ $0 - 1 }), id.hasPrefix("r"), parsed.rules.indices.contains(index) else {
        throw Problem.refused("\(id) isn’t a rule in this backup.")
      }
      let rule = parsed.rules[index]
      if rule.managed || rule.builtIn { throw Problem.refused("\(rule.sentence) belongs to \(rule.group ?? "Little Snitch") and stays.") }
      if rule.action == "deny", !duplicates.contains(id) { throw Problem.refused("\(rule.sentence) is a block and stays.") }
      drop.insert(index)
    }
    json["rules"] = rules.enumerated().filter { !drop.contains($0.offset) }.map(\.element)
    let data = try JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
    // The copy must read back with exactly those rules gone and every other key as it was.
    guard let check = try? LittleSnitchRules.parse(data), check.rules.count == parsed.rules.count - drop.count,
      let reread = try JSONSerialization.jsonObject(with: data) as? [String: Any],
      Set(reread.keys) == Set((try JSONSerialization.jsonObject(with: original) as? [String: Any])?.keys ?? [:].keys)
    else { throw Problem.checkFailed }
    Log.info(.network, "Made a cleaned Little Snitch backup without \(drop.count) rules")
    return (data, drop.count)
  }
}
