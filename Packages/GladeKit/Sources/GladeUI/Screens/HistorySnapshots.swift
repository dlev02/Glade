import GladeKit
import SwiftUI

/// The History screens that can be drawn to an image with `glade snapshot <name>`.
/// Add an entry for each state worth checking: empty, busy, a sheet, an error.
enum HistorySnapshots {
  static let all: [String: (AppModel) -> AnyView] = [
    "history": { _ in AnyView(NavigationStack { HistoryScreen() }) },
    "history-selected": { model in
      AnyView(NavigationStack { HistoryScreen(selection: model.receipts.first?.id) })
    },
    "history-empty": { _ in AnyView(NavigationStack { HistoryScreen(previewReceipts: []) }) },
    // The receipt on its own, at the inspector’s width (`--width 380`).
    "history-receipt": { model in
      guard let receipt = model.receipts.first(where: { !$0.dryRun }) else { return AnyView(EmptyView()) }
      return AnyView(ReceiptDetail(receipt: receipt))
    },
    "history-min": { model in
      model.section = .history
      return AnyView(RootView())
    },
  ]
}
