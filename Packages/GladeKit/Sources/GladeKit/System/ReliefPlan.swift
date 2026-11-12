import Foundation

/// Everything Glade would quit or shut down in one go to lighten the load, built from
/// the advisor’s suggestions: storage’s clean plan, for memory, processor and graphics.
///
/// Only what can be undone by opening it again is ever in the plan: asking an app to
/// quit (so it can ask about unsaved work), relaunching one, and shutting down a
/// simulator (its apps and data stay). Nothing is force quit.
///
/// Ticked for the person only when the advisor is confident, nothing casts doubt on it
/// and it hasn’t been used in the last few minutes: idle apps and idle simulators.
/// Relaunches, hogs, anything with a caveat and, during a game or full-screen video,
/// anything that goes with the app in front start unticked. What’s in front, playing
/// or recording sound, keeping the Mac awake or on the keep-running list never appears.
public struct ReliefPlan: Codable, Sendable, Equatable {
  /// One thing the plan would do.
  public struct Action: Codable, Sendable, Identifiable, Hashable {
    public enum Kind: String, Codable, Sendable {
      /// Ask the app to quit, as its Quit menu item would.
      case quit
      /// Quit and open again, for an app that has grown over a long session.
      case relaunch
      /// Shut a simulator down; its apps and data are kept.
      case shutDown
    }

    /// The suggestion’s id.
    public var id: String
    public var kind: Kind
    public var suggestionKind: PerformanceSuggestion.Kind
    /// `AppUsage.id`, or `simulator:<UDID>`.
    public var appID: String
    public var name: String
    public var bundlePath: String?
    public var simulatorUDID: String?
    public var simulatorSetPath: String?
    /// The memory it holds now, which is the most quitting it can give back.
    public var memoryBytes: Int64
    /// Share of one core.
    public var cpuPercent: Double
    public var gpuPercent: Double?
    /// The numbers in a few words: "Idle 3 h · 9.1 GB".
    public var facts: String
    /// Why it’s safe, in one sentence.
    public var why: String
    /// A doubt worth seeing before ticking it. Anything with one starts unticked.
    public var caveat: String?
    public var selectedByDefault: Bool

    public init(
      id: String, kind: Kind, suggestionKind: PerformanceSuggestion.Kind, appID: String, name: String,
      bundlePath: String? = nil, simulatorUDID: String? = nil, simulatorSetPath: String? = nil,
      memoryBytes: Int64, cpuPercent: Double = 0, gpuPercent: Double? = nil, facts: String, why: String,
      caveat: String? = nil, selectedByDefault: Bool
    ) {
      self.id = id
      self.kind = kind
      self.suggestionKind = suggestionKind
      self.appID = appID
      self.name = name
      self.bundlePath = bundlePath
      self.simulatorUDID = simulatorUDID
      self.simulatorSetPath = simulatorSetPath
      self.memoryBytes = memoryBytes
      self.cpuPercent = cpuPercent
      self.gpuPercent = gpuPercent
      self.facts = facts
      self.why = why
      self.caveat = caveat
      self.selectedByDefault = selectedByDefault
    }
  }

  /// An app the plan deliberately leaves out, and why in a word or two.
  public struct LeftAlone: Codable, Sendable, Hashable {
    public var name: String
    public var memoryBytes: Int64
    /// "in use", "playing sound", "on a call", "keeping the Mac awake", "kept running".
    public var reason: String

    public init(name: String, memoryBytes: Int64, reason: String) {
      self.name = name
      self.memoryBytes = memoryBytes
      self.reason = reason
    }
  }

  public var date: Date
  /// Largest first.
  public var actions: [Action]
  /// Largest first.
  public var leftAlone: [LeftAlone]
  /// The game or full-screen video in front, when there is one.
  public var heavyFrontApp: String?

  public init(date: Date = Date(), actions: [Action], leftAlone: [LeftAlone] = [], heavyFrontApp: String? = nil) {
    self.date = date
    self.actions = actions
    self.leftAlone = leftAlone
    self.heavyFrontApp = heavyFrontApp
  }

  /// Used within this many seconds counts as in use, whatever the advisor said.
  public static let recentSeconds: Double = 5 * 60
  /// Apps smaller than this aren’t named among what’s left alone.
  static let leftAloneMinimumBytes: Int64 = 200_000_000

  public var defaultSelection: Set<String> { Set(actions.filter(\.selectedByDefault).map(\.id)) }

