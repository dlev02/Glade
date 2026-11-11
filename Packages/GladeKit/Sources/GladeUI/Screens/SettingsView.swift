import GladeKit
import SwiftUI

struct SettingsView: View {
  @Environment(AppModel.self) private var model

  var body: some View {
    Text("Settings")
      .frame(width: 520, height: 360)
  }
}
