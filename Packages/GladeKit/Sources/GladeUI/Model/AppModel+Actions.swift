import Foundation
import GladeKit

/// The Assistant acting on this Mac: what it may propose for a question, how the
/// person’s choice in Settings › Assistant › Actions decides what runs by itself, and
/// carrying actions out through Glade’s own code. `ActionPolicy` makes every decision;
/// this only follows it.
extension AppModel {
  /// What Glade offers the Assistant for this question, from the readings just taken.
  func offeredActions(for question: String) async -> [AgentAction] {
    let path = isDemo ? nil : await NetworkPath.current()
    return ActionCatalogue.offer(.init(
      question: question, apps: apps, relief: reliefPlan, scan: scan, config: config,
      lastReceipt: receipts.first { !$0.dryRun }, limitedConnection: path?.isLimited ?? !isDemo,
      speedTestRan: speedTestRanInConversation, speedTestBytes: speedTestEstimate
    ))
  }

  /// A speed test already ran from an answer in this conversation.
  var speedTestRanInConversation: Bool {
    messages.contains { message in
      guard let card = message.actions else { return false }
      return card.actions.contains { $0.kind == .speedTest && card.status[$0.id]?.isDone == true }
    }
  }

  // MARK: Deciding

  /// Decides each proposed action under the person’s mode, asking the second opinion
  /// first in Auto, then runs what may run.
  func settleActions(in message: UUID) async {
    guard var card = actionCard(message) else { return }
    let mode = card.mode
    var reviewerIsProposer = false
    if mode == .auto {
      let candidates = card.actions.filter { $0.eligible && ($0.tier == .undoable || $0.tier == .harder) }
      if !candidates.isEmpty {
        for action in candidates { card.status[action.id] = .checking }
        setActionCard(card, in: message)
        assistantState = .thinking("Getting a second opinion on what to do…")
        let review: Assistant.ActionReview
        if isDemo {
          try? await Task.sleep(for: .seconds(1.5))
          review = Assistant.ActionReview(
            reviews: Dictionary(uniqueKeysWithValues: candidates.map { ($0.id, ActionPolicy.Review.approve) }),
            reviewer: "codex", reviewerIsProposer: false
          )
        } else {
          review = await Assistant.reviewActions(candidates, request: card.request, proposer: card.proposer, config: config, providers: AgentProviders.all)
        }
        assistantState = .idle
        guard var latest = actionCard(message) else { return }
        latest.reviewer = review.reviewer
        latest.reviews = review.reviews
        reviewerIsProposer = review.reviewerIsProposer
        card = latest
      }
    }
    let decisions = ActionPolicy.decideAll(card.actions, mode: mode, reviews: card.reviews, reviewerIsProposer: reviewerIsProposer)
    for action in card.actions {
      if case .wait(let why)? = decisions[action.id] { card.status[action.id] = .waiting(why) }
    }
    setActionCard(card, in: message)
    let running = card.actions.filter { decisions[$0.id]?.runs == true }
    Log.info(.agent, "Proposed actions under \(mode.title): \(running.count) run by themselves, \(card.actions.count - running.count) wait")
    for action in running { await run(action, in: message, byThemselves: true) }
    await explainResults(in: message)
  }

  // MARK: The person’s buttons

  func approveAction(_ id: String, in message: UUID) async {
    guard let card = actionCard(message), card.status[id]?.isWaiting == true, let action = card.actions.first(where: { $0.id == id }) else { return }
    Log.info(.agent, "The person approved \(action.kind.rawValue)")
    await run(action, in: message, byThemselves: false)
    await explainResults(in: message)
  }

  func approveAllActions(in message: UUID) async {
    guard let card = actionCard(message) else { return }
    for action in card.waiting { await run(action, in: message, byThemselves: false) }
    await explainResults(in: message)
  }

  func declineAction(_ id: String, in message: UUID) {
    guard var card = actionCard(message), card.status[id]?.isWaiting == true else { return }
    card.status[id] = .declined
    setActionCard(card, in: message)
  }

