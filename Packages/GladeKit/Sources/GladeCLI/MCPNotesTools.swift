import Foundation
import GladeKit

/// What the person has told Glade to remember, for agents too. Read only: notes and
/// rules are the person’s to write.
extension MCPTools {
  static let notes: [MCPTool] = [
    MCPTool(
      name: "glade_notes",
      description: "What the person keeps for Glade's Assistant: dated notes (their internet provider and router, problems that came back before, apps they no longer use) and standing rules (apps whose leftovers and caches Glade always ticks). Read them before advising; current readings win where a note disagrees. To keep a new note, suggest the person runs `glade notes add \"…\"` or saves it in Glade; you can't write them.",
      schema: #"{"type":"object","properties":{},"additionalProperties":false}"#, readOnly: true
    ) { _ in
      struct Report: Encodable {
        var notes: [AssistantNote]
        var alwaysClear: [String]
      }
      return JSONFiles.string(Report(notes: AssistantNotes.load(), alwaysClear: ConfigStore.load().alwaysClear))
    },
  ]
}
