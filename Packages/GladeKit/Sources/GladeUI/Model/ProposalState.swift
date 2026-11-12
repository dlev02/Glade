import Foundation
import GladeKit

/// A proposal in the conversation and what the person has done with it: which items
/// are ticked, and what happened when they confirmed. Kept with its message, so the
/// card looks the same after scrolling away and back.
public struct ProposalState: Sendable {
  /// What happened to the ticked items once the person confirmed.
  public struct Outcome: Sendable {
    public var receiptID: String
    /// Items that went, by identifier: moved to the Trash or removed straight away.
    public var removed: [String: Bool]
    /// Items that stayed, with the reason.
    public var stayed: [String: String]
    /// Space they take in the Trash, or freed.
    public var bytes: Int64
    /// Put Back brought the Trash items home again.
    public var putBack = false

    public var trashedAll: Bool { removed.values.allSatisfy { $0 } }
  }

  public var proposal: RemovalProposal
  public var ticks: Set<String>
  /// The clean sheet is open with this card’s items.
  var awaitingClean = false
  public var outcome: Outcome?

  public init(_ proposal: RemovalProposal) {
    self.proposal = proposal
    ticks = Set(proposal.items.filter(\.startsTicked).map(\.id))
  }
}
