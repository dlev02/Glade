import Foundation

/// The person’s standing rules: apps and tools whose leftovers and caches they always
/// want gone (“I don’t use Cursor any more”). A rule ticks a matching finding at every
/// level, the way the person would by hand, so it may tick what no level or AI can,
/// such as an app’s leftovers. It never ticks personal files, anything blocked or in
/// use, or an installed app, and only a person can add one.
public enum AlwaysClear {
  /// The shortest rule accepted, so “AI” or “Go” can’t sweep in half the disk.
  public static let minimumLength = 3

  /// The rule that ticks this finding, or `nil`.
  public static func rule(for finding: Finding, rules: [String]) -> String? {
    guard mayClear(finding) else { return nil }
    return rules.first { rule in
      matches(finding.owner?.name ?? "", rule: rule) || matches(finding.title, rule: rule)
    }
  }

  /// What a rule may never tick, whatever it names.
  public static func mayClear(_ finding: Finding) -> Bool {
    !finding.isBlocked && finding.risk != .personal && finding.category != .installedApps
  }

  /// The rule’s words appear in the name, whole and in order: “Cursor” matches
  /// “Cursor” and “Cursor’s cache”, not “Cursorly” or “Recursor”.
  static func matches(_ name: String, rule: String) -> Bool {
    let wanted = words(rule)
    guard !wanted.isEmpty, rule.trimmingCharacters(in: .whitespaces).count >= minimumLength else { return false }
    let have = words(name)
    guard have.count >= wanted.count else { return false }
    for start in 0...(have.count - wanted.count) where Array(have[start..<start + wanted.count]) == wanted {
      return true
    }
    return false
  }

  static func words(_ text: String) -> [String] {
    // “Cursor’s” is Cursor’s: drop a possessive before splitting.
    let plain = text.lowercased().replacingOccurrences(of: "’s", with: "").replacingOccurrences(of: "'s", with: "")
    return plain.split { !$0.isLetter && !$0.isNumber }.map(String.init)
  }

  /// A rule cleaned up for saving, or `nil` when it’s too short to be safe.
  public static func normalised(_ rule: String) -> String? {
    let trimmed = rule.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.count >= minimumLength && !words(trimmed).isEmpty ? trimmed : nil
  }
}
