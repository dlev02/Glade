import Foundation
import GladeKit

/// Requests to remove something the person names: the Assistant’s proposal in the
/// conversation, the ticks on it, and the clean that confirms it. Nothing is removed
/// from here; the ticked items go through the usual confirmation sheet and `Cleaner`.
extension AppModel {
  /// Asks for a proposal and adds it to the conversation under the answer.
  func proposeRemoval(_ text: String) async {
    guard let scan else {
      messages.append(Message(
        role: .assistant,
        text: "\(Brand.name) hasn’t looked at this Mac’s storage yet, so it doesn’t know what’s here to remove. Scan in **Storage**, then ask again."
      ))
      return
    }
    assistantState = .thinking("Looking for what you named…")
    // Sample data is never sent to a real AI; a made-up proposal arrives instead.
    if isDemo {
      try? await Task.sleep(for: .seconds(2.5))
      let sample = SampleData.sampleProposal(scan: scan, request: text)
      messages.append(Message(role: .assistant, text: sample.answer, provider: sample.provider, model: sample.model, proposal: ProposalState(sample)))
      assistantState = .idle
      return
    }
    await refreshApps()
    let description = MacDescription.build(
      snapshot: snapshot, apps: apps, context: context, suggestions: suggestions, scan: scan, plan: plan
    )
    do {
      let proposal = try await Assistant.propose(
        text, scan: scan, snapshot: description, config: config, providers: AgentProviders.all
      ) { [weak self] reviewer in
        Task { @MainActor in
          guard let self, case .thinking = self.assistantState else { return }
          self.assistantState = .thinking("Asking \(reviewer) for a second opinion…")
        }
      }
      let card = proposal.items.isEmpty && proposal.rejected.isEmpty ? nil : ProposalState(proposal)
      messages.append(Message(role: .assistant, text: proposal.answer, provider: proposal.provider, model: proposal.model, proposal: card))
      assistantState = .idle
    } catch {
      messages.append(Message(role: .problem, text: error.localizedDescription))
      assistantState = .failed(error.localizedDescription)
    }
  }

  // MARK: The card

  /// The finding behind a proposed item in the scan as it is now, or `nil` when a newer
  /// scan or a clean no longer has it.
  func proposedFinding(_ id: String) -> Finding? {
    scan?.finding(id)
  }

  /// What can be done with an item now, worked out again from the scan as it is (an app
  /// quit since, a newer scan), or `nil` when the scan no longer has it.
  func currentAction(of item: RemovalProposal.Item) -> RemovalProposal.Action? {
    proposedFinding(item.id).map { RemovalProposal.item(for: $0, why: "", named: false).action }
  }

  /// Whether the person can tick an item: it can be removed here and is still in the scan.
  func canTick(_ item: RemovalProposal.Item) -> Bool {
    currentAction(of: item) == .remove
  }

  func setTicked(_ ticked: Bool, item id: String, in message: UUID) {
    guard let index = messages.firstIndex(where: { $0.id == message }), var card = messages[index].proposal else { return }
    if ticked {
      guard let item = card.proposal.items.first(where: { $0.id == id }), canTick(item) else { return }
      card.ticks.insert(id)
    } else {
      card.ticks.remove(id)
    }
    messages[index].proposal = card
  }

  /// The ticked items that can still be removed.
  func tickedItems(_ card: ProposalState) -> [RemovalProposal.Item] {
    card.proposal.items.filter { card.ticks.contains($0.id) && canTick($0) }
  }

  /// Gets the clean sheet ready with the card’s ticked items. Returns false when none of
  /// them can be removed any more, so there is nothing to confirm.
  func reviewRemoval(in message: UUID) -> Bool {
    guard let index = messages.firstIndex(where: { $0.id == message }), let card = messages[index].proposal else { return false }
    let ids = tickedItems(card).map(\.id)
    guard !ids.isEmpty, !isCleaning else { return false }
    focusClean(on: ids)
    guard !cleanItems.isEmpty else {
      endCleanFocus()
      return false
    }
    for other in messages.indices where messages[other].proposal?.awaitingClean == true {
      messages[other].proposal?.awaitingClean = false
    }
    messages[index].proposal?.awaitingClean = true
    Log.info(.app, "Reviewing \(ids.count) proposed items before removing them")
    return true
  }

  /// The clean sheet closed: a card waiting on it stops waiting.
  func endRemovalReview() {
    for index in messages.indices where messages[index].proposal?.awaitingClean == true {
      messages[index].proposal?.awaitingClean = false
    }
    endCleanFocus()
  }

  /// A clean finished: if it was a card’s, the card records what happened.
  func proposalCleanFinished(_ receiptID: String) {
    guard let index = messages.firstIndex(where: { $0.proposal?.awaitingClean == true }),
          var card = messages[index].proposal, let receipt = receipt(receiptID) else { return }
    var removed: [String: Bool] = [:]
    var stayed: [String: String] = [:]
    var bytes: Int64 = 0
    let proposed = Set(card.proposal.items.map(\.id))
    for entry in receipt.entries where proposed.contains(entry.id) {
      switch entry.outcome {
      case .trashed:
        removed[entry.id] = true
        bytes += entry.bytes
      case .deleted:
        removed[entry.id] = false
        bytes += entry.bytes
      case .skipped(let reason), .failed(let reason):
        stayed[entry.id] = reason
      case .wouldRemove:
        break
      }
    }
    card.ticks.subtract(removed.keys)
    card.outcome = ProposalState.Outcome(receiptID: receiptID, removed: removed, stayed: stayed, bytes: bytes)
    card.awaitingClean = false
    messages[index].proposal = card
  }

  /// Puts back what the card’s clean moved to the Trash.
  func putBackRemoval(in message: UUID) {
    guard let index = messages.firstIndex(where: { $0.id == message }),
          let outcome = messages[index].proposal?.outcome, let receipt = receipt(outcome.receiptID) else { return }
    let result = putBack(receipt)
    Log.info(.app, "Put back \(result.restored.count) items from a proposal; \(result.missing.count) missing, \(result.blocked.count) blocked")
    messages[index].proposal?.outcome?.putBack = true
  }
}
