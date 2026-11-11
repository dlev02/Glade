import Foundation

/// One thing the person could do to free memory, processor or GPU.
public struct PerformanceSuggestion: Codable, Sendable, Identifiable, Hashable {
  public enum Kind: String, Codable, Sendable {
    /// An app left open and unused.
    case quitIdleApp
    /// An app that has grown large over a long session; a fresh start usually frees memory.
    case relaunchHeavyApp
    /// A process pinning a core. For the person to look at, never acted on automatically.
    case runawayProcess
    /// An app or process using an unusual share of memory.
    case memoryHog
    /// A background app keeping the GPU busy.
    case gpuHog
    /// A booted simulator nothing is using. Shutting it down keeps its apps and data.
    case shutDownIdleSimulator
  }

  public enum Confidence: String, Codable, Sendable, Comparable {
    case low, medium, high

    private var rank: Int {
      switch self {
      case .low: 0
      case .medium: 1
      case .high: 2
      }
    }

    public static func < (lhs: Confidence, rhs: Confidence) -> Bool { lhs.rank < rhs.rank }
  }

  /// What acting on the suggestion would give back, estimated from current use.
  public struct Frees: Codable, Sendable, Hashable {
    public var memoryBytes: Int64
    /// Share of one core.
    public var cpuPercent: Double
    public var gpuPercent: Double?
  }

  /// `<kind>:<appID>`, stable while the situation lasts.
  public var id: String
  public var kind: Kind
  /// For simulators, `simulator:<UDID>`.
  public var appID: String
  public var appName: String
  /// The process concerned, for runaways inside a multi-process app.
  public var pid: Int32?
  public var title: String
  /// One plain sentence with the numbers.
  public var reason: String
  public var frees: Frees
  public var confidence: Confidence
  /// Glade can act on it (quit or relaunch an app). `false` means look, don’t touch:
  /// runaways, and processes that aren’t apps.
  public var actionable: Bool
  /// The simulator to shut down, for `shutDownIdleSimulator`.
  public var simulatorUDID: String? = nil
  /// Its device set’s folder, passed to `SimulatorControl.shutdown(udid:set:)`.
  public var simulatorSetPath: String? = nil
  /// The numbers in a few words, for a row under the name: "Idle 31 h · 10.3 GB".
  /// `reason` stays the full sentence for the command line and the assistant.
  public var facts: String? = nil
  /// A short doubt worth seeing before acting, such as "May be in use by Bitrig".
  public var caveat: String? = nil
}

/// Rule-based suggestions. No model involved, so it can run on every refresh.
public enum PerformanceAdvisor {
  /// Minutes in the background before an app counts as idle.
  public static let idleMinutes = 20.0
  /// Below this share of one core an app counts as quiet.
  public static let quietCPUPercent = 2.0
  /// At or above this share of one core an app counts as working.
  public static let workingCPUPercent = 10.0
  /// A process above this share of one core may be stuck.
  public static let runawayCPUPercent = 90.0
  /// Idle apps using less than this aren’t worth mentioning.
  public static let minimumIdleBytes: Int64 = 100_000_000

  /// Idle simulators using less than this aren’t worth mentioning.
  public static let minimumIdleSimulatorBytes: Int64 = 300_000_000

