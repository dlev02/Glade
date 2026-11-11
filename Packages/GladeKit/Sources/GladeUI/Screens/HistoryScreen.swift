import GladeKit
import SwiftUI

struct HistoryScreen: View {
  @Environment(AppModel.self) private var model

  var body: some View {
    EmptyState("History", symbol: AppModel.Section.history.symbol)
      .navigationTitle("History")
  }
}
