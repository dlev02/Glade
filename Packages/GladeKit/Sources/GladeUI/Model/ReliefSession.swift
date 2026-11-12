import GladeKit

/// Free Up Memory while its sheet is open: the plan as it stood when the sheet opened
/// (so rows don’t move under the pointer), what’s ticked, and how far along it is.
public struct ReliefSession: Equatable, Sendable {
  public enum Step: Equatable, Sendable {
    case confirm
    /// `name` is the app or simulator being quit or shut down.
    case running(done: Int, total: Int, name: String)
    case finished(ReliefResult)
  }

  public var plan: ReliefPlan
  public var chosen: Set<String>
  public var step: Step = .confirm

  public var chosenActions: [ReliefPlan.Action] { plan.actions(chosen) }

  public var isRunning: Bool {
    if case .running = step { return true }
    return false
  }
}
