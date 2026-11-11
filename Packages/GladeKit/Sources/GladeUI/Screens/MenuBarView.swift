import GladeKit
import SwiftUI

struct MenuBarView: View {
  @Environment(AppModel.self) private var model

  var body: some View {
    Text(Brand.name)
      .padding()
      .frame(width: 320)
  }
}
