import Foundation

/// Requests to remove something the person names. The model proposes finding
/// identifiers from a list Glade made; Glade throws out anything it wasn’t shown,
/// decides in code what starts ticked, and asks a second model what the person should
/// know first. Nothing is removed here: the person confirms in Glade’s own sheet.
extension Assistant {
  static let proposalPurpose = "removal proposal"
  static let reviewPurpose = "removal second opinion"
  /// The most items one proposal lists.
  static let proposalLimit = 12

  /// Answers a request to remove something with a proposal the person can act on.
  /// - Parameters:
  ///   - snapshot: The usual description of this Mac (`MacDescription.build`), sent
  ///     after the candidates as far as the budget allows.
  ///   - reviewing: Told the second opinion’s provider name as it is asked.
  public static func propose(
    _ request: String,
    scan: ScanResult,
    snapshot: String,
    config: GladeConfig = ConfigStore.load(),
    providers: [any AgentProvider],
    now: Date = Date(),
    reviewing: (@Sendable (String) -> Void)? = nil
  ) async throws -> RemovalProposal {
    let provider = try await pick(config: config, providers: providers, proactive: false)
    let model = config.assistant.models[provider.id]
    let budget = provider.isLocal ? 9_000 : 60_000
    let found = RemovalRequest.candidates(for: request, scan: scan, limit: provider.isLocal ? 12 : 40, now: now)
    let candidates = MacDescription.removalCandidates(found, characterBudget: budget * 2 / 3, now: now)
    let prompt = StoragePrompt.removalPrompt(request: request, candidates: candidates, snapshot: snapshot, characterBudget: budget)
    let (reply, runID) = try await run(
      provider: provider, purpose: proposalPurpose, system: StoragePrompt.removalSystem, prompt: prompt,
      model: model, config: config, proactive: false, schema: StoragePrompt.removalSchema
    )
    var proposal = RemovalProposal(
      request: request, answer: "", items: [], rejected: [], provider: reply.provider, model: reply.model ?? model,
      runID: runID, scanID: scan.id, date: now
    )
    guard let raw = try? decode(RawProposal.self, from: reply.text, provider: provider.name) else {
      // An answer in words only is still an answer; it just proposes nothing.
      Log.info(.agent, "\(provider.name) answered the removal request without a proposal")
      proposal.answer = reply.text.trimmingCharacters(in: .whitespacesAndNewlines)
      return proposal
    }
    proposal.answer = String((raw.answer ?? "").trimmingCharacters(in: .whitespacesAndNewlines).prefix(800))
    validate(raw.propose ?? [], into: &proposal, shown: Set(candidates.ids), scan: scan)
    amend(runID: runID) { record in record.rejected = proposal.rejected.map { "\($0.id): \($0.why)" } }
    let ticked = proposal.items.filter(\.startsTicked).count
    Log.info(.agent, "Proposal from \(provider.name): \(proposal.items.count) items, \(proposal.items.filter(\.named).count) named, \(ticked) ticked, \(proposal.rejected.count) rejected, from \(candidates.ids.count) candidates")
    if !proposal.items.isEmpty {
      await review(&proposal, scan: scan, proposer: provider, config: config, providers: providers, now: now, reviewing: reviewing)
    }
    return proposal
  }

  /// Keeps only proposals of findings the model was shown that are still in the scan,
  /// each once, and decides each item in code.
  static func validate(_ notes: [RawProposal.Note], into proposal: inout RemovalProposal, shown: Set<String>, scan: ScanResult) {
    let words = RemovalRequest.Words(proposal.request)
    var seen = Set<String>()
    for note in notes {
      guard seen.insert(note.id).inserted else { continue }
      guard shown.contains(note.id), let finding = scan.finding(note.id) else {
        proposal.rejected.append(.init(id: note.id, why: "Not one of the items it was shown."))
        Log.warning(.safety, "Dropped a proposal for \(note.id): not one of the items shown")
        continue
      }
      guard proposal.items.count < proposalLimit else {
        proposal.rejected.append(.init(id: note.id, why: "Glade lists at most \(proposalLimit) at a time."))
        continue
      }
      proposal.items.append(RemovalProposal.item(for: finding, why: clip(note.why), named: RemovalRequest.isNamed(finding, words)))
    }
  }

  // MARK: The second opinion

