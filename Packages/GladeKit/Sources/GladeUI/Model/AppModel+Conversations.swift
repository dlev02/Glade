import Foundation
import GladeKit

/// Saved conversations: each is kept as it goes, and any can be opened again, renamed,
/// pinned to the top or deleted.
extension AppModel {
  func loadConversations() async {
    savedConversations = await Task.detached {
      ConversationStore.prune()
      return ConversationStore.all()
    }.value
  }

  /// Saves the conversation on screen. Sample data is never saved.
  func keepConversation() {
    guard !isDemo, messages.contains(where: { $0.role == .person }) else { return }
    let existing = savedConversations.first { $0.id == conversationID }
    var saved = SavedConversation(id: conversationID, name: existing?.name, pinned: existing?.pinned ?? false)
    saved.turns = messages.map { message in
      SavedConversation.Turn(role: message.role.saved, text: message.text, date: message.date, provider: message.provider, model: message.model)
    }
    guard saved != existing else { return }
    ConversationStore.save(saved)
    savedConversations.removeAll { $0.id == saved.id }
    savedConversations.append(saved)
    sortConversations()
  }

  /// Whether another conversation may be opened: not while an answer is on its way,
  /// which would land in the wrong one.
  public var canSwitchConversation: Bool {
    if case .thinking = assistantState { return false }
    return true
  }

  public func openConversation(_ id: UUID) {
    guard canSwitchConversation, id != conversationID,
          let saved = savedConversations.first(where: { $0.id == id }) ?? ConversationStore.load(id)
    else { return }
    conversationID = id
    assistantState = .idle
    messages = saved.turns.map { turn in
      var message = Message(role: turn.role.message, text: turn.text, provider: turn.provider, model: turn.model)
      message.date = turn.date
      return message
    }
  }

  public func renameConversation(_ id: UUID, to name: String) {
    update(id) { $0.name = name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : name.trimmingCharacters(in: .whitespacesAndNewlines) }
  }

  public func setPinned(_ id: UUID, _ pinned: Bool) {
    update(id) { $0.pinned = pinned }
  }

  public func deleteConversation(_ id: UUID) {
    ConversationStore.delete(id)
    savedConversations.removeAll { $0.id == id }
    if id == conversationID { clearConversation() }
  }

  private func update(_ id: UUID, _ change: (inout SavedConversation) -> Void) {
    guard let index = savedConversations.firstIndex(where: { $0.id == id }) else { return }
    change(&savedConversations[index])
    ConversationStore.save(savedConversations[index])
    sortConversations()
  }

  private func sortConversations() {
    savedConversations.sort { ($0.pinned ? 1 : 0, $0.updated) > ($1.pinned ? 1 : 0, $1.updated) }
  }
}

extension AppModel {
  /// Made-up earlier conversations for screenshots; never the person’s own.
  static func sampleConversations(now: Date = Date()) -> [SavedConversation] {
    func turns(_ question: String, _ answer: String, hoursAgo: Double, provider: String) -> [SavedConversation.Turn] {
      let date = now.addingTimeInterval(-hoursAgo * 3_600)
      return [
        .init(role: .person, text: question, date: date),
        .init(role: .assistant, text: answer, date: date.addingTimeInterval(20), provider: provider),
      ]
    }
    return [
      SavedConversation(name: "Wi-Fi drops in the evening", pinned: true, turns: turns("Why does my Wi-Fi drop every evening?", "The delay starts between this Mac and the router.", hoursAgo: 70, provider: "claude")),
      SavedConversation(turns: turns("What’s using my memory?", "Simulator devices use the most.", hoursAgo: 1, provider: "claude")),
      SavedConversation(turns: turns("Free 20 GB", "A Balanced clean frees 21 GB.", hoursAgo: 5, provider: "codex")),
      SavedConversation(turns: turns("Is my battery healthy?", "It holds 91% of its original charge.", hoursAgo: 30, provider: "apple")),
      SavedConversation(turns: turns("Which apps haven’t I opened this year?", "Seven apps, 38 GB together.", hoursAgo: 120, provider: "claude")),
      SavedConversation(turns: turns("Review my Little Snitch rules", "155 rules belong to apps that are gone.", hoursAgo: 400, provider: "codex")),
    ].sorted { ($0.pinned ? 1 : 0, $0.updated) > ($1.pinned ? 1 : 0, $1.updated) }
  }
}

extension AppModel.Message.Role {
  var saved: SavedConversation.Turn.Role {
    switch self {
    case .person: .person
    case .assistant: .assistant
    case .problem: .problem
    }
  }
}

extension SavedConversation.Turn.Role {
  var message: AppModel.Message.Role {
    switch self {
    case .person: .person
    case .assistant: .assistant
    case .problem: .problem
    }
  }
}
