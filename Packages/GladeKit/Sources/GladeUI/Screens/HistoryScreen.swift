import GladeKit
import SwiftUI

/// Every clean Glade has done, newest first, grouped by day under what they freed in
/// total. Choosing one opens its receipt in the inspector, with the way back for
/// anything that went to the Trash.
struct HistoryScreen: View {
  @Environment(AppModel.self) private var model
  /// Only set when drawing snapshots.
  var previewReceipts: [Receipt]?
  @State private var selection: String?
  /// Follows the selection, except that closing it stays closed until another clean
  /// is chosen.
  @State private var showsReceipt: Bool

  init(selection: String? = nil, previewReceipts: [Receipt]? = nil) {
    _selection = State(initialValue: selection)
    _showsReceipt = State(initialValue: selection != nil)
    self.previewReceipts = previewReceipts
  }

  var body: some View {
    // Receipts come newest first; dry runs removed nothing, so they aren't history.
    let cleans = (previewReceipts ?? model.receipts).filter { !$0.dryRun }
    let selected = cleans.first { $0.id == selection }
    Group {
      if cleans.isEmpty {
        EmptyState("Nothing cleaned yet", symbol: AppModel.Section.history.symbol)
      } else {
        List(selection: $selection) {
          HistorySummary(cleans: cleans)
            .listRowSeparator(.hidden)
          ForEach(CleanDay.grouped(cleans)) { day in
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
        .onExitCommand {
          selection = nil
        }
      }
    }
    .navigationTitle("History")
    .toolbar {
      if !showsReceipt {
        ToolbarItem(placement: .primaryAction) {
          receiptButton
            .disabled(selected == nil)
        }
      }
    }
    .inspector(isPresented: $showsReceipt) {
      Group {
        if let selected {
          ReceiptDetail(receipt: selected)
            .id(selected.id)
        }
      }
      .inspectorColumnWidth(min: 320, ideal: 380)
      .toolbar {
        ToolbarSpacer(.flexible)
        ToolbarItem {
          receiptButton
        }
      }
    }
    .onChange(of: selection) { old, new in
      if new == nil {
        showsReceipt = false
      } else if new != old {
        showsReceipt = true
      }
    }
  }

  /// Shows or hides the receipt. It sits at the far trailing edge, above the
  /// inspector when that's open.
  private var receiptButton: some View {
    Button {
      showsReceipt.toggle()
    } label: {
      Label(showsReceipt ? "Hide Receipt" : "Show Receipt", systemImage: Symbols.inspector)
    }
    .keyboardShortcut("i", modifiers: [.command, .option])
    .help(showsReceipt ? "Hide Receipt" : "Show Receipt")
  }
}
