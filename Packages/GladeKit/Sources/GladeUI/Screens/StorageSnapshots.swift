import Foundation
import GladeKit
import SwiftUI

/// The storage screens that can be drawn to an image with `glade snapshot <name>`.
/// Sheets are drawn on their own; render them with `--width 440 --height 460`.
enum StorageSnapshots {
  /// Reading these means a snapshot is being drawn, so the screen switches to what
  /// the offscreen renderer can draw.
  static var all: [String: (AppModel) -> AnyView] {
    StorageScreen.drawsOffscreen = true
    return screens
  }

  private static let screens: [String: (AppModel) -> AnyView] = [
    "storage": { _ in screen(StorageViewState(showsInspector: false)) },
    "storage-everything": { _ in screen(StorageViewState(scope: .everything, showsInspector: false)) },
    "storage-review": { _ in screen(StorageViewState(scope: .review, showsInspector: false)) },
    "storage-inspector": { model in
      let id = model.scan?.findings.first { $0.title.hasPrefix("Build data – Lantern") }?.id
      return screen(StorageViewState(highlighted: id, showsInspector: true))
    },
    // The offscreen renderer leaves the inspector column blank, so its content is
    // drawn on its own too.
    "storage-inspector-panel": { model in
      let finding = model.scan?.findings.first { $0.title.hasPrefix("Worktree – Lantern") }
      return panel(FindingInspector(finding: finding))
    },
    "storage-inspector-blocked": { model in
      panel(FindingInspector(finding: model.scan?.findings.first(where: \.isBlocked)))
    },
    "storage-inspector-permanent": { model in
      panel(FindingInspector(finding: model.scan?.findings.first { $0.recovery == .permanent }))
    },
    // Open with nothing highlighted: what's selected, by category.
    "storage-inspector-selection": { _ in panel(FindingInspector(finding: nil)) },
    "storage-advice": { model in
      screen(StorageViewState(showsInspector: false), advice: sampleAdvice(model))
    },
    "storage-advice-banner": { model in
      AnyView(sampleAdvice(model).map { advice in
        AdviceBanner(advice: advice) { id in model.scan?.finding(id)?.title }.frame(width: 700).padding()
      })
    },
    "storage-empty": { _ in AnyView(NavigationStack { StorageEmptyState().navigationTitle("Storage") }) },
    "storage-scanning": { _ in AnyView(NavigationStack { StorageScanning(done: 7, total: 19).navigationTitle("Storage") }) },
    "storage-minimum": { model in
      model.section = .storage
      return AnyView(RootView())
    },
    "storage-confirm": { _ in AnyView(sheet(CleanConfirmation(cancel: {}, confirm: {}))) },
    "storage-progress": { _ in
      AnyView(sheet(CleanProgress(done: 4, total: 11, title: "Simulator system · iOS 18.0")))
    },
    "storage-result": { model in
      guard let receipt = SampleData.sampleReceipts().first else { return AnyView(EmptyView()) }
      return AnyView(sheet(CleanSummary(receipt: receipt, done: {})))
    },
    "storage-result-problems": { _ in AnyView(sheet(CleanSummary(receipt: troubledReceipt, done: {}))) },
  ]

  private static func screen(_ state: StorageViewState, advice: StorageAdvice? = nil) -> AnyView {
    AnyView(NavigationStack { StorageScreen(state: state, advice: advice) })
  }

  private static func panel(_ inspector: FindingInspector) -> AnyView {
    AnyView(inspector.frame(width: 300).frame(maxHeight: .infinity, alignment: .top))
  }

  private static func sheet(_ content: some View) -> some View {
    content
      .frame(width: 440)
      .background(Color(nsColor: .windowBackgroundColor))
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
  }

  /// Advice as an assistant might give it, about the sample findings. `StorageAdvice`
  /// has no public initialiser, so it's decoded.
  private static func sampleAdvice(_ model: AppModel) -> StorageAdvice? {
    let findings = model.scan?.findings ?? []
    func id(_ prefix: String) -> String { findings.first { $0.title.hasPrefix(prefix) }?.id ?? prefix }
    func note(_ prefix: String, _ why: String) -> [String: String] { ["id": id(prefix), "why": why] }
    let object: [String: Any] = [
      "summary": "I’d clear about 46 GB: build data for projects you haven’t opened in over a month, an iOS 18 simulator system nothing uses and old package downloads. I left Atlas and Harbor alone because you built both this week.",
      "select": [
        note("Build data – Pocket Notes", "Not opened in three months."),
        note("Codex sessions", "Untouched since August."),
        note("Homebrew downloads", "Installers already unpacked."),
        note("Speech models", "MacWhisper hasn’t run in two months."),
      ],
      "deselect": [note("build – Atlas", "Built this morning."), note("Ollama models", "Used five days ago.")],
      "review": [note("CleanShot", "Mostly old recordings."), note("Sintel", "Not opened in ten months."), note("holiday-2025", "A second copy.")],
      "rejected": [
        note("Worktree – Harbor", "It has 3 uncommitted files, so only you can remove it."),
        note("holiday-2025", "Personal files are never selected for you."),
      ],
      "provider": "Claude",
      "escalated": false,
      "runID": "sample",
    ]
    guard let data = try? JSONSerialization.data(withJSONObject: object) else { return nil }
    return try? JSONDecoder().decode(StorageAdvice.self, from: data)
  }

  /// A clean where some things went to the Trash, one was skipped and one failed.
  private static var troubledReceipt: Receipt {
    func entry(_ title: String, _ category: StorageCategory, _ gigabytes: Double, _ outcome: RemovalOutcome) -> ReceiptEntry {
      ReceiptEntry(id: UUID().uuidString, title: title, category: category, paths: [], bytes: Int64(gigabytes * 1e9), outcome: outcome)
    }
    return Receipt(
      id: "sample-problems", date: Date(), initiator: .user, dryRun: false,
      entries: [
        entry("Build data – Lantern", .xcode, 31.2, .deleted),
        entry("Test simulators", .simulators, 25.1, .deleted),
        entry("CleanShot capture history", .largeFiles, 21.9, .trashed(locations: ["~/a": "~/.Trash/a"])),
        entry("Slack cache", .appCaches, 0.9, .skipped(reason: "Slack opened while the clean was running.")),
        entry("Simulator system · iOS 18.0", .simulators, 8.4, .failed(reason: "Xcode’s simulator tool didn’t answer within two minutes.")),
      ],
      freeBefore: 9_600_000_000, freeAfter: 65_900_000_000
    )
  }
}
