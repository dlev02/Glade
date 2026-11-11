import GladeKit
import SwiftUI

/// A conversation with the person's own AI about this Mac. The AI has no tools: Glade
/// describes the Mac to it and checks whatever it suggests against the safety rules.
struct AssistantScreen: View {
  @Environment(AppModel.self) private var model
  /// Only set when drawing snapshots.
  var preview: AssistantPreview?
  @State private var showsRuns = false

  var body: some View {
    let messages = preview?.messages ?? model.messages
    let state = preview?.state ?? model.assistantState
    let providers = preview?.providers ?? model.providers
    let active = preview?.providers == nil ? model.activeProvider : providers.first(where: \.isReady)

    content(messages: messages, state: state, providers: providers, active: active)
      .navigationTitle("Assistant")
      .toolbar {
        ToolbarItemGroup {
          Button("New Conversation", systemImage: "square.and.pencil") { model.clearConversation() }
            .help("New Conversation")
            .disabled(messages.isEmpty)
          Button("Show What Was Sent", systemImage: "text.page.badge.magnifyingglass") { showsRuns = true }
            .help("Show What Was Sent")
        }
      }
      .sheet(isPresented: $showsRuns) {
        RunsSheet()
      }
  }

  @ViewBuilder
  private func content(
    messages: [AppModel.Message], state: AppModel.AssistantState, providers: [ProviderStatus], active: ProviderStatus?
  ) -> some View {
    if providers.isEmpty {
      ProgressView()
        .controlSize(.small)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    } else if let active {
      let isThinking = if case .thinking = state { true } else { false }
      Group {
        if messages.isEmpty && !isThinking {
          ConversationStart(provider: active)
        } else {
          ConversationView(messages: messages, state: state)
        }
      }
      .safeAreaInset(edge: .bottom, spacing: 0) {
        Composer(active: active, ready: providers.filter(\.isReady), isBusy: isThinking)
      }
    } else {
      NoAssistantState(providers: providers)
    }
  }
}
