import Foundation

/// Something the Assistant may propose doing, offered by Glade from the readings it
/// took for this question. The model only ever names an action by its `id`; what the
/// action does, what it says on the card, how risky it is and whether Glade’s rules
/// would ever do it without the person are all decided here, in code.
public struct AgentAction: Codable, Sendable, Identifiable, Hashable {
  public enum Kind: String, Codable, Sendable {
    /// Ask one app to quit, as its Quit menu item would.
    case quit
    /// Quit an app that has grown and open it again.
    case relaunch
    /// Shut a simulator down; its apps and data stay.
    case shutDownSimulator
    /// The quits and shutdowns Free Up Memory ticks by itself, together.
    case freeUpMemory
    /// Restart a macOS helper that is using far more memory than it should. macOS
    /// opens it again by itself.
    case restartHelper
    /// The Careful clean: things that rebuild themselves and haven’t been used lately.
    case cleanCareful
    /// What the Balanced clean adds: things that download or reinstall again.
    case cleanBalanced
    /// Put back what the last clean moved to the Trash.
    case putBack
    /// macOS’s own speed test, which uses data.
    case speedTest
    /// Compare how quickly a site the person named answers with a well-known one.
    case siteCheck
  }

  /// How much care an action needs. Decided in code for each action, never by a model.
  public enum Tier: String, Codable, Sendable {
    /// Only reads; runs in every mode.
    case look
    /// Easily undone, or comes back by itself.
    case undoable
    /// Takes effort to undo: things download again, or wait in the Trash.
    case harder
    /// Always waits for the person, whatever the mode.
    case alwaysAsks
  }

  /// Random for each question, so an id from an earlier answer, or one written into an
  /// app’s name, matches nothing.
  public var id: String
  public var kind: Kind
  /// What the card says, written by Glade: "Quit Slack".
  public var title: String
  /// What will happen, written by Glade: "Frees about 1.2 GB. Opening it again brings it back."
  public var detail: String
  public var tier: Tier
  /// Glade’s own rules would do this without the person: Free Up Memory would tick it,
  /// the Careful plan selects it, or the person named it. Only these can ever run
  /// without the person, and then only in Auto or Full Access.
  public var eligible: Bool
  /// Why it can’t run without the person, when it can’t.
  public var heldBecause: String?
  /// For quits, relaunches and shutdowns: what Free Up Memory would do.
  public var relief: [ReliefPlan.Action] = []
  /// For cleans: the findings, from the scan below.
  public var findingIDs: [String] = []
  public var scanID: String?
  public var bytes: Int64 = 0
  /// For a helper restart: its bundle identifier.
  public var helperBundleID: String?
  /// For Put Back: the clean’s receipt.
  public var receiptID: String?
  /// For a site check: the host, taken from the person’s own words.
  public var host: String?

  public init(id: String, kind: Kind, title: String, detail: String, tier: Tier, eligible: Bool, heldBecause: String? = nil) {
    self.id = id
    self.kind = kind
    self.title = title
    self.detail = detail
    self.tier = tier
    self.eligible = eligible
    self.heldBecause = heldBecause
  }
}

/// Whether an action runs now or waits for the person. Pure, so the safety test can
/// walk every case. The second AI can only hold an action back; nothing it says can
/// make one run that Glade’s rules wouldn’t run.
public enum ActionPolicy {
  /// The second AI’s view of one action, in Auto.
  public enum Review: Codable, Sendable, Equatable {
    case approve
    case hold(String)
  }

  public enum Decision: Sendable, Equatable {
    case run
    case wait(String)

    public var runs: Bool { self == .run }
  }

  /// The most actions one answer may propose.
  public static let perAnswer = 3
  /// The most of those that take effort to undo and may run without the person.
  public static let harderPerAnswer = 1

  public static func decide(_ action: AgentAction, mode: ActionMode, review: Review?, reviewerIsProposer: Bool) -> Decision {
    switch action.tier {
    case .look: return .run
    case .alwaysAsks: return .wait(action.heldBecause ?? "Glade always asks you first about this.")
    case .undoable, .harder: break
    }
    guard action.eligible else { return .wait(action.heldBecause ?? "Glade’s rules wouldn’t do this by themselves.") }
    switch mode {
    case .ask:
      return .wait("Waiting for you.")
    case .full:
      return .run
    case .auto:
      switch review {
      case .approve?:
        // Something that takes effort to undo needs a check by a different AI.
        if action.tier == .harder, reviewerIsProposer { return .wait("No other AI was free to check it.") }
        return .run
      case .hold(let why)?:
        return .wait(why.isEmpty ? "The second opinion held it back." : why)
      case nil:
        return .wait("No second opinion, so it waits for you.")
      }
    }
  }

  /// Decides each action of one answer, in order, keeping to the limits per answer.
  public static func decideAll(
    _ actions: [AgentAction], mode: ActionMode, reviews: [String: Review], reviewerIsProposer: Bool
  ) -> [String: Decision] {
    var decisions: [String: Decision] = [:]
    var harderRunning = 0
    for action in actions.prefix(perAnswer) {
      var decision = decide(action, mode: mode, review: reviews[action.id], reviewerIsProposer: reviewerIsProposer)
      if decision.runs, action.tier == .harder {
        harderRunning += 1
        if harderRunning > harderPerAnswer { decision = .wait("Only one change like this runs without you at a time.") }
      }
      decisions[action.id] = decision
    }
    return decisions
  }

  /// Whether a removal proposal’s ticked items go without the confirmation sheet. Only
  /// items Glade ticked itself (named by the person, removable, never personal or
  /// permanent) are ever ticked to begin with; in Auto every one of them needs an
  /// explicit all-clear from the second opinion, and apps one from a different AI.
  public static func decideRemoval(_ proposal: RemovalProposal, ticked: Set<String>, mode: ActionMode) -> Decision {
    let items = proposal.items.filter { ticked.contains($0.id) }
    guard !items.isEmpty else { return .wait("Nothing is ticked.") }
    guard items.allSatisfy({ $0.startsTicked && $0.action == .remove }) else { return .wait("You changed what’s ticked.") }
    if items.filter(\.isApp).count > 1 { return .wait("More than one app, so Glade asks you first.") }
    switch mode {
    case .ask:
      return .wait("Waiting for you.")
    case .full:
      return .run
    case .auto:
      guard proposal.hasReview else { return .wait("No second opinion, so it waits for you.") }
      if let caution = items.first(where: { $0.review?.verdict != .ok }) {
        return .wait(caution.review == nil ? "The second opinion didn’t look at \(caution.title)." : "The second opinion has a caution.")
      }
      if items.contains(where: \.isApp), proposal.reviewer == proposal.provider {
        return .wait("No other AI was free to check it.")
      }
      return .run
    }
  }
}
