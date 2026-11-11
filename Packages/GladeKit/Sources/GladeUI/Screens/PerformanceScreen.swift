import GladeKit
import SwiftUI

struct PerformanceScreen: View {
  @Environment(AppModel.self) private var model

  var body: some View {
    EmptyState("Performance", symbol: AppModel.Section.performance.symbol)
      .navigationTitle("Performance")
  }
}