  /// - Parameter simulators: From `SystemSampler.simulators()`. Idle ones become
  ///   shut-down suggestions, ranked with the app suggestions by memory freed.
  public static func suggestions(
    snapshot: SystemSnapshot, apps: [AppUsage], context: ActivityContext, simulators: [SimulatorUsage] = [],
    config: GladeConfig = ConfigStore.load(), now: Date = Date()
  ) -> [PerformanceSuggestion] {
    let ram = max(snapshot.memory.totalBytes, 1)
    let pressured = snapshot.memory.pressure > .normal
    let keep = Set(config.keepRunning.map { $0.lowercased() })
    let frontID = context.frontmostApp?.id

    func protected(_ app: AppUsage) -> Bool {
      app.isSystem || app.isGlade || app.isFrontmost || app.id == frontID
        || keep.contains(app.id.lowercased()) || keep.contains(app.name.lowercased())
        || app.bundleIdentifier.map { keep.contains($0.lowercased()) } == true
    }
    func busy(_ app: AppUsage) -> Bool {
      app.isPlayingAudio || app.isCapturingAudio || app.preventingSleep != nil
    }
    func frees(_ app: AppUsage) -> PerformanceSuggestion.Frees {
      .init(memoryBytes: app.memoryBytes, cpuPercent: app.cpuPercent, gpuPercent: app.gpuPercent)
    }
    func make(
      _ kind: PerformanceSuggestion.Kind, _ app: AppUsage, title: String, reason: String, facts: String,
      confidence: PerformanceSuggestion.Confidence, pid: Int32? = nil, actionable: Bool
    ) -> PerformanceSuggestion {
      PerformanceSuggestion(
        id: "\(kind.rawValue):\(app.id)", kind: kind, appID: app.id, appName: app.name, pid: pid,
        title: title, reason: reason, frees: frees(app), confidence: confidence, actionable: actionable,
        facts: facts
      )
    }

    var result: [PerformanceSuggestion] = []
    let memory = { (bytes: Int64) in Format.bytes(bytes) }

    // Shut down idle simulators. Each is offered on its own, so the combined "Simulator
    // devices" row isn’t also flagged as a memory hog.
    let idleSimulators = simulators.filter {
      $0.isIdle && $0.memoryBytes >= minimumIdleSimulatorBytes
        && !keep.contains($0.udid.lowercased()) && !keep.contains($0.name.lowercased())
    }
    for simulator in idleSimulators {
      let idleFor = simulator.lastActivity.map { now.timeIntervalSince($0) }
      // Only boot time known: nothing has started in it since, but it may have been looked at.
      let sinceBootOnly = simulator.lastActivity != nil && simulator.lastActivity == simulator.bootedAt
      let label = simulator.system.map { "\(simulator.name) · \($0)" } ?? simulator.name
      var reason =
        if let idleFor, sinceBootOnly {
          "\(label) has been idle since it started \(Durations.phrase(idleFor)) ago and is using \(memory(simulator.memoryBytes))."
        } else if let idleFor {
          "\(label) has been idle for \(Durations.phrase(idleFor)) and is using \(memory(simulator.memoryBytes))."
        } else {
          "\(label) is booted with nothing using it and is using \(memory(simulator.memoryBytes))."
        }
      if simulator.deviceSet != .standard { reason += " It’s in the \(simulator.deviceSet.title) set." }
      if let note = simulator.note { reason += " \(note)" }
      var confidence = PerformanceSuggestion.Confidence.medium
      if !sinceBootOnly && (idleFor ?? 0) >= 2 * 3600 && (simulator.memoryBytes >= 1_000_000_000 || pressured) { confidence = .high }
      if simulator.note != nil { confidence = .low }
      let idleFacts = idleFor.map { "Idle \(shortDuration($0))" } ?? "Not in use"
      // Every caveat so far is about Bitrig, which can show a simulator Glade can’t see.
      let caveat = simulator.note.map { $0.contains("Bitrig") ? "May be in use by Bitrig" : "May be in use" }
      let id = "simulator:\(simulator.udid)"
      result.append(PerformanceSuggestion(
        id: "\(PerformanceSuggestion.Kind.shutDownIdleSimulator.rawValue):\(id)", kind: .shutDownIdleSimulator,
        appID: id, appName: simulator.name, pid: nil, title: "Shut down \(simulator.name)", reason: reason,
        frees: .init(memoryBytes: simulator.memoryBytes, cpuPercent: simulator.cpuPercent, gpuPercent: simulator.gpuPercent),
        confidence: confidence, actionable: true, simulatorUDID: simulator.udid, simulatorSetPath: simulator.setPath,
        facts: "\(idleFacts) · \(memory(simulator.memoryBytes))", caveat: caveat
      ))
    }
    let simulatorRowIDs: Set<String> = ["process:\(AppGrouper.simulatorRowName)", IDEContext.simulatorBundleID]

    for app in apps where !protected(app) && !busy(app) {
      // With a breakdown, the devices are judged one by one above.
      if !simulators.isEmpty && simulatorRowIDs.contains(app.id) { continue }
      let isApp = app.kind == .app
      let launchedAgo = app.launchDate.map { now.timeIntervalSince($0) } ?? 0

      // Quit an idle app.
      if isApp, app.activationPolicy == .regular, app.cpuPercent < quietCPUPercent, app.memoryBytes >= minimumIdleBytes, launchedAgo > 120 {
        var idleFor: TimeInterval?
        var confidence = PerformanceSuggestion.Confidence.medium
        if let last = app.lastActive {
          let gap = now.timeIntervalSince(last)
          if gap >= idleMinutes * 60 {
            idleFor = gap
            if gap >= 2 * 3600 && (app.memoryBytes >= 500_000_000 || pressured) { confidence = .high }
          }
        } else if app.isHidden && app.windowCount == 0 {
          idleFor = launchedAgo
          confidence = .low
        }
        if let idleFor {
          let when = app.lastActive == nil ? "is hidden with no windows open" : "hasn’t been used for \(Durations.phrase(idleFor))"
          result.append(make(
            .quitIdleApp, app, title: "Quit \(app.name)",
            reason: "\(app.name) is using \(memory(app.memoryBytes)) and \(when).",
            facts: "\(app.lastActive == nil ? "Hidden" : "Idle \(shortDuration(idleFor))") · \(memory(app.memoryBytes))",
            confidence: confidence, actionable: true
          ))
          continue
        }
      }

      // A process pinning a core. Checked before the "working" rule because high CPU is the point.
      if app.busiestCPUPercent >= runawayCPUPercent {
        let process = app.pids.count > 1 ? "One of \(app.name)’s processes" : app.name
        let cores = app.busiestCPUPercent / 100
        let load = cores >= 1.5 ? "about \(Int(cores.rounded())) full cores" : "a full core"
        result.append(make(
          .runawayProcess, app, title: "Check \(app.name)",
          reason: "\(process) is using \(Int(app.busiestCPUPercent.rounded()))% CPU (\(load)) while in the background.",
          facts: "\(Int(app.busiestCPUPercent.rounded()))% CPU in the background",
          confidence: app.kind == .app ? .medium : .low, pid: app.busiestPID, actionable: false
        ))
        continue
      }

      // A background app keeping the GPU busy.
      if let gpu = app.gpuPercent, gpu >= 50 {
        result.append(make(
          .gpuHog, app, title: "\(app.name) is using the GPU",
          reason: "\(app.name) is using \(Int(gpu.rounded()))% of the GPU while in the background.",
          facts: "\(Int(gpu.rounded()))% GPU in the background",
          confidence: .medium, actionable: false
        ))
        continue
      }

      guard app.cpuPercent < workingCPUPercent else { continue }

      // A long session that has grown large.
      let heavy = max(2_000_000_000, ram / 12)
      if isApp, app.activationPolicy == .regular, app.memoryBytes >= heavy, launchedAgo >= 12 * 3600 {
        result.append(make(
          .relaunchHeavyApp, app, title: "Relaunch \(app.name)",
          reason: "\(app.name) has grown to \(memory(app.memoryBytes)) over \(Durations.phrase(launchedAgo)) open; reopening it usually gives most of that back.",
          facts: "\(memory(app.memoryBytes)) after \(shortDuration(launchedAgo)) open",
          confidence: pressured ? .high : .medium, actionable: true
        ))
        continue
      }

      // An unusual share of memory.
      let hog = pressured ? max(3_000_000_000, ram * 15 / 100) : ram / 4
      if app.memoryBytes >= hog {
        let share = Int((Double(app.memoryBytes) / Double(ram) * 100).rounded())
        result.append(make(
          .memoryHog, app, title: "\(app.name) is using a lot of memory",
          reason: "\(app.name) is using \(memory(app.memoryBytes)), \(share)% of this Mac’s memory\(pressured ? ", while memory is under pressure" : "").",
          facts: "\(memory(app.memoryBytes)) · \(share)% of memory",
          confidence: pressured ? .medium : .low, actionable: isApp
        ))
      }
    }

    result.sort {
      if $0.frees.memoryBytes != $1.frees.memoryBytes { return $0.frees.memoryBytes > $1.frees.memoryBytes }
      return $0.frees.cpuPercent > $1.frees.cpuPercent
    }
    return result
  }

  /// "45 min", "31 h", "3 days": a duration short enough for a facts line.
  static func shortDuration(_ seconds: TimeInterval) -> String {
    let minutes = Int(seconds / 60)
    if minutes < 90 { return "\(max(minutes, 1)) min" }
    let hours = Int((Double(minutes) / 60).rounded())
    if hours < 48 { return "\(hours) h" }
    return "\(Int((Double(hours) / 24).rounded())) days"
  }
}
