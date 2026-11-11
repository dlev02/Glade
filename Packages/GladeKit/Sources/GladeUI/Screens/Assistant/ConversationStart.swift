import GladeKit
import SwiftUI

/// A new conversation: who will answer, and a few questions to start with.
struct ConversationStart: View {
  @Environment(AppModel.self) private var model
  var provider: ProviderStatus

  private static let suggestions = [
    ["Free up 30 GB", "Why is my Mac slow right now?"],
    ["What’s using my memory?", "What’s safe to remove?"],
  ]

  var body: some View {
    VStack(spacing: Metrics.xl) {
      VStack(spacing: Metrics.m) {
        Image(systemName: "sparkles")
          .font(.largeTitle)
          .foregroundStyle(.tint)
          .accessibilityHidden(true)
        Text("Ask \(provider.name) about this Mac")
          .font(.title2.weight(.semibold))
          .multilineTextAlignment(.center)
      }
      VStack(spacing: Metrics.s) {
        ForEach(Self.suggestions, id: \.self) { row in
          HStack(spacing: Metrics.s) {
            ForEach(row, id: \.self) { question in
              Button(question) { Task { await model.ask(question) } }
                .buttonStyle(.bordered)
                .buttonBorderShape(.capsule)
                .controlSize(.large)
            }
          }
        }
      }
    }
    .padding(Metrics.xl)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }
}
