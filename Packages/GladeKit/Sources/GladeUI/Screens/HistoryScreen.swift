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
    // Receipts come newest first; dry runs removed nothing, so they aren’t history.
    let cleans = (previewReceipts ?? model.receipts).filter { !$0.dryRun }
    let selected = cleans.first { $0.id == selection }
    Group {
      if cleans.isEmpty {
        EmptyState("Nothing cleaned yet", symbol: AppModel.Section.history.symbol)
      } else {
        ScrollView {
          LazyVStack(alignment: .leading, spacing: 0) {
            HistorySummary(cleans: cleans)
              .padding(.horizontal, Metrics.s)
            ForEach(CleanDay.grouped(cleans)) { day in
              Text(day.title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, Metrics.s)
                .padding(.top, Metrics.l)
                .padding(.bottom, Metrics.xs)
                .accessibilityAddTraits(.isHeader)
              ForEach(day.receipts) { receipt in
                HistoryRow(receipt: receipt, isSelected: selection == receipt.id) {
                  selection = receipt.id
                }
              }
            }
          }
          // Narrower than Overview, so a clean’s size sits near its name, and centred
          // once the window is wider than that.
          .frame(maxWidth: Metrics.listWidth, alignment: .leading)
          .padding(.horizontal, Metrics.l)
          .padding(.vertical, Metrics.m)
          .frame(maxWidth: .infinity)
        }
        .focusable()
        .focusEffectDisabled()
        .onKeyPress(.downArrow) { move(1, in: cleans) }
        .onKeyPress(.upArrow) { move(-1, in: cleans) }
        .onExitCommand {
          selection = nil
        }
      }
    }
    .navigationTitle("History")
    .toolbar {
      // Declared once, so it never appears twice or moves when the receipt opens.
      ToolbarItem(placement: .primaryAction) {
        receiptButton
          .disabled(selected == nil)
      }
    }
    .inspector(isPresented: $showsReceipt) {
      Group {
        if let selected {
          ReceiptDetail(receipt: selected)
            .id(selected.id)
        }
      }
      .inspectorBackground()
      .inspectorColumnWidth(min: 300, ideal: 320, max: 440)
    }
    .task {
      // `-demoReceipt first` opens the newest clean’s receipt.
      guard DemoState.value("demoReceipt") != nil else { return }
      // Sample receipts arrive a moment after launch.
      for _ in 0..<20 where selection == nil {
        try? await Task.sleep(for: .milliseconds(500))
        selection = (previewReceipts ?? model.receipts).first { !$0.dryRun }?.id
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

  /// Moves the selection with the arrow keys, in the list’s order.
  private func move(_ step: Int, in cleans: [Receipt]) -> KeyPress.Result {
    let ordered = CleanDay.grouped(cleans).flatMap(\.receipts)
    guard !ordered.isEmpty else { return .ignored }
    let index = ordered.firstIndex { $0.id == selection } ?? (step > 0 ? -1 : ordered.count)
    selection = ordered[min(max(index + step, 0), ordered.count - 1)].id
    return .handled
  }

  /// Shows or hides the receipt. It sits at the far trailing edge, above the
  /// inspector when that’s open.
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
