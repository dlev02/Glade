import AppKit
import Foundation
import GladeKit

/// Free Up Memory: the plan, the sheet’s ticks, and carrying it out.
extension AppModel {
  /// What Free Up Memory would do right now. Sample data has its own made-up plan, so
  /// it never names the person’s apps.
  public var reliefPlan: ReliefPlan {
    if isDemo { return SampleData.sampleRelief(suggestions: suggestions) }
    return ReliefPlan.make(suggestions: suggestions, apps: apps, context: context, simulators: simulators, config: config)
  }

  /// "Free Up 7.4 GB of Memory…", or without the figure when nothing would be ticked.
  public func reliefButtonTitle(_ plan: ReliefPlan) -> String {
    let bytes = plan.memoryBytes(of: plan.defaultSelection)
    return bytes >= 50_000_000 ? "Free Up \(Format.bytes(bytes)) of Memory…" : "Free Up Memory…"
  }

  /// Opens the sheet on the plan as it is now, with the plan’s own ticks.
  public func openRelief() {
    guard !showsRelief else { return }
    let plan = reliefPlan
    guard !plan.actions.isEmpty else { return }
    relief = ReliefSession(plan: plan, chosen: plan.defaultSelection)
    showsRelief = true
    Log.info(.app, "Free Up Memory opened: \(plan.actions.count) actions, \(plan.defaultSelection.count) ticked")
  }

  /// Takes fresh readings first, for when the window was closed and nothing was
  /// watching: a notification or a link opening the sheet.
  public func openReliefWithFreshReadings() async {
    if !isDemo { await refreshApps() }
    openRelief()
  }

  public func isChosen(_ action: ReliefPlan.Action) -> Bool {
    relief?.chosen.contains(action.id) ?? false
  }

  public func setChosen(_ action: ReliefPlan.Action, _ chosen: Bool) {
    guard var session = relief, session.step == .confirm else { return }
    if chosen { session.chosen.insert(action.id) } else { session.chosen.remove(action.id) }
    relief = session
  }

  /// Quits and shuts down what’s ticked, in order, then shows what happened.
  public func performRelief() async {
    guard var session = relief, session.step == .confirm else { return }
    let actions = session.chosenActions
    guard !actions.isEmpty else { return }
    session.step = .running(done: 0, total: actions.count, name: actions[0].name)
    relief = session
    let result: ReliefResult
    if isDemo {
      result = await simulateRelief(actions)
    } else {
      let config = config
      result = await ReliefResult.perform(actions, config: config) { [weak self] done, total, name in
        Task { @MainActor in
          guard let self, var current = self.relief, current.isRunning, done < total else { return }
          current.step = .running(done: done, total: total, name: name)
          self.relief = current
        }
      }
      await refreshApps()
    }
    guard var finished = relief else { return }
    finished.step = .finished(result)
    relief = finished
  }

  /// Closes the sheet, unless it’s part way through.
  public func dismissRelief() {
    guard !(relief?.isRunning ?? false) else { return }
    showsRelief = false
  }

  /// Called once the sheet has gone.
  public func reliefDismissed() {
    relief = nil
  }

  /// Demo mode only: walks through the actions without touching anything. With
  /// `-demoRelief partial`, Mail stays open as if it were asking about unsaved work.
  private func simulateRelief(_ actions: [ReliefPlan.Action]) async -> ReliefResult {
    let partial = DemoState.value("demoRelief") == "partial"
    var entries: [ReliefResult.Entry] = []
    for (index, action) in actions.enumerated() {
      if var session = relief {
        session.step = .running(done: index, total: actions.count, name: action.name)
        relief = session
      }
      try? await Task.sleep(for: .milliseconds(350))
      let stuck = partial && action.kind == .quit && action.name == "Mail"
      let done: ReliefResult.Outcome = switch action.kind {
      case .quit: .quit
      case .relaunch: .relaunched
      case .shutDown: .shutDown
      }
      let outcome = stuck ? .stillOpen : done
      entries.append(ReliefResult.Entry(
        id: action.id, name: action.name, kind: action.kind, outcome: outcome, memoryBytes: action.memoryBytes,
        detail: stuck ? "Still open: it may be asking about unsaved changes" : nil
      ))
    }
    let before = snapshot?.memory.usedBytes ?? 0
    // Quitting gives back a little less than the apps held.
    let freed = entries.filter { $0.outcome.succeeded }.reduce(Int64(0)) { $0 + $1.memoryBytes } * 9 / 10
    return ReliefResult(entries: entries, memoryBefore: before, memoryAfter: max(0, before - freed))
  }

  /// Where clicking a notification of this kind goes.
  static func link(forNotification kind: String) -> URL {
    switch ThresholdAlert.Kind(rawValue: kind) {
    case .memoryPressure: Section.performance.reliefLink
    case .sustainedCPU, .sustainedGPU: Section.performance.link
    case .lowStorage: Section.storage.link
    case .chargedPastLimit, .chargeLimitOff, .batteryHot, .batteryHealth, .awakeOnBattery, .sleepDrain: Section.battery.link
    case nil: kind == "assistant" ? Section.assistant.link : Section.overview.link
    }
  }
}
