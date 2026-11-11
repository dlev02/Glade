import GladeKit

/// Acting on a suggestion, wherever it’s shown.
extension AppModel {
  /// The button title for a suggestion, or `nil` when it’s only something to look at.
  public func actionTitle(for suggestion: PerformanceSuggestion) -> String? {
    guard suggestion.actionable else { return nil }
    if isDemo { return suggestion.kind == .shutDownIdleSimulator ? "Shut Down" : "Quit" }
    if suggestion.kind == .shutDownIdleSimulator {
      return simulators.contains { $0.udid == suggestion.simulatorUDID } ? "Shut Down" : nil
    }
    return apps.contains { $0.id == suggestion.appID } ? "Quit" : nil
  }

  /// Does what the suggestion says and returns a sentence describing what happened.
  public func perform(_ suggestion: PerformanceSuggestion) async -> String {
    if isDemo { return "Sample data: nothing was changed." }
    if suggestion.kind == .shutDownIdleSimulator {
      guard let simulator = simulators.first(where: { $0.udid == suggestion.simulatorUDID }) else {
        return "That simulator is no longer running."
      }
      return await shutDown(simulator)
    }
    guard let app = apps.first(where: { $0.id == suggestion.appID }) else {
      return "\(suggestion.appName) is no longer running."
    }
    return await quit(app)
  }

  /// The symbol shown for a suggestion that has no app icon of its own.
  public func symbol(for suggestion: PerformanceSuggestion) -> String? {
    suggestion.kind == .shutDownIdleSimulator ? "iphone" : nil
  }

  /// Something to look at rather than tidy up: a process pinning the processor or the
  /// graphics chip, or anything while memory is under pressure. Its icon uses the
  /// warning colour instead of the accent.
  public func isWarning(_ suggestion: PerformanceSuggestion) -> Bool {
    suggestion.kind == .runawayProcess || suggestion.kind == .gpuHog
      || (snapshot?.memory.pressure ?? .normal) > .normal
  }
}
