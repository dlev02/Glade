import GladeKit
import SwiftUI

/// The first time Network opens: the two things macOS asks about, with why. Everything
/// else works either way.
struct NetworkSetupCard: View {
  @Environment(AppModel.self) private var model

  var body: some View {
    Card {
      VStack(alignment: .leading, spacing: Metrics.m) {
        row(
          symbol: "location", title: "Wi-Fi Network Names",
          detail: "macOS counts your Wi-Fi network’s name as location. With it, Glade tells your networks apart in Data Used. It never reads where you are."
        ) {
          Button("Allow…") { model.requestLocation() }
        }
        Divider()
        row(
          symbol: "wifi.router", title: "Your Router",
          detail: "macOS will ask to let Glade find devices on your local network, so it can ping your router and read its status."
        ) {
          EmptyView()
        }
        HStack {
          Spacer()
          Button("Done") { model.networkSetupAsked = true }
        }
      }
    }
  }

  private func row<Action: View>(symbol: String, title: String, detail: String, @ViewBuilder action: () -> Action) -> some View {
    HStack(alignment: .top, spacing: Metrics.m) {
      Image(systemName: symbol)
        .font(.title3)
        .foregroundStyle(.tint)
        .frame(width: 28)
        .accessibilityHidden(true)
      VStack(alignment: .leading, spacing: 2) {
        Text(title).fontWeight(.medium)
        Text(detail)
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
      }
      Spacer(minLength: Metrics.m)
      action()
    }
    .font(.callout)
  }
}