  /// Who reviews a proposal: the person’s choice for a closer look (the same one
  /// `advise` escalates to) when it’s ready and isn’t the proposer with the same model;
  /// otherwise Apple Intelligence on this Mac; otherwise any other ready provider.
  static func reviewer(
    config: GladeConfig, proposer: any AgentProvider, providers: [any AgentProvider]
  ) async -> (provider: any AgentProvider, model: String?)? {
    if let (deep, model) = deepChoice(config: config, current: proposer, providers: providers), await deep.status().isReady {
      return (deep, model)
    }
    if proposer.id != "apple", let apple = providers.first(where: { $0.id == "apple" }), await apple.status().isReady {
      return (apple, nil)
    }
    let ordered = config.assistant.order.compactMap { id in providers.first { $0.id == id } }
      + providers.filter { !config.assistant.order.contains($0.id) }
    for other in ordered where other.id != proposer.id && other.id != "apple" {
      if await other.status().isReady { return (other, config.assistant.models[other.id]) }
    }
    return nil
  }

  /// Adds the second opinion’s notes to each item. It can’t add items, tick or untick
  /// anything; a failure leaves the proposal without one.
  static func review(
    _ proposal: inout RemovalProposal, scan: ScanResult, proposer: any AgentProvider,
    config: GladeConfig, providers: [any AgentProvider], now: Date, reviewing: (@Sendable (String) -> Void)?
  ) async {
    guard let (reviewer, model) = await reviewer(config: config, proposer: proposer, providers: providers) else {
      Log.info(.agent, "No second opinion: no other AI is ready")
      return
    }
    reviewing?(reviewer.name)
    Log.info(.agent, "Second opinion from \(reviewer.name) (\(model ?? "default model")) on \(proposal.items.count) items")
    let findings = proposal.items.compactMap { scan.finding($0.id) }
    let prompt = StoragePrompt.reviewPrompt(
      request: proposal.request, findings: findings, scan: scan, characterBudget: reviewer.isLocal ? 3_500 : 20_000, now: now
    )
    do {
      let (reply, runID) = try await run(
        provider: reviewer, purpose: reviewPurpose, system: StoragePrompt.reviewSystem, prompt: prompt,
        model: model, config: config, proactive: false, schema: StoragePrompt.reviewSchema
      )
      let raw = try decode(RawReview.self, from: reply.text, provider: reviewer.name)
      let refused = apply(raw.items ?? [], to: &proposal)
      amend(runID: runID) { $0.rejected = refused }
      proposal.reviewer = reply.provider
      proposal.reviewerModel = reply.model ?? model
      proposal.reviewRunID = runID
      let cautions = proposal.items.filter { $0.review?.verdict == .caution }.count
      Log.info(.agent, "Second opinion from \(reviewer.name): \(cautions) cautions, \(refused.count) notes refused")
    } catch {
      Log.warning(.agent, "The second opinion from \(reviewer.name) failed: \(error.localizedDescription)")
    }
  }

  /// Puts each note on its item. Notes about anything else are refused and returned.
  static func apply(_ notes: [RawReview.Note], to proposal: inout RemovalProposal) -> [String] {
    var refused: [String] = []
    for note in notes {
      guard let index = proposal.items.firstIndex(where: { $0.id == note.id }) else {
        refused.append("\(note.id): Not one of the items it was asked about.")
        Log.warning(.safety, "Dropped a second-opinion note for \(note.id): not one of the proposed items")
        continue
      }
      let verdict = RemovalProposal.Review.Verdict(rawValue: (note.verdict ?? "").lowercased()) ?? .ok
      let text = clip(note.note ?? "")
      // A caution with nothing to say isn’t one.
      proposal.items[index].review = .init(verdict: verdict == .caution && text.isEmpty ? .ok : verdict, note: text)
    }
    return refused
  }

  // MARK: Parsing

  struct RawProposal: Decodable {
    struct Note: Decodable {
      var id: String
      var why: String

      init(id: String, why: String) {
        self.id = id
        self.why = why
      }

      init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        why = (try? c.decodeIfPresent(String.self, forKey: .why)) ?? ""
      }

      enum CodingKeys: String, CodingKey { case id, why }
    }

    var answer: String?
    var propose: [Note]?
  }

  struct RawReview: Decodable {
    struct Note: Decodable {
      var id: String
      var verdict: String?
      var note: String?
    }

    var items: [Note]?
  }
}
