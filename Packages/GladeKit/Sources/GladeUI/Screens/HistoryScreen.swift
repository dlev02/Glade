import GladeKit
import SwiftUI

/// Every clean Glade has done, newest first, grouped by day, with the way back for
/// anything that went to the Trash.
struct HistoryScreen: View {
  @Environment(AppModel.self) private var model
  /// Only set when drawing snapshots.
  var previewReceipts: [Receipt]?
  @State private var selection: String?

  init(selection: String? = nil, previewReceipts: [Receipt]? = nil) {
    _selection = State(initialValue: selection)
    self.previewReceipts = previewReceipts
  }

  var body: some View {
    // Receipts come newest first; dry runs removed nothing, so they aren't history.
    let cleans = (previewReceipts ?? model.receipts).filter { !$0.dryRun }
    Group {
      if cleans.isEmpty {
        EmptyState("Nothing cleaned yet", symbol: AppModel.Section.history.symbol)
      } else {
        HStack(spacing: 0) {
          List(selection: $selection) {
            ForEach(CleanDay.group(cleans)) { day in
              Section(day.title) {
                ForEach(day.receipts) { receipt in
                  ReceiptRow(receipt: receipt)
                    .tag(receipt.id)
                    .listRowSeparator(.hidden)
                }
              }
              .listSectionSeparator(.hidden)
            }
          }
          .frame(width: 300)
          Divider()
          if let receipt = cleans.first(where: { $0.id == selection }) {
            ReceiptDetail(receipt: receipt)
              .id(receipt.id)
          } else {
            HistorySummary(cleans: cleans)
          }
        }
      }
    }
    .navigationTitle("History")
  }
}
