import GladeKit
import SwiftUI

struct SetupView: View {
  @Environment(AppModel.self) private var model

  var body: some View {
    VStack(spacing: Metrics.l) {
      Text("Set Up \(Brand.name)").font(.title2.bold())
      Button("Done") { model.finishSetup() }
        .keyboardShortcut(.defaultAction)
    }
    .padding(Metrics.xxl)
    .frame(width: 520, height: 360)
  }
}