  /// Puts back what an action’s clean moved to the Trash.
  func putBackAction(_ id: String, in message: UUID) {
    guard var card = actionCard(message), let receiptID = card.receipts[id], let receipt = receipt(receiptID) else { return }
    let result = putBack(receipt)
    Log.info(.app, "Put back \(result.restored.count) items from an Assistant clean; \(result.missing.count) missing")
    card.putBack.insert(id)
    setActionCard(card, in: message)
  }

  // MARK: Carrying out

  private func run(_ action: AgentAction, in message: UUID, byThemselves: Bool) async {
    guard var card = actionCard(message) else { return }
    card.status[action.id] = .running
    setActionCard(card, in: message)
    let outcome = await perform(action, provider: card.proposer)
    guard var latest = actionCard(message) else { return }
    latest.status[action.id] = outcome.ok ? .done(outcome.text) : .failed(outcome.text)
    if let receiptID = outcome.receiptID { latest.receipts[action.id] = receiptID }
    if byThemselves { latest.ranByThemselves.insert(action.id) }
    setActionCard(latest, in: message)
  }

  /// Does one action through the code that already does it in the window. Every check
  /// those make (an app now in front, a finding changed) is made again here.
  private func perform(_ action: AgentAction, provider: String) async -> (ok: Bool, text: String, receiptID: String?) {
    switch action.kind {
    case .quit, .relaunch, .shutDownSimulator, .freeUpMemory:
      let result = isDemo ? await simulateRelief(action.relief) : await ReliefResult.perform(action.relief, config: config)
      if !isDemo { await refreshApps() }
      let done = result.entries.filter(\.outcome.succeeded)
      let notDone = result.problems.map { "\($0.name): \($0.detail ?? "not done")" }
      var text = done.isEmpty ? "" : "Memory in use went down by \(Format.bytes(result.measuredFreedBytes))."
      if !notDone.isEmpty { text += (text.isEmpty ? "" : " ") + notDone.joined(separator: "; ") + "." }
      return (!done.isEmpty, text, nil)
    case .restartHelper:
      if isDemo { return (true, "Sample data: nothing was restarted.", nil) }
      await refreshApps()
      guard let id = action.helperBundleID, let app = apps.first(where: { $0.bundleIdentifier?.lowercased() == id.lowercased() }) else {
        return (false, "It isn’t running any more.", nil)
      }
      do {
        let result = try await AppControl.restartHelper(id, memoryBytes: app.memoryBytes)
        try? await Task.sleep(for: .seconds(2))
        await refreshApps()
        return (result.exited, result.message + (result.exited ? " It was using \(Format.bytes(app.memoryBytes))." : ""), nil)
      } catch {
        return (false, error.localizedDescription, nil)
      }
    case .cleanCareful, .cleanBalanced:
      guard let scan, scan.id == action.scanID else { return (false, "The storage scan has changed since; ask again.", nil) }
      if isDemo { return (true, "Sample data: nothing was removed.", nil) }
      guard let receipt = await assistantClean(ids: action.findingIDs, provider: provider) else {
        return (false, "The clean didn’t run.", nil)
      }
      let freed = receipt.entries.reduce(Int64(0)) { $0 + ($1.outcome == .deleted ? $1.bytes : 0) }
      var trashed: Int64 = 0
      var stayed = 0
      for entry in receipt.entries {
        switch entry.outcome {
        case .trashed: trashed += entry.bytes
        case .skipped, .failed: stayed += 1
        default: break
        }
      }
      var text = "Freed \(Format.bytes(freed))"
      if trashed > 0 { text += "; \(Format.bytes(trashed)) went to the Trash" }
      text += "."
      if stayed > 0 { text += " \(stayed) stayed, because they were in use or had changed." }
      return (freed + trashed > 0, text, trashed > 0 ? receipt.id : nil)
    case .putBack:
      guard let id = action.receiptID, let receipt = receipt(id) else { return (false, "That clean’s record is gone.", nil) }
      let result = putBack(receipt)
      return (!result.restored.isEmpty, "Put back \(result.restored.count) items" + (result.missing.isEmpty ? "." : "; \(result.missing.count) were no longer in the Trash."), nil)
    case .speedTest:
      let before = network.lastTest?.date
      await runSpeedTest()
      if isDemo { return (true, "Sample data: no test was run.", nil) }
      guard let test = network.lastTest, test.date != before else { return (false, network.testProblem ?? "The test didn’t finish.", nil) }
      var text = "Download \(Int(test.downloadMbps.rounded())) Mbps, upload \(Int(test.uploadMbps.rounded())) Mbps"
      if let idle = test.idleLatency, let busy = test.busyLatency { text += ", latency \(Int(idle)) ms idle and \(Int(busy)) ms under load" }
      return (true, text + ".", nil)
    case .siteCheck:
      guard let host = action.host else { return (false, "No site was named.", nil) }
      if isDemo { return (true, "Sample data: \(host) wasn’t checked.", nil) }
      let checks = await SiteCheck.compare(host)
      guard checks.count == 2 else { return (false, "The check didn’t finish.", nil) }
      return (true, SiteCheck.sentence(checks[0], control: checks[1]), nil)
    }
  }

