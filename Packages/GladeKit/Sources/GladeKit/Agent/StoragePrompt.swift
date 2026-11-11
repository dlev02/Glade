import Foundation

/// Builds what the assistant is told about storage. Everything a model learns about
/// this Mac’s files passes through here, so this is also where privacy is enforced:
/// only findings the scanner produced are described (protected areas never produce
/// any), and only by title, size, age and location.
public enum StoragePrompt {
  public static let system = """
    You are the assistant inside Glade, a Mac app that frees up storage safely. Glade has already scanned this Mac and classified what it found. You don’t have tools and you can’t see or touch files; you advise by referring to findings by their id.

    Each finding line gives: id | size | category | what it is | when it was last used | how it comes back if removed | whether Glade’s rules selected it (and why) | flags.

    Your job is to improve the selection with judgement the rules lack.

    Hard rules. Glade enforces these and discards anything that breaks them:
    - Use only ids from the list. Never invent one, and never write a file path.
    - You may add a finding to `select` only if its flags include `can-add`.
    - Findings flagged `personal` or `manual` can never be selected. If one looks like a strong candidate, put it in `review` and the person will decide.
    - Findings flagged `blocked` can’t be removed right now. Leave them out.

    Good judgement:
    - Protect work in progress. Leave build data, dependencies and caches for projects and apps that were used in the last few days, especially ones named under ACTIVITY. Rebuilding them costs the person time.
    - Stale beats large. Something untouched for months is a better choice than something bigger that was used this week.
    - If there is a GOAL with an amount, try to reach it inside the level. If you can’t, say so plainly and point to what the person could review.
    - Don’t add things just because you can. Deselect anything the rules picked that you’d regret removing.
    - `review` is for at most 8 personal or manual items that look most worth a person’s time: old installers, large old files, duplicates, games not played in months.

    Writing:
    - `summary`: two or three plain sentences for a non-technical person, as Markdown (bold for the key figure is fine; no headings or lists). Say roughly how much you’d clear, the main things, and what you left alone and why. No jargon ("regenerable", "artifacts").
    - Each `why`: under 20 words, specific to that item.
    - Set `escalate.needed` to true only when the choice is genuinely unclear or risky and a stronger model’s judgement would change the answer.

    Reply with one JSON object and nothing else:
    {"summary": "...", "select": [{"id": "...", "why": "..."}], "deselect": [{"id": "...", "why": "..."}], "review": [{"id": "...", "why": "..."}], "escalate": {"needed": false, "why": ""}}
    """

  public static let questionSystem = """
    You are the assistant inside Glade, a Mac app that shows what is using a Mac’s storage, memory and processors and helps clear it safely. You are given a snapshot Glade took of this Mac and a question from its owner.

    Answer from the snapshot only. If it doesn’t contain what you’d need, say what’s missing instead of guessing. Be specific: name the apps and items and give the numbers. Keep it short, in plain language for a non-technical person. Markdown is shown formatted: a few bullets or a numbered list and **bold** for the key figures help; use at most a small `###` heading, and only when the answer has more than one part. You can’t take actions; if something should be done, say which Glade action does it (a Careful, Balanced or Aggressive clean, or quitting a named app).
    """

  public static let schema = """
    {"type":"object","properties":{"summary":{"type":"string"},"select":{"type":"array","items":{"type":"object","properties":{"id":{"type":"string"},"why":{"type":"string"}},"required":["id","why"],"additionalProperties":false}},"deselect":{"type":"array","items":{"type":"object","properties":{"id":{"type":"string"},"why":{"type":"string"}},"required":["id","why"],"additionalProperties":false}},"review":{"type":"array","items":{"type":"object","properties":{"id":{"type":"string"},"why":{"type":"string"}},"required":["id","why"],"additionalProperties":false}},"escalate":{"type":"object","properties":{"needed":{"type":"boolean"},"why":{"type":"string"}},"required":["needed","why"],"additionalProperties":false}},"required":["summary","select","deselect","review","escalate"],"additionalProperties":false}
    """

  public struct Built: Sendable {
    public var text: String
    /// The findings that fitted. Suggestions about anything else are ignored.
    public var includedIDs: [String]
  }

  /// Describes a scan and a plan in as few characters as possible.
  /// - Parameter characterBudget: Roughly four characters per token. Small for the
  ///   on-device model, generous for the others.
  public static func build(scan: ScanResult, plan: CleanPlan, goal: String?, activity: String?, characterBudget: Int) -> Built {
    var header = ""
    if let goal, !goal.isEmpty { header += "GOAL: \(goal)\n" }
    header += "LEVEL: \(plan.level.rawValue) (\(levelMeaning(plan.level)))\n"
    header += "DISK: \(Format.bytes(scan.volume.availableBytes)) free of \(Format.bytes(scan.volume.totalBytes))\n"
    header += "RULES SELECTED: \(Format.bytes(plan.selectedBytes)) across \(plan.selectedIDs.count) findings\n"
    if let activity, !activity.isEmpty { header += "ACTIVITY: \(activity)\n" }
    header += "\nFINDINGS (largest first)\n"

    let reasons = Dictionary(uniqueKeysWithValues: plan.items.map { ($0.id, $0) })
    var lines: [String] = []
    var included: [String] = []
    var used = header.count
    var omitted = 0
    var omittedBytes: Int64 = 0
    let compact = characterBudget < 20_000

    for finding in scan.findings.sorted(by: { $0.bytes > $1.bytes }) {
      let item = reasons[finding.id]
      var flags: [String] = []
      if finding.isBlocked { flags.append("blocked") }
      if finding.risk == .personal { flags.append("personal") }
      if finding.autoLevel == nil, finding.risk != .personal { flags.append("manual") }
      if item?.selected != true, Planner.mayAutoSelect(finding), let level = finding.autoLevel, level <= plan.level {
        flags.append("can-add")
      }
      let state = item?.selected == true ? "selected" : "not selected: \(item?.reason ?? "")"
      var line = "\(finding.id) | \(Format.bytes(finding.bytes)) | \(finding.category.title) | \(finding.title)"
      line += " | \(Format.age(finding.lastUsed)) | \(finding.recovery.title.lowercased()) | \(state)"
      if !flags.isEmpty { line += " | \(flags.joined(separator: ","))" }
      if !compact, finding.paths.count == 1 { line += " | \(Redactor.tilde(finding.paths[0]))" }
      if !compact, let project = finding.project { line += " | project \(project)" }

      if used + line.count + 1 > characterBudget {
        omitted += 1
        omittedBytes += finding.bytes
        continue
      }
      used += line.count + 1
      lines.append(line)
      included.append(finding.id)
    }
    var text = header + lines.joined(separator: "\n")
    if omitted > 0 {
      text += "\n(\(omitted) smaller findings totalling \(Format.bytes(omittedBytes)) aren’t listed; the rules' choices for them stand.)"
    }
    return Built(text: text, includedIDs: included)
  }

  static func levelMeaning(_ level: CleanLevel) -> String {
    switch level {
    case .careful: "only things that rebuild themselves and haven’t been touched lately"
    case .balanced: "also things that download or reinstall, and stale agent history, when they’ve sat idle"
    case .aggressive: "everything that can come back, even if used recently"
    }
  }
}
