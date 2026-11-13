import Foundation

/// The person’s standing rules: apps and tools whose leftovers and caches they always
/// want gone (“I don’t use Cursor any more”). A rule ticks a finding owned by that app
/// at every level, in plans the person sees before a clean, the way they would by hand.
/// It ticks only an app’s leftovers (which go to the Trash) and things that rebuild or
/// download again; never personal files, anything blocked or in use, an installed app
/// or a copy of one, or anything else that can’t come back. Only a person adds one.
public enum AlwaysClear {
  /// The shortest rule accepted, so “AI” or “Go” can’t sweep in half the disk.
  public static let minimumLength = 3

  /// The rule that ticks this finding, or `nil`.
  public static func rule(for finding: Finding, rules: [String]) -> String? {
    guard mayClear(finding), let owner = finding.owner?.name else { return nil }
    // The owner only: a title can mention an app (“Worktree – Glade”) without being its.
    return rules.first { matches(owner, rule: $0) }
  }

  /// What a rule may tick at all, whatever it names: an app’s leftovers, which go to the
  /// Trash, or something that rebuilds or downloads again.
  public static func mayClear(_ finding: Finding) -> Bool {
    guard !finding.isBlocked, finding.risk != .personal, finding.category != .installedApps, finding.category != .appCopies else { return false }
    if finding.category == .appLeftovers { return finding.method == .trash }
    return finding.autoLevel != nil && (finding.recovery == .automatic || finding.recovery == .redownload)
  }

  /// The rule’s words appear in the name, whole and in order: “Cursor” matches
  /// “Cursor” and “Cursor’s cache”, not “Cursorly” or “Recursor”.
  static func matches(_ name: String, rule: String) -> Bool {
    let wanted = words(rule)
    guard !wanted.isEmpty, wanted.joined().count >= minimumLength else { return false }
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
    // Letters and digits count, so “C++” (one letter) is too short.
    return words(trimmed).joined().count >= minimumLength ? trimmed : nil
  }
}
