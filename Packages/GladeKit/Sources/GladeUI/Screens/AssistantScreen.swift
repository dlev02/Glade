import GladeKit
import SwiftUI

struct AssistantScreen: View {
  @Environment(AppModel.self) private var model

  var body: some View {
    EmptyState("Assistant", symbol: AppModel.Section.assistant.symbol)
      .navigationTitle("Assistant")
  }
}
