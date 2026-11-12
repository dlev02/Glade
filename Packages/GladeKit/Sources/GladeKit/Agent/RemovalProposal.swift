import Foundation

/// What the Assistant proposed removing for a request, after Glade has checked it: each
/// item is a finding from the scan, with the model’s reason, what Glade decided about
/// it, and a second model’s opinion. Nothing here removes anything; the person ticks
/// what goes and confirms in Glade’s own sheet, and `Cleaner` does the rest.
public struct RemovalProposal: Codable, Sendable {
  /// What can be done with an item here.
  public enum Action: String, Codable, Sendable {
    /// Glade can move it to the Trash once the person confirms.
    case remove
    /// The app comes with its own uninstaller, which Glade opens instead.
    case openUninstaller
    /// The app belongs to the system account, so only Finder can move it to the Trash.
    case showInFinder
    /// The app is open; it has to be quit first.
    case quitFirst
    /// Can’t be removed right now, for the reason given.
    case listOnly
  }

  /// A second model’s view of one item.
  public struct Review: Codable, Sendable, Hashable {
    public enum Verdict: String, Codable, Sendable {
      case ok, caution
    }

    public var verdict: Verdict
    /// One plain sentence; empty for most `ok` items.
    public var note: String

    public init(verdict: Verdict, note: String) {
      self.verdict = verdict
      self.note = note
    }
  }

  public struct Item: Codable, Sendable, Identifiable, Hashable {
    /// The finding’s identifier.
    public var id: String
    public var title: String
    public var category: StorageCategory
    public var bytes: Int64
    /// The app’s location, for its icon. Never sent anywhere.
    public var appPath: String?
    /// The proposing model’s reason, in its words.
    public var why: String
    /// The person named it in their request.
    public var named: Bool
    /// Glade ticks it to begin with: only named items that can be removed here.
    public var startsTicked: Bool
    public var action: Action
    /// Why it can’t be removed here, when it can’t.
    public var blocked: String?
    public var review: Review?

    public var isApp: Bool { category == .installedApps }
  }

  /// The person’s words.
  public var request: String
  /// What the proposing model said, for the person.
  public var answer: String
  public var items: [Item]
  /// Identifiers the model proposed that Glade threw out, and why.
  public var rejected: [StorageAdvice.Note]
  public var provider: String
  public var model: String?
  public var runID: String
  /// Who gave the second opinion, when one was given.
  public var reviewer: String?
  public var reviewerModel: String?
  public var reviewRunID: String?
  /// The scan the identifiers come from.
  public var scanID: String
  public var date: Date

  public var hasReview: Bool { reviewer != nil }

  public init(
    request: String, answer: String, items: [Item], rejected: [StorageAdvice.Note], provider: String, model: String?,
    runID: String, reviewer: String? = nil, reviewerModel: String? = nil, reviewRunID: String? = nil, scanID: String,
    date: Date = Date()
  ) {
    self.request = request
    self.answer = answer
    self.items = items
    self.rejected = rejected
    self.provider = provider
    self.model = model
    self.runID = runID
    self.reviewer = reviewer
    self.reviewerModel = reviewerModel
    self.reviewRunID = reviewRunID
    self.scanID = scanID
    self.date = date
  }

  // MARK: Glade’s decisions

  /// What Glade decides about one proposed finding, in code: what can be done with it
  /// here, and whether it starts ticked. Only something the person named that can be
  /// removed right now starts ticked: an app, or a finding the rules would let an
  /// assistant select (`Planner.mayAutoSelect`) and that comes back, so personal and
  /// permanent things never are. Apps with their own uninstaller, ones that need Finder and ones that are open
  /// never are.
  public static func item(for finding: Finding, why: String, named: Bool) -> Item {
    let kinds = Set(finding.blockers.map(\.kind))
    let isApp = finding.category == .installedApps
    let action: Action
    if isApp, kinds.contains(.ownUninstaller) {
      action = .openUninstaller
    } else if isApp, kinds.contains(.needsAdmin) {
      action = .showInFinder
    } else if kinds.contains(.appRunning) {
      action = .quitFirst
    } else if finding.isBlocked {
      action = .listOnly
    } else {
      action = .remove
    }
    let allowed = isApp || (Planner.mayAutoSelect(finding) && finding.recovery != .permanent)
    return Item(
      id: finding.id, title: finding.title, category: finding.category, bytes: finding.bytes,
      appPath: isApp ? finding.paths.first : nil, why: why, named: named,
      startsTicked: action == .remove && named && allowed,
      action: action, blocked: action == .remove ? nil : finding.blockers.first?.detail, review: nil
    )
  }
}
