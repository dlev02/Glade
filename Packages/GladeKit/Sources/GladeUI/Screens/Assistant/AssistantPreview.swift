import GladeKit

/// Stand-ins for the model’s read-only assistant state, so snapshots can draw states
/// (thinking, an answer with advice, no AI ready) that only a real run would produce.
/// The running app never sets one.
struct AssistantPreview {
  var messages: [AppModel.Message]?
  var state: AppModel.AssistantState?
  var providers: [ProviderStatus]?
  var runs: [AssistantRun]?
  /// Whether the advice in `messages` still describes the selection.
  var adviceIsLive: Bool?
}
