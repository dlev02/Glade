import GladeKit
import SwiftUI

/// A conversation with the person's own AI about this Mac. The AI has no tools: Glade
/// describes the Mac to it and checks whatever it suggests against the safety rules.
struct AssistantScreen: View {
  @Environment(AppModel.self) private var model
  /// Only set when drawing snapshots.
  var preview: AssistantPreview?
  @State private var showsDetails: Bool
  /// Every recorded run, newest first; `nil` until read.
  @State private var runs: [AssistantRun]?
  /// The run shown in full in a sheet.
  @State private var shownRun: AssistantRun?

  init(preview: AssistantPreview? = nil, showsDetails: Bool = false) {
    self.preview = preview
    _showsDetails = State(initialValue: showsDetails)
    _runs = State(initialValue: preview?.runs)
  }

  var body: some View {
    let messages = preview?.messages ?? model.messages
    let state = preview?.state ?? model.assistantState
    let providers = preview?.providers ?? model.providers
    let active = preview?.providers == nil ? model.activeProvider : providers.first(where: \.isReady)

    content(messages: messages, state: state, providers: providers, active: active)
      .navigationTitle("Assistant")
      .toolbar {
        ToolbarItem(placement: .primaryAction) {
          Button("New Conversation", systemImage: Symbols.newConversation) { model.clearConversation() }
            .accessibilityIdentifier("toolbar.newConversation")
            .help("New Conversation")
            .keyboardShortcut("n")
            .disabled(messages.isEmpty)
        }
        // Declared once in the main toolbar, its own capsule at the trailing edge, the
        // same as Storage's and History's inspector buttons.
        ToolbarSpacer(.fixed, placement: .primaryAction)
        ToolbarItem(placement: .primaryAction) {
          Button("Details", systemImage: Symbols.inspector) { showsDetails.toggle() }
            .accessibilityIdentifier("toolbar.details")
            .accessibilityValue(showsDetails ? "Shown" : "Hidden")
            .help("Show What Was Sent")
            .keyboardShortcut("i", modifiers: [.command, .option])
        }
      }
      .inspector(isPresented: $showsDetails) {
        RunsInspector(runs: runs) { shownRun = $0 }
          .inspectorBackground()
          .inspectorColumnWidth(min: 260, ideal: 300, max: 400)
      }
      .sheet(item: $shownRun) { run in
        RunSheet(run: run)
      }
      .task(id: messages.count) {
        guard preview?.runs == nil else { return }
        await loadRuns()
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
          ConversationStart()
        } else {
          ConversationView(
            messages: messages, state: state, chosen: active,
            isLive: { advice in preview?.adviceIsLive ?? model.isLive(advice) }
          ) { message in
            Task { await showRun(for: message) }
          }
        }
      }
      .safeAreaInset(edge: .bottom, spacing: 0) {
        Composer(active: active, ready: providers.filter(\.isReady), isBusy: isThinking)
      }
    } else {
      NoAssistantState()
    }
  }

  private func loadRuns() async {
    // Reading the records touches files, so keep it off the main thread.
    runs = await Task.detached { Assistant.runs() }.value
  }

  /// Opens the run behind an answer: the one its advice names, or else the newest run
  /// that started before the answer arrived.
  private func showRun(for message: AppModel.Message) async {
    await loadRuns()
    let runs = runs ?? []
    let run = message.advice.flatMap { advice in runs.first { $0.id == advice.runID } }
      ?? runs.first { $0.date <= message.date }
    if let run {
      shownRun = run
    } else {
      showsDetails = true
    }
  }
}
