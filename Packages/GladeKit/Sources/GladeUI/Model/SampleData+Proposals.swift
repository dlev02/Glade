import Foundation
import GladeKit

/// A made-up proposal for screenshots and demo mode: two apps the person named (one
/// Glade can remove, one with its own uninstaller), one the AI added, and the second
/// opinion’s notes.
extension SampleData {
  static let sampleRemovalRequest = "Uninstall Final Cut Pro and Photoshop, I don’t edit any more"

  static func sampleProposal(scan: ScanResult, request: String = sampleRemovalRequest, reviewed: Bool = true) -> RemovalProposal {
    func app(_ name: String) -> Finding? {
      scan.findings.first { $0.category == .installedApps && $0.title == name }
    }
    let notes: [(name: String, why: String, caution: String?)] = [
      ("Final Cut Pro", "The video editor you named; not opened in over a year.", "Libraries made in Final Cut Pro only open in it, so keep it if you might edit one again."),
      ("Adobe Photoshop 2025", "The Photoshop you named.", "Uninstalling doesn’t end a Creative Cloud plan; cancel it with Adobe."),
      ("iMovie", "Another video editor, not opened in eight months.", nil),
    ]
    let items = notes.compactMap { note -> RemovalProposal.Item? in
      guard let finding = app(note.name) else { return nil }
      var item = RemovalProposal.item(for: finding, why: note.why, named: RemovalRequest.isNamed(finding, in: request))
      if reviewed { item.review = RemovalProposal.Review(verdict: note.caution == nil ? .ok : .caution, note: note.caution ?? "") }
      return item
    }
    return RemovalProposal(
      request: request,
      answer: "I found **Final Cut Pro** and **Photoshop**, and added iMovie, another video editor you haven’t opened in months. Photoshop comes with its own uninstaller.",
      items: items, rejected: [], provider: "claude", model: "sonnet", runID: "sample-proposal",
      reviewer: reviewed ? "apple" : nil, scanID: scan.id
    )
  }
}
