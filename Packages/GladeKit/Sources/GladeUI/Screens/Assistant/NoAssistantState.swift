import GladeKit
import SwiftUI

/// Shown when no AI is ready to answer. What each one needs is in Settings, so this
/// only points there and offers to look again.
struct NoAssistantState: View {
  @Environment(AppModel.self) private var model
  @Environment(\.openSettings) private var openSettings
  @State private var isChecking = false

  var body: some View {
    EmptyState("Connect an AI", symbol: Symbols.assistant) {
      HStack(spacing: Metrics.m) {
        Button("Check Again", systemImage: Symbols.scan) {
          isChecking = true
          Task {
            await model.refreshProviders()
            isChecking = false
          }
        }
        .secondaryAction()
        .disabled(isChecking)
        Button("Open Settings") {
          openSettings()
          Task {
            // Give the Settings window a moment to start listening.
            try? await Task.sleep(for: .milliseconds(300))
            NotificationCenter.default.post(name: .gladeShowAssistantSettings, object: nil)
          }
        }
        .principalAction()
      }
      .controlSize(.large)
    }
  }
}
