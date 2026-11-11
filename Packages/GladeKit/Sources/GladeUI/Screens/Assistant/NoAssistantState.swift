import GladeKit
import SwiftUI

/// Shown when no AI is ready to answer: what Glade found, what each one needs, and a
/// way to look again.
struct NoAssistantState: View {
  @Environment(AppModel.self) private var model
  var providers: [ProviderStatus]
  @State private var isChecking = false

  var body: some View {
    let detected = providers.filter { $0.state != .notInstalled }
    let missing = providers.filter { $0.state == .notInstalled }.map(\.name)
    EmptyState("No AI connected", symbol: "sparkles") {
      VStack(spacing: Metrics.l) {
        if !detected.isEmpty || !missing.isEmpty {
          Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: Metrics.m, verticalSpacing: Metrics.s) {
            ForEach(detected) { provider in
              GridRow {
                Text(provider.name)
                Text(need(provider.state))
                  .foregroundStyle(.secondary)
                  .fixedSize(horizontal: false, vertical: true)
              }
            }
            if !missing.isEmpty {
              GridRow {
                Text("Not installed")
                Text(missing.formatted(.list(type: .and)))
                  .foregroundStyle(.secondary)
                  .fixedSize(horizontal: false, vertical: true)
              }
            }
          }
          .font(.callout)
          .frame(width: 460, alignment: .leading)
          .padding(Metrics.l)
          .background(Palette.card, in: .rect(cornerRadius: Metrics.cardRadius))
          .overlay {
            RoundedRectangle(cornerRadius: Metrics.cardRadius)
              .strokeBorder(Palette.hairline.opacity(0.6), lineWidth: Metrics.hairline)
          }
        }
        HStack(spacing: Metrics.m) {
          SettingsLink {
            Text("Open Settings")
          }
          Button("Check Again", systemImage: "arrow.clockwise") {
            isChecking = true
            Task {
              await model.refreshProviders()
              isChecking = false
            }
          }
          .disabled(isChecking)
        }
      }
    }
  }

  private func need(_ state: ProviderStatus.State) -> String {
    switch state {
    case .ready: "Ready"
    case .notInstalled: "Not installed"
    case .needsSignIn(let hint): hint
    case .unavailable(let reason): reason
    }
  }
}
