import GladeKit
import SwiftUI

struct StorageScreen: View {
  @Environment(AppModel.self) private var model

  var body: some View {
    EmptyState("Storage", symbol: AppModel.Section.storage.symbol)
      .navigationTitle("Storage")
  }
}
