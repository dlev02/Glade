import Foundation
import GladeKit

/// The actions an answer proposed and what became of each: checked, waiting for the
/// person, running, done. Kept with its message, so the card reads the same after
/// scrolling away and back.
public struct ActionCardState: Sendable {
  public enum Status: Sendable, Equatable {
    /// Auto: the second opinion is looking at it.
    case checking
    /// Waiting for the person, with why it didn’t run by itself.
    case waiting(String)
    case running
    case done(String)
    case failed(String)
    /// The person chose Not Now.
    case declined

    public var isWaiting: Bool { if case .waiting = self { true } else { false } }
    public var isDone: Bool { if case .done = self { true } else { false } }
    public var isFinished: Bool {
      switch self {
      case .done, .failed, .declined: true
      default: false
      }
    }
  }

  public var actions: [AgentAction]
  public var status: [String: Status]
  /// The person’s words the actions answer.
  public var request: String
  /// The AI that proposed them.
  public var proposer: String
  /// The mode when they were proposed.
  public var mode: ActionMode
  /// Auto: who checked them, and what it said.
  public var reviewer: String?
  public var reviews: [String: ActionPolicy.Review] = [:]
  /// Ran without the person approving it.
  public var ranByThemselves: Set<String> = []
  /// A clean’s receipt, for Put Back.
  public var receipts: [String: String] = [:]
  public var putBack: Set<String> = []
  /// An explanation of the results has been asked for.
  public var followedUp = false

  public init(actions: [AgentAction], request: String, proposer: String, mode: ActionMode) {
    self.actions = actions
    self.request = request
    self.proposer = proposer
    self.mode = mode
    status = Dictionary(uniqueKeysWithValues: actions.map { ($0.id, Status.waiting("Waiting for you.")) })
  }

  public var waiting: [AgentAction] { actions.filter { status[$0.id]?.isWaiting == true } }
  public var isBusy: Bool { status.values.contains { $0 == .running || $0 == .checking } }

  /// What happened, as Glade’s own words for the conversation, so the next answer knows.
  public var outcomeLines: [String] {
    actions.compactMap { action in
      switch status[action.id] {
      case .done(let text)?: "\(action.title): done. \(text)"
      case .failed(let text)?: "\(action.title): didn’t work. \(text)"
      case .declined?: "\(action.title): the owner chose not to."
      case .waiting?: "\(action.title): waiting for the owner to approve it."
      default: nil
      }
    }
  }
}