  /// The memory the chosen actions hold now. Quitting gives back at most this, often a
  /// little less, so it’s shown as "about".
  public func memoryBytes(of chosen: Set<String>) -> Int64 {
    actions.filter { chosen.contains($0.id) }.reduce(0) { $0 + $1.memoryBytes }
  }

  /// The chosen actions, in the plan’s order.
  public func actions(_ chosen: Set<String>) -> [Action] {
    actions.filter { chosen.contains($0.id) }
  }

  /// One line naming the biggest of what’s left alone, grouped by reason: "Leaving
  /// Safari, Xcode and Music: in use", or "Leaving Safari: in use; Music: playing
  /// sound". `nil` when nothing is.
  public var leftAloneSummary: String? {
    guard !leftAlone.isEmpty else { return nil }
    let shown = Array(leftAlone.prefix(3))
    var reasons: [String] = []
    for item in shown where !reasons.contains(item.reason) { reasons.append(item.reason) }
    let groups = reasons.map { reason in
      "\(Format.listed(shown.filter { $0.reason == reason }.map(\.name))): \(reason)"
    }
    let more = leftAlone.count - shown.count
    return "Leaving " + groups.joined(separator: "; ") + (more > 0 ? "; \(more) more" : "")
  }

  // MARK: Building

  /// - Parameters:
  ///   - suggestions: From `PerformanceAdvisor.suggestions`, built from the same `apps`.
  ///   - apps: The live listing. Each app action is checked against it again, so an
  ///     app that has come to the front or started playing since is left out.
  public static func make(
    suggestions: [PerformanceSuggestion], apps: [AppUsage], context: ActivityContext?,
    simulators: [SimulatorUsage] = [], config: GladeConfig = ConfigStore.load(), now: Date = Date()
  ) -> ReliefPlan {
    let keep = Set(config.keepRunning.map { $0.lowercased() })
    let byID = Dictionary(apps.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    let frontID = context?.frontmostApp?.id
    let heavy = heavyFront(context: context, apps: apps)

    func kept(_ app: AppUsage) -> Bool {
      keep.contains(app.id.lowercased()) || keep.contains(app.name.lowercased())
        || app.bundleIdentifier.map { keep.contains($0.lowercased()) } == true
    }

    var actions: [Action] = []
    var included: Set<String> = []
    for suggestion in suggestions where suggestion.actionable {
      let kind: Action.Kind
      switch suggestion.kind {
      case .quitIdleApp, .memoryHog, .gpuHog: kind = .quit
      case .relaunchHeavyApp: kind = .relaunch
      case .shutDownIdleSimulator: kind = .shutDown
      // A process pinning a core is for the person to look at; battery suggestions
      // aren’t about memory.
      case .runawayProcess, .idleEnergyDrain, .forgottenAwakeHolder: continue
      }

      var caveat = suggestion.caveat
      var recent = suggestion.idleSeconds.map { $0 < recentSeconds } ?? false
      var bundlePath: String?
      var why: String
      if kind == .shutDown {
        guard let udid = suggestion.simulatorUDID else { continue }
        if let live = simulators.first(where: { $0.udid == udid }) {
          // Something has happened in it since the suggestion was made.
          if live.inUse || !live.isIdle { continue }
          if let last = live.lastActivity, now.timeIntervalSince(last) < recentSeconds { recent = true }
        } else if !simulators.isEmpty {
          continue
        }
        if keep.contains(udid.lowercased()) || keep.contains(suggestion.appName.lowercased()) { continue }
        why = "Nothing is running in it. Its apps and data are kept."
      } else {
        // The app must still be running and still be left alone by the person.
        guard let app = byID[suggestion.appID] else { continue }
        if app.isSystem || app.isGlade || app.isFrontmost || app.id == frontID || kept(app) { continue }
        if app.isPlayingAudio || app.isCapturingAudio || app.preventingSleep != nil { continue }
        if let last = app.lastActive, now.timeIntervalSince(last) < recentSeconds { recent = true }
        bundlePath = app.bundlePath
        if let heavy, heavy.family(app) {
          caveat = caveat ?? "Goes with \(heavy.name)"
        }
        why = whyQuit(app, suggestion: suggestion, now: now)
        if kind == .relaunch { why = "It has grown over a long session; reopening it usually gives most of that back." }
      }

      let selected = (kind == .quit && suggestion.kind == .quitIdleApp || kind == .shutDown)
        && suggestion.confidence == .high && caveat == nil && !recent
      if recent && caveat == nil { caveat = "Used in the last few minutes" }
      actions.append(Action(
        id: suggestion.id, kind: kind, suggestionKind: suggestion.kind, appID: suggestion.appID, name: suggestion.appName,
        bundlePath: bundlePath, simulatorUDID: suggestion.simulatorUDID, simulatorSetPath: suggestion.simulatorSetPath,
        memoryBytes: suggestion.frees.memoryBytes, cpuPercent: suggestion.frees.cpuPercent, gpuPercent: suggestion.frees.gpuPercent,
        facts: suggestion.facts ?? suggestion.reason, why: why, caveat: caveat, selectedByDefault: selected
      ))
      included.insert(suggestion.appID)
    }
    actions.sort { $0.memoryBytes > $1.memoryBytes }

    // What’s worth naming as left alone: sizeable apps the plan doesn’t touch because
    // the person is using them in some way.
    var leftAlone: [LeftAlone] = []
    for app in apps where app.kind == .app && !app.isSystem && !app.isGlade && !included.contains(app.id) {
      guard app.memoryBytes >= leftAloneMinimumBytes else { continue }
      let reason: String
      if app.isCapturingAudio {
        reason = "on a call"
      } else if app.isPlayingAudio {
        reason = "playing sound"
      } else if app.preventingSleep != nil {
        reason = "keeping the Mac awake"
      } else if kept(app) {
        reason = "kept running"
      } else if app.isFrontmost || app.id == frontID {
        reason = "in use"
      } else if app.activationPolicy == .regular, let last = app.lastActive,
        now.timeIntervalSince(last) < PerformanceAdvisor.idleMinutes * 60
      {
        reason = "in use"
      } else {
        continue
      }
      leftAlone.append(LeftAlone(name: app.name, memoryBytes: app.memoryBytes, reason: reason))
    }
    leftAlone.sort { $0.memoryBytes > $1.memoryBytes }

    return ReliefPlan(date: now, actions: actions, leftAlone: leftAlone, heavyFrontApp: heavy?.name)
  }

  /// The plan for this Mac right now, from one process listing.
  public static func current(
    sampler: SystemSampler = SystemSampler(), config: GladeConfig = ConfigStore.load()
  ) async -> (plan: ReliefPlan, apps: [AppUsage], snapshot: SystemSnapshot) {
    async let reading = sampler.snapshot()
    let processes = await sampler.processes()
    let apps = AppGrouper.group(processes)
    let simulators = await sampler.simulatorBreakdown(processes: processes).devices
    let snapshot = await reading
    let context = ActivityContext.current(apps: apps, power: snapshot.power)
    let suggestions = PerformanceAdvisor.suggestions(snapshot: snapshot, apps: apps, context: context, simulators: simulators, config: config)
    let plan = make(suggestions: suggestions, apps: apps, context: context, simulators: simulators, config: config)
    return (plan, apps, snapshot)
  }

  /// An action for an app the person named themselves, such as with
  /// `glade relieve --include`, which the rules didn’t offer. Never ticked by itself.
  /// Refused, with the reason, for anything the plan never touches: the app in front,
  /// anything playing or recording, keeping the Mac awake, kept running, macOS’s own
  /// apps and Glade.
  public static func namedAction(for app: AppUsage, config: GladeConfig = ConfigStore.load()) -> (action: Action?, refusal: String?) {
    guard app.kind == .app else { return (nil, "\(app.name) is a process, not an app, so it can’t be asked to quit") }
    let keep = Set(config.keepRunning.map { $0.lowercased() })
    if let reason = ReliefResult.inUse(app, keep: keep) { return (nil, "\(app.name): \(reason.prefix(1).lowercased() + reason.dropFirst())") }
    let action = Action(
      id: "named:\(app.id)", kind: .quit, suggestionKind: .quitIdleApp, appID: app.id, name: app.name,
      bundlePath: app.bundlePath, memoryBytes: app.memoryBytes, cpuPercent: app.cpuPercent, gpuPercent: app.gpuPercent,
      facts: Format.bytes(app.memoryBytes), why: "You named it. It can ask about unsaved work before it quits.",
      selectedByDefault: false
    )
    return (action, nil)
  }

  /// The action a person or agent means, by name, app id, bundle identifier or
  /// simulator UDID; a unique prefix of a name also counts.
  public func action(named target: String, apps: [AppUsage] = []) -> Action? {
    let wanted = target.trimmingCharacters(in: .whitespaces).lowercased()
    func bundleID(_ action: Action) -> String? { apps.first { $0.id == action.appID }?.bundleIdentifier?.lowercased() }
    if let exact = actions.first(where: {
      $0.name.lowercased() == wanted || $0.appID.lowercased() == wanted || $0.simulatorUDID?.lowercased() == wanted
        || bundleID($0) == wanted
    }) {
      return exact
    }
    let prefixed = actions.filter { $0.name.lowercased().hasPrefix(wanted) }
    return prefixed.count == 1 ? prefixed[0] : nil
  }

  /// The selection a person or agent asked for by name: the default ticks (none with
  /// `only`), plus `include`, minus `exclude`. An app named in `include` that the rules
  /// didn’t offer is added when it may be asked to quit. Returns the ticked ids and a
  /// sentence for each name that couldn’t be honoured.
  public mutating func choose(
    include: [String], exclude: [String], only: Bool, apps: [AppUsage], config: GladeConfig = ConfigStore.load()
  ) -> (chosen: Set<String>, refused: [String]) {
    var chosen = only ? Set<String>() : defaultSelection
    var refused: [String] = []
    for name in include {
      if let action = action(named: name, apps: apps) {
        chosen.insert(action.id)
        continue
      }
      let wanted = name.trimmingCharacters(in: .whitespaces).lowercased()
      var matches = apps.filter {
        $0.kind == .app && ($0.name.lowercased() == wanted || $0.id.lowercased() == wanted || $0.bundleIdentifier?.lowercased() == wanted)
      }
      if matches.isEmpty { matches = apps.filter { $0.kind == .app && $0.name.lowercased().hasPrefix(wanted) } }
      guard matches.count == 1, let app = matches.first else {
        refused.append("“\(name)” isn’t running, or matches more than one app")
        continue
      }
      let named = Self.namedAction(for: app, config: config)
      if let action = named.action {
        actions.append(action)
        chosen.insert(action.id)
      } else if let refusal = named.refusal {
        refused.append(refusal)
      }
    }
    for name in exclude {
      if let action = action(named: name, apps: apps) { chosen.remove(action.id) } else { refused.append("“\(name)” isn’t in the plan") }
    }
    if !include.isEmpty || !exclude.isEmpty {
      Log.info(.system, "Free up memory: chose \(chosen.count) by name\(refused.isEmpty ? "" : "; left out: " + refused.joined(separator: "; "))")
    }
    return (chosen, refused)
  }

  /// Why quitting the app is safe, from what’s known about it.
  private static func whyQuit(_ app: AppUsage, suggestion: PerformanceSuggestion, now: Date) -> String {
    var parts: [String] = []
    if let idle = suggestion.idleSeconds ?? app.lastActive.map({ now.timeIntervalSince($0) }) {
      parts.append("not used for \(Durations.phrase(idle))")
    } else if app.isHidden {
      parts.append("hidden")
    }
    if app.windowCount == 0 { parts.append("no windows on screen") }
    parts.append("not playing sound")
    let sentence = Format.listed(parts)
    return sentence.prefix(1).uppercased() + sentence.dropFirst() + ". It can ask about unsaved work before it quits."
  }

  /// The game, or the app playing full-screen video, in front, and which other apps
  /// count as going with it: from the same maker, or (for games) another game or a
  /// game launcher.
  private struct HeavyFront {
    var name: String
    var bundleID: String?
    var gaming: Bool

    func family(_ app: AppUsage) -> Bool {
      if gaming && app.isGame { return true }
      guard let mine = bundleID.flatMap(Self.maker), let theirs = app.bundleIdentifier.flatMap(Self.maker) else { return false }
      return mine == theirs
    }

    /// The first two parts of a bundle identifier, such as `com.valvesoftware`.
    /// Apple’s own are left out, since they’re all one maker.
    static func maker(_ bundleID: String) -> String? {
      let parts = bundleID.lowercased().split(separator: ".")
      guard parts.count >= 3 else { return nil }
      let maker = parts.prefix(2).joined(separator: ".")
      return maker == "com.apple" ? nil : maker
    }
  }

  private static func heavyFront(context: ActivityContext?, apps: [AppUsage]) -> HeavyFront? {
    guard let context, let front = context.frontmostApp else { return nil }
    if context.isGaming { return HeavyFront(name: front.name, bundleID: front.bundleIdentifier, gaming: true) }
    let watching = context.signals.contains {
      $0.appID == front.id && ($0.kind == .playingAudio || $0.kind == .preventingSleep)
    }
    if front.isFullScreen && watching { return HeavyFront(name: front.name, bundleID: front.bundleIdentifier, gaming: false) }
    return nil
  }
}