  /// After a measurement ran (a speed test, a site check), asks the same AI once what it
  /// shows. That answer offers no actions, so nothing chains on from it.
  private func explainResults(in message: UUID) async {
    guard var card = actionCard(message), !card.followedUp, !card.isBusy else { return }
    let measured = card.actions.filter { [.speedTest, .siteCheck].contains($0.kind) && card.status[$0.id]?.isDone == true }
    guard !measured.isEmpty else { return }
    card.followedUp = true
    setActionCard(card, in: message)
    if isDemo { return }
    assistantState = .thinking("Looking at the results…")
    let question = "Glade has just done what you proposed. " + card.outcomeLines.joined(separator: " ")
      + "\nIn two or three sentences, tell the owner what this shows about what they asked: “\(card.request.prefix(400))”."
    let networkBrief = await networkForAssistant(card.request, earlier: conversationSoFar)
    let description = MacDescription.build(
      snapshot: snapshot, apps: apps, context: context, suggestions: suggestions, scan: scan, plan: plan,
      battery: batteryBrief, network: networkBrief, networkHistory: networkBrief == nil ? nil : NetworkHistoryStore.load()
    )
    do {
      let reply = try await Assistant.ask(question, snapshot: description, earlier: conversationSoFar, config: config, providers: AgentProviders.all)
      messages.append(Message(role: .assistant, text: reply.answer, provider: reply.provider, model: reply.model))
      assistantState = .idle
    } catch {
      messages.append(Message(role: .problem, text: error.localizedDescription))
      assistantState = .failed(error.localizedDescription)
    }
  }

  // MARK: Removal proposals

  /// Auto or Full Access: a removal proposal’s ticked items go without the
  /// confirmation sheet when `ActionPolicy.decideRemoval` says so.
  func settleRemoval(in message: UUID) async {
    guard let index = messages.firstIndex(where: { $0.id == message }), var card = messages[index].proposal else { return }
    let mode = config.assistant.actionMode
    guard mode != .ask else { return }
    let decision = ActionPolicy.decideRemoval(card.proposal, ticked: card.ticks, mode: mode)
    guard decision.runs else {
      if case .wait(let why) = decision { card.heldBack = why }
      messages[index].proposal = card
      return
    }
    let ids = tickedItems(card).map(\.id)
    guard !ids.isEmpty, !isDemo, let receipt = await assistantClean(ids: ids, provider: card.proposal.provider) else { return }
    guard let latest = messages.firstIndex(where: { $0.id == message }) else { return }
    messages[latest].proposal?.awaitingClean = true
    messages[latest].proposal?.ranByThemselves = mode
    proposalCleanFinished(receipt.id)
  }

  // MARK: Helpers

  func actionCard(_ message: UUID) -> ActionCardState? {
    messages.first { $0.id == message }?.actions
  }

  private func setActionCard(_ card: ActionCardState, in message: UUID) {
    guard let index = messages.firstIndex(where: { $0.id == message }) else { return }
    messages[index].actions = card
  }
}
