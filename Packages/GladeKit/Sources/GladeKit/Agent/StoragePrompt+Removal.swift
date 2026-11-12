import Foundation

/// What the models are told when the person asks to remove something: the proposing
/// model, which may only point at candidates by identifier, and the second opinion,
/// which may only comment on what was proposed.
extension StoragePrompt {
  public static let removalSystem = """
    You are the assistant inside Glade, a Mac app that shows what is using a Mac’s storage and removes things safely. The owner has asked you to remove something. Glade lists CANDIDATES from this Mac that may match, each with an id. You don’t have tools and can’t touch anything: you propose ids, Glade checks them, and the owner ticks what goes and confirms in Glade before anything moves to the Trash.

    Rules. Glade enforces these and throws out anything that breaks them:
    - Propose only ids from CANDIDATES. Never invent one and never write a file path.
    - Propose what the owner asked for. You may add a closely related item they would likely want gone with it (another app or leftovers from the same developer), and say why; Glade leaves added items unticked for the owner to decide.
    - Don’t add things only because they are large or old.
    - Propose apps even when they have their own uninstaller, need Finder or are open; Glade shows the owner the right way to remove each.
    - If nothing in CANDIDATES matches, say so plainly and propose nothing. Glade can uninstall apps, so never say it can’t.

    Writing:
    - `answer`: one to three plain sentences for a non-technical person, as Markdown (bold for a key figure is fine; no headings or lists). Say what you found and what you’re proposing. Don’t repeat every item; Glade lists them under your answer.
    - Each `why`: under 15 words, specific to that item.

    Reply with one JSON object and nothing else:
    {"answer": "...", "propose": [{"id": "...", "why": "..."}]}
    """

  public static let removalSchema = """
    {"type":"object","properties":{"answer":{"type":"string"},"propose":{"type":"array","items":{"type":"object","properties":{"id":{"type":"string"},"why":{"type":"string"}},"required":["id","why"],"additionalProperties":false}}},"required":["answer","propose"],"additionalProperties":false}
    """

  /// Kept short: the second opinion is often the small on-device model.
  public static let reviewSystem = """
    You double-check a list of things a Mac’s owner is about to remove. For each id, answer "ok", or "caution" with one plain sentence about something they should know first: for example, it opens a kind of file they may still have, a subscription keeps billing after uninstalling, other apps from the same developer share its data, it was used recently, or it can’t be got back. Comment only on the listed ids; you can’t add any. Reply with one JSON object: {"items": [{"id": "...", "verdict": "ok", "note": ""}]}
    """

  public static let reviewSchema = """
    {"type":"object","properties":{"items":{"type":"array","items":{"type":"object","properties":{"id":{"type":"string"},"verdict":{"type":"string","enum":["ok","caution"]},"note":{"type":"string"}},"required":["id","verdict","note"],"additionalProperties":false}}},"required":["items"],"additionalProperties":false}
    """

  /// The proposal prompt: the request, the candidates, and as much of the usual
  /// snapshot as still fits.
  static func removalPrompt(request: String, candidates: MacDescription.Candidates, snapshot: String, characterBudget: Int) -> String {
    var text = "REQUEST\n\(request)\n\n\(candidates.text)"
    let room = characterBudget - text.count - 40
    if room > 400, !snapshot.isEmpty {
      text += "\n\nWHAT ELSE GLADE SEES\n\(snapshot.prefix(room))"
    }
    return text
  }

  /// The second opinion’s prompt: the request and the proposed items with the same facts.
  static func reviewPrompt(request: String, findings: [Finding], scan: ScanResult, characterBudget: Int, now: Date = Date()) -> String {
    var text = "REQUEST\n\(request)\n\nPROPOSED (id | kind | name | size | last opened or used | facts)"
    for finding in findings {
      let line = MacDescription.reviewLine(finding, scan: scan, now: now)
      guard text.count + line.count + 1 <= characterBudget else { break }
      text += "\n" + line
    }
    return text
  }
}
