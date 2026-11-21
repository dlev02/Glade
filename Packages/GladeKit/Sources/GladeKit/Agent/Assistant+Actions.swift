import Foundation

/// Auto mode’s check: a second AI looks at the actions an answer proposed and may hold
/// any of them back. It sees the person’s own words and Glade’s descriptions of the
/// actions only, never the first AI’s answer, so a poisoned answer can’t argue its own
/// case. It can only hold; whatever it says, nothing runs that Glade’s rules wouldn’t
/// run (`ActionPolicy`), and a missing, unreadable or failed check holds everything.
extension Assistant {
  static let actionReviewPurpose = "action check"

  public struct ActionReview: Sendable {
    public var reviews: [String: ActionPolicy.Review]
    /// Who checked, when anyone did.
    public var reviewer: String?
    /// The same AI as the one that proposed them, so it checked its own work.
    public var reviewerIsProposer: Bool

    public init(reviews: [String: ActionPolicy.Review], reviewer: String?, reviewerIsProposer: Bool) {
      self.reviews = reviews
      self.reviewer = reviewer
      self.reviewerIsProposer = reviewerIsProposer
    }
  }

  public static func reviewActions(
    _ actions: [AgentAction], request: String, proposer: String,
    config: GladeConfig = ConfigStore.load(), providers: [any AgentProvider]
  ) async -> ActionReview {
    let held = ActionReview(reviews: [:], reviewer: nil, reviewerIsProposer: false)
    guard !actions.isEmpty, let proposing = providers.first(where: { $0.id == proposer }) ?? providers.first,
          let (reviewer, model, effort) = await reviewer(config: config, proposer: proposing, providers: providers)
    else {
      Log.info(.agent, "No AI free to check the proposed actions; they wait for the person")
      return held
    }
    let words = String(request.components(separatedBy: .newlines).joined(separator: " ").prefix(1_200))
    var prompt = "THE OWNER ASKED\n\(words)\n\nACTIONS PROPOSED (id | what | what happens)\n"
    prompt += actions.map { "\($0.id) | \($0.title) | \($0.detail)" }.joined(separator: "\n")
    do {
      let (reply, runID) = try await run(
        provider: reviewer, purpose: actionReviewPurpose, system: actionReviewSystem, prompt: prompt,
        model: model, config: config, proactive: false, schema: actionReviewSchema, effort: effort
      )
      let raw = try decode(RawActionReview.self, from: reply.text, provider: reviewer.name)
      var reviews: [String: ActionPolicy.Review] = [:]
      var refused: [String] = []
      let offered = Set(actions.map(\.id))
      for item in raw.items ?? [] {
        guard offered.contains(item.id) else {
          refused.append("\(item.id): not one of the actions it was asked about")
          continue
        }
        // Only an explicit approve counts; anything else holds.
        reviews[item.id] = item.verdict?.lowercased() == "approve" ? .approve : .hold(clip(item.note ?? ""))
      }
      if !refused.isEmpty { amend(runID: runID) { $0.rejected = refused } }
      let approved = reviews.values.filter { $0 == .approve }.count
      Log.info(.agent, "\(reviewer.name) checked \(actions.count) proposed actions: \(approved) approved")
      return ActionReview(reviews: reviews, reviewer: reply.provider, reviewerIsProposer: reviewer.id == proposing.id)
    } catch {
      Log.warning(.agent, "The check of proposed actions by \(reviewer.name) failed, so they wait: \(error.localizedDescription)")
      return ActionReview(reviews: [:], reviewer: reviewer.name, reviewerIsProposer: reviewer.id == proposing.id)
    }
  }

  static let actionReviewSystem = """
    You check actions another assistant proposed to take on a Mac for its owner, inside Glade, an app that keeps the Mac running well. You see what the owner asked and each proposed action, described by Glade. For each, answer `approve` only when it plainly helps with what the owner asked and what happens is something the owner would expect and accept; otherwise `hold`, with a short note for the owner saying why. Hold anything the owner didn’t ask about, said not to do, or might lose work or data from. When unsure, hold: a held action simply waits for the owner to approve it.

    Reply with one JSON object and nothing else:
    {"items": [{"id": "...", "verdict": "approve", "note": ""}]}
    """

  static let actionReviewSchema = """
    {"type":"object","properties":{"items":{"type":"array","items":{"type":"object","properties":{"id":{"type":"string"},"verdict":{"type":"string","enum":["approve","hold"]},"note":{"type":"string"}},"required":["id","verdict","note"],"additionalProperties":false}}},"required":["items"],"additionalProperties":false}
    """

  struct RawActionReview: Decodable {
    struct Item: Decodable {
      var id: String
      var verdict: String?
      var note: String?
    }

    var items: [Item]?
  }
}
