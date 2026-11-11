import AppKit
import GladeKit
import Observation
import SwiftUI

/// Everything the interface shows and every action it can take. Screens read from
/// here and call its methods; none of them talk to the engine directly, so the
/// window, the menu bar and the command line all go through the same code.
@Observable
public final class AppModel {
  public enum Section: String, CaseIterable, Identifiable, Sendable {
    case overview, storage, performance, assistant, history

    public var id: String { rawValue }

    public var title: String {
      switch self {
      case .overview: "Overview"
      case .storage: "Storage"
      case .performance: "Performance"
      case .assistant: "Assistant"
      case .history: "History"
      }
    }

    public var symbol: String {
      switch self {
      case .overview: "gauge.with.dots.needle.33percent"
      case .storage: "internaldrive"
      case .performance: "waveform.path.ecg"
      case .assistant: "sparkles"
      case .history: "clock.arrow.trianglehead.counterclockwise.rotate.90"
      }
    }
  }

  public enum ScanState: Equatable, Sendable {
    case idle
    case scanning(done: Int, total: Int)
  }

  public enum CleanState: Equatable, Sendable {
    case idle
    case cleaning(done: Int, total: Int, title: String)
    case finished(receiptID: String)
    case failed(String)
  }

  public enum AssistantState: Equatable, Sendable {
    case idle
    /// What it’s doing, for a progress label.
    case thinking(String)
    case failed(String)
  }

  /// One turn in the conversation with the assistant.
  public struct Message: Identifiable, Sendable {
    public enum Role: Sendable { case person, assistant, problem }

    public var id = UUID()
    public var role: Role
    public var text: String
    public var date = Date()
    /// Which AI answered.
    public var provider: String?
    /// The model it used, when one was chosen.
    public var model: String?
    /// Set when the answer changed the storage plan.
    public var advice: StorageAdvice?
  }

  // MARK: Settings

  public var config: GladeConfig {
    didSet {
      guard config != oldValue else { return }
      // Sample data never writes the person’s own settings.
      if !isDemo { ConfigStore.save(config) }
      if config.level != oldValue.level || config.trashEverything != oldValue.trashEverything { rebuildPlan() }
      let automation = config.automation
      Task { await monitor.update(automation) }
    }
  }

  public var appearance: Appearance {
    didSet { defaults.set(appearance.rawValue, forKey: "appearance") }
  }

  public var accent: Accent {
    didSet { defaults.set(accent.rawValue, forKey: "accent") }
  }

  /// The person’s own accent colour as `#RRGGBB`, used when `accent` is `.custom`.
  public var customAccent: String {
    didSet { defaults.set(customAccent, forKey: "customAccent") }
  }

  /// Show free space next to the menu bar icon.
  public var menuBarShowsFreeSpace: Bool {
    didSet { defaults.set(menuBarShowsFreeSpace, forKey: "menuBarShowsFreeSpace") }
  }

  public var tint: Color { accent.color(custom: customAccent) }

  // MARK: Navigation

  public var section: Section = .overview
  /// Setup is showing (first launch, or reopened from the menu).
  public var showsSetup: Bool

  // MARK: Live readings

  public private(set) var snapshot: SystemSnapshot?
  /// Recent snapshots, oldest first, for the charts.
  public private(set) var history: [SystemSnapshot] = []
  public private(set) var apps: [AppUsage] = []
  public private(set) var context: ActivityContext?
  public private(set) var suggestions: [PerformanceSuggestion] = []
  /// Running simulators, each with the memory it holds.
  public private(set) var simulators: [SimulatorUsage] = []
  public private(set) var alerts: [ThresholdAlert] = []

  // MARK: Storage

  public private(set) var scan: ScanResult?
  public private(set) var scanState: ScanState = .idle
  /// While scanning: what was just looked at, and how much has been found so far.
  public private(set) var scanActivity: (title: String, found: Int64)?
  public private(set) var plan: CleanPlan?
  public private(set) var cleanState: CleanState = .idle
  public private(set) var receipts: [Receipt] = []
  /// Choices the person made by hand, which win over the plan.
  private var overrides: [String: Bool] = [:]

  // MARK: Assistant

  public private(set) var providers: [ProviderStatus] = []
  public private(set) var assistantState: AssistantState = .idle
  public private(set) var advice: StorageAdvice?
  public private(set) var messages: [Message] = []

  // MARK: Permissions

  public private(set) var hasFullDiskAccess = FullDiskAccess.isGranted
  public private(set) var notificationsAllowed = false

  // MARK: Internals

  private let defaults = UserDefaults.standard
  private let sampler = SystemSampler()
  private let monitor: ThresholdMonitor
  private var samplingTask: Task<Void, Never>?
  private var scanCancel: CancelFlag?
  /// How many windows or popovers are showing live readings.
  private var surfaces = 0
  /// How many of them need the per-app breakdown, which costs more.
  private var detailWatchers = 0
  private var tick = 0
  private var isLive = false
  /// Showing made-up findings and suggestions (`-demo YES`). Acting on a sample
  /// suggestion changes nothing.
  public private(set) var isDemo = false

  public init(live: Bool = true) {
    let loaded = live ? ConfigStore.load() : GladeConfig()
    config = loaded
    appearance = Appearance(rawValue: defaults.string(forKey: "appearance") ?? "") ?? .system
    accent = Accent(rawValue: defaults.string(forKey: "accent") ?? "") ?? .glade
    customAccent = defaults.string(forKey: "customAccent") ?? "#1C9A68"
    menuBarShowsFreeSpace = defaults.object(forKey: "menuBarShowsFreeSpace") as? Bool ?? false
    showsSetup = live && !defaults.bool(forKey: "setupComplete")
    // `-startSection storage` on the command line opens the window on that section,
    // which is how screenshots of each screen are taken.
    if let wanted = defaults.string(forKey: "startSection"), let start = Section(rawValue: wanted) {
      section = start
    }
    monitor = ThresholdMonitor(settings: loaded.automation, stateFile: live ? GladePaths.support.appendingPathComponent("alerts.json") : nil)
    isLive = live
  }

  /// Starts background work. Call once when the app launches.
  public func start() {
    // `-demo YES` shows made-up findings and only well-known apps, for screenshots
    // that don’t reveal anyone’s own files.
    if defaults.bool(forKey: "demo") {
      isLive = false
      isDemo = true
      // `-demoTrashEverything YES|NO` and `-demoLevel careful|balanced|aggressive` set
      // up a clean’s three outcomes (all to the Trash, all removed, mixed) for
      // screenshots, in memory only.
      if defaults.object(forKey: "demoTrashEverything") != nil { config.trashEverything = defaults.bool(forKey: "demoTrashEverything") }
      if let wanted = defaults.string(forKey: "demoLevel"), let level = CleanLevel(rawValue: wanted) { config.level = level }
      Task {
        var sample = await SampleData.capture()
        sample.apps = Self.demoApps(sample.apps)
        sample.suggestions = SampleData.sampleSuggestions(apps: sample.apps)
        loadSample(sample)
        // `-demoSetup YES` shows Setup over the sample data.
        if DemoState.value("demoSetup") != nil { showsSetup = true }
        // `-demoSetup signin` shows it with no AI ready yet, only one to sign in to.
        if DemoState.value("demoSetup") == "signin" {
          providers = [ProviderStatus(id: "claude", name: "Claude Code", state: .needsSignIn(hint: "Run `claude` in Terminal and sign in."))]
        }
        // `-demoConversation empty` starts the Assistant with nothing asked yet.
        if DemoState.value("demoConversation") == "empty" { messages = [] }
        // `-demoProvider claude` puts that AI first, in memory only.
        if let first = DemoState.value("demoProvider") {
          config.assistant.order = [first] + config.assistant.order.filter { $0 != first }
        }
        // `-demoTrashOnly YES` unticks what never goes to the Trash (simulators and
        // worktrees are removed by their own tools), as a person might, so a clean can
        // be all Trash.
        if DemoState.value("demoTrashOnly") != nil {
          setSelected(cleanItems.filter { !$0.goesToTrash(config) }.map(\.id), false)
        }
        // `-demoAsking YES` shows the assistant at work on the selection.
        if DemoState.value("demoAsking") != nil { assistantState = .thinking("Looking at what’s safe to clear…") }
        // `-demoScan YES` starts a (made-up) scan straight away.
        if DemoState.value("demoScan") != nil { startScan() }
        // `-demoAdvice short|long` starts with the assistant’s advice showing.
        if let length = defaults.string(forKey: "demoAdvice"), let scan {
          applySampleAdvice(SampleData.sampleAdvice(scan: scan, short: length == "short"))
          // `-demoAdvice earlier` then changes the selection by hand, so the advice
          // becomes an earlier selection.
          if length == "earlier", let first = cleanItems.first { setSelected(first.id, false) }
        }
      }
      return
    }
    guard isLive, samplingTask == nil else { return }
    Log.info(.app, "\(Brand.name) \(Brand.version) (\(Brand.build)) started; Full Disk Access \(hasFullDiskAccess ? "on" : "off")")
    if let last = ScanEngine.loadLast(), Date().timeIntervalSince(last.finished) < Cleaner.maximumScanAge {
      scan = last
      rebuildPlan()
    }
    receipts = Cleaner.receipts()
    NSWorkspace.shared.notificationCenter.addObserver(
      forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
    ) { note in
      let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
      ActivityLog.noteActivation(bundleID: app?.bundleIdentifier)
    }
    samplingTask = Task { [weak self] in
      while !Task.isCancelled {
        guard let self else { return }
        await self.sample()
        // Brisk while someone is looking, slow otherwise: the readings only have to
        // be fresh enough to notice a limit being crossed.
        try? await Task.sleep(for: .seconds(self.surfaces > 0 ? 2 : 15))
      }
    }
    Task {
      await refreshProviders()
      notificationsAllowed = await Notifier.isAllowed()
    }
  }

  public func finishSetup() {
    defaults.set(true, forKey: "setupComplete")
    showsSetup = false
  }

  // MARK: Live readings

  /// A window or popover showing live readings appeared. Pair with `surfaceDisappeared`.
  /// - Parameter detail: It shows the per-app breakdown too.
  public func surfaceAppeared(detail: Bool = false) {
    surfaces += 1
    if detail { detailWatchers += 1 }
    Task { await sample() }
  }

  public func surfaceDisappeared(detail: Bool = false) {
    surfaces = max(0, surfaces - 1)
    if detail { detailWatchers = max(0, detailWatchers - 1) }
  }

  private func sample() async {
    let reading = await sampler.snapshot()
    snapshot = reading
    history.append(reading)
    if history.count > 180 { history.removeFirst(history.count - 180) }
    tick += 1

    // The per-app breakdown costs a few milliseconds, so only do it when it’s on
    // screen, and then every other reading.
    if detailWatchers > 0, tick % 2 == 0 || apps.isEmpty {
      await refreshApps()
    }
    for alert in await monitor.ingest(reading) {
      alerts.insert(alert, at: 0)
      if alerts.count > 20 { alerts.removeLast() }
      await handle(alert)
    }
  }

  /// Sample data shows only well-known apps, never the person’s own.
  private static func demoApps(_ apps: [AppUsage]) -> [AppUsage] {
    let known = ["Xcode", "Safari", "Mail", "Messages", "Music", "Finder", "Simulator", "Simulator devices", "Docker", "Notes", "Photos", "Terminal", "Calendar", "Preview", "TV", "Podcasts", "Maps", "Reminders", "Glade"]
    var shown = apps.filter { app in known.contains(app.name) || app.bundleIdentifier?.hasPrefix("com.apple.") == true }
    // `-demoGraphics YES` gives a few apps a share of the graphics chip, so the
    // Graphics column shows.
    if DemoState.value("demoGraphics") != nil {
      let shares: [String: Double] = ["Safari": 6.4, "Simulator": 12.8, "Xcode": 3.1, "Music": 0.8]
      for index in shown.indices { if let share = shares[shown[index].name] { shown[index].gpuPercent = share } }
    }
    return shown
  }

  public func refreshApps() async {
    var listing = await sampler.apps()
    if isDemo { listing = Self.demoApps(listing) }
    let current = ActivityContext.current(apps: listing, power: snapshot?.power)
    // Only worth working out when simulators are actually running.
    let running = listing.contains { $0.name.localizedCaseInsensitiveContains("simulator") }
    let devices = running ? await sampler.simulators() : []
    apps = listing
    context = current
    simulators = devices
    // Sample suggestions stay as they are, so they never name the person’s own apps.
    if let snapshot, !isDemo {
      suggestions = PerformanceAdvisor.suggestions(
        snapshot: snapshot, apps: listing, context: current, simulators: devices, config: config
      )
    }
  }

  /// Shuts a simulator down, as turning a phone off would: its apps stop, its data stays.
  @discardableResult
  public func shutDown(_ simulator: SimulatorUsage) async -> String {
    do {
      let result = try await SimulatorControl.shutdown(simulator)
      await refreshApps()
      return result.message
    } catch {
      return error.localizedDescription
    }
  }

  private func handle(_ alert: ThresholdAlert) async {
    var body = alert.body
    if alert.kind == .lowStorage, config.automation.autoCleanOnLowStorage {
      if let freed = await automaticClean(), freed > 0 { body += " Glade freed \(Format.bytes(freed)) of caches." }
    } else if alert.kind == .lowStorage, let scan {
      let plan = Planner.plan(scan: scan, level: config.level, config: config)
      if plan.immediateBytes > 0 {
        body += " A \(config.level.title) clean would free \(Format.bytes(plan.immediateBytes))."
      } else if plan.selectedBytes > 0 {
        body += " A \(config.level.title) clean would move \(Format.bytes(plan.selectedBytes)) to the Trash."
      }
    } else if alert.kind == .memoryPressure || alert.kind == .sustainedCPU {
      await refreshApps()
      if let top = suggestions.first(where: \.actionable) { body += " \(top.title)." }
    }
    await Notifier.post(title: alert.title, body: body, kind: alert.kind.rawValue)
    if config.assistant.proactive { await checkIn(about: alert) }
  }

  /// Has the assistant look at what set off an alert, when the person has switched
  /// that on. Counted against the runs-a-day limit they chose.
  private func checkIn(about alert: ThresholdAlert) async {
    do {
      if alert.kind == .lowStorage {
        if scan == nil || Date().timeIntervalSince(scan?.finished ?? .distantPast) > 6 * 3600 {
          let fresh = await ScanEngine.run(config: config)
          ScanEngine.save(fresh)
          scan = fresh
          rebuildPlan()
        }
        guard let scan else { return }
        if apps.isEmpty { await refreshApps() }
        let base = Planner.plan(scan: scan, level: config.level, config: config)
        let result = try await Assistant.advise(
          scan: scan, plan: base, goal: "Free space is low (\(alert.body)) Suggest what to clear.",
          activity: MacDescription.activity(context: context, apps: apps), config: config, proactive: true,
          providers: AgentProviders.all
        )
        plan = result.plan
        advice = result.advice
        overrides = [:]
        messages.append(Message(role: .assistant, text: result.advice.summary, provider: result.advice.provider, model: result.advice.model, advice: result.advice))
        await Notifier.post(title: "\(Brand.name) has a plan", body: result.advice.summary, kind: "assistant")
      } else {
        await refreshApps()
        let description = MacDescription.build(
          snapshot: snapshot, apps: apps, context: context, suggestions: suggestions, scan: scan, plan: plan
        )
        let reply = try await Assistant.ask(
          "\(alert.title). \(alert.body) What is the cause, and what would you quit or shut down?",
          snapshot: description, config: config, proactive: true, providers: AgentProviders.all
        )
        messages.append(Message(role: .assistant, text: reply.answer, provider: reply.provider, model: reply.model))
        await Notifier.post(title: alert.title, body: String(reply.answer.prefix(220)), kind: "assistant")
      }
    } catch {
      Log.info(.agent, "Proactive check-in skipped: \(error.localizedDescription)")
    }
  }

  /// The Careful clean, run unattended because the person switched that on.
  private func automaticClean() async -> Int64? {
    let result = await ScanEngine.run(config: config)
    ScanEngine.save(result)
    let ids = Planner.plan(scan: result, level: .careful, config: config).selectedIDs
    guard !ids.isEmpty, let receipt = try? await Cleaner.clean(
      ids: ids, from: result, config: config,
      options: CleanOptions(dryRun: false, initiator: .automation(rule: "low storage"))
    ) else { return nil }
    scan = result.removing(receipt)
    if let scan { ScanEngine.save(scan) }
    rebuildPlan()
    receipts = Cleaner.receipts()
    return receipt.freedBytes
  }

  // MARK: Scanning

  public var isScanning: Bool { scanState != .idle }

  public func startScan(deep: Bool = false) {
    guard !isScanning else { return }
    let cancel = CancelFlag()
    scanCancel = cancel
    scanState = .scanning(done: 0, total: 1)
    scanActivity = nil
    hasFullDiskAccess = FullDiskAccess.isGranted
    let config = config
    // Sample data never scans the real disk: a made-up scan walks through the same
    // steps and ends where it started.
    if isDemo, let sample = scan {
      Task { await simulateScan(sample, cancel: cancel) }
      return
    }
    Task {
      let result = await ScanEngine.run(config: config, deep: deep, cancel: cancel) { [weak self] progress in
        Task { @MainActor in
          guard let self, self.isScanning else { return }
          self.scanState = .scanning(done: progress.finished, total: progress.total)
          self.scanActivity = (progress.message, progress.foundBytes)
        }
      }
      if !cancel.isCancelled {
        ScanEngine.save(result)
        scan = result
        overrides = [:]
        advice = nil
        rebuildPlan()
      }
      scanState = .idle
    }
  }

  /// Demo mode only: shows a scan’s progress over the sample findings.
  private func simulateScan(_ sample: ScanResult, cancel: CancelFlag) async {
    let steps = ["Xcode build data", "Simulators", "Package caches", "AI models", "Agent sessions", "Worktrees", "App caches", "Downloads & installers", "Large files", "Logs"]
    let total = sample.findings.filter { $0.within == nil }.reduce(Int64(0)) { $0 + $1.bytes }
    for (index, title) in steps.enumerated() {
      try? await Task.sleep(for: .milliseconds(900))
      if cancel.isCancelled { break }
      scanState = .scanning(done: index + 1, total: steps.count)
      scanActivity = (title, total * Int64(index + 1) / Int64(steps.count))
    }
    scanState = .idle
  }

  public func cancelScan() {
    scanCancel?.cancel()
  }

  // MARK: The plan and selection

  public var level: CleanLevel {
    get { config.level }
    set { config.level = newValue }
  }

  private func rebuildPlan() {
    guard let scan else {
      plan = nil
      return
    }
    plan = Planner.plan(scan: scan, level: config.level, config: config)
    advice = nil
  }

  public func isSelected(_ id: String) -> Bool {
    if let choice = overrides[id] { return choice }
    return plan?.items.first { $0.id == id }?.selected ?? false
  }

  /// Why the plan did or didn’t select a finding.
  public func reason(for id: String) -> String? {
    if overrides[id] != nil { return "You chose this." }
    return plan?.items.first { $0.id == id }?.reason
  }

  /// Selects or deselects a finding by hand. Blocked findings can’t be selected.
  public func setSelected(_ id: String, _ selected: Bool) {
    guard let finding = scan?.finding(id), !(selected && finding.isBlocked) else { return }
    overrides[id] = selected
  }

  public func setSelected(_ ids: [String], _ selected: Bool) {
    for id in ids { setSelected(id, selected) }
  }

  /// Drops hand-made choices and goes back to what the level selects.
  public func resetSelection() {
    overrides = [:]
  }

  public var hasManualChoices: Bool { !overrides.isEmpty }

  public var selectedIDs: [String] {
    scan?.findings.map(\.id).filter { isSelected($0) } ?? []
  }

  /// What a clean of the selection works through, biggest first: each finding once,
  /// leaving out any inside another selected one (it goes with it). Every count of
  /// items, in the clean bar, the inspector, the confirmation and the result, is this.
  public var cleanItems: [Finding] {
    guard let scan else { return [] }
    return Planner.topLevel(selectedIDs, in: scan).sorted { $0.bytes > $1.bytes }
  }

  /// The selection’s total, with nested folders counted once.
  public var selectedBytes: Int64 { totals.selected }
  /// How much of it is freed straight away.
  public var immediateBytes: Int64 { totals.immediate }
  /// How much of it goes to the Trash, which frees nothing until it is emptied.
  public var trashBytes: Int64 {
    let totals = totals
    return max(0, totals.selected - totals.immediate)
  }

  private var totals: (selected: Int64, immediate: Int64) {
    guard let scan, var copy = plan else { return (0, 0) }
    let chosen = Set(selectedIDs)
    copy.items = scan.findings.map { PlanItem(id: $0.id, selected: chosen.contains($0.id), reason: "") }
    Planner.total(&copy, scan: scan, config: config)
    return (copy.selectedBytes, copy.immediateBytes)
  }

  // MARK: Cleaning

  public var isCleaning: Bool {
    if case .cleaning = cleanState { return true }
    return false
  }

  /// Removes everything selected.
  public func clean() async {
    guard let scan, !isCleaning else { return }
    // Only the outermost of nested findings: the rest go with them.
    let ids = cleanItems.map(\.id)
    guard !ids.isEmpty else { return }
    cleanState = .cleaning(done: 0, total: ids.count, title: "")
    // Sample findings point at real places in the home folder, so a demo clean only
    // pretends: nothing is removed and the real last scan is left alone.
    if isDemo {
      await simulateClean(ids: ids, scan: scan)
      return
    }
    do {
      let receipt = try await Cleaner.clean(
        ids: ids, from: scan, config: config, options: CleanOptions(dryRun: false, initiator: .user)
      ) { [weak self] done, total, title in
        Task { @MainActor in
          guard let self, self.isCleaning else { return }
          self.cleanState = .cleaning(done: done, total: total, title: title)
        }
      }
      let remaining = scan.removing(receipt)
      ScanEngine.save(remaining)
      self.scan = remaining
      overrides = [:]
      rebuildPlan()
      receipts = Cleaner.receipts()
      cleanState = .finished(receiptID: receipt.id)
    } catch {
      cleanState = .failed(error.localizedDescription)
    }
  }

  /// Demo mode only: walks through the selection as a clean would and records what
  /// it would have done, without touching the disk.
  private func simulateClean(ids: [String], scan: ScanResult) async {
    var entries: [ReceiptEntry] = []
    for (index, id) in ids.enumerated() {
      guard let finding = scan.finding(id) else { continue }
      cleanState = .cleaning(done: index, total: ids.count, title: finding.title)
      try? await Task.sleep(for: .milliseconds(120))
      let trashed = finding.goesToTrash(config)
      let outcome: RemovalOutcome = trashed
        ? .trashed(locations: Dictionary(uniqueKeysWithValues: finding.paths.map { ($0, "~/.Trash/" + ($0 as NSString).lastPathComponent) }))
        : .deleted
      entries.append(ReceiptEntry(
        id: finding.id, title: finding.title, category: finding.category, paths: finding.paths,
        bytes: finding.bytes, outcome: outcome
      ))
    }
    // Only what was deleted frees space; the Trash holds on to the rest.
    let freed = entries.reduce(Int64(0)) { $0 + ($1.outcome == .deleted ? $1.bytes : 0) }
    let receipt = Receipt(
      id: UUID().uuidString, date: Date(), initiator: .user, dryRun: false, entries: entries,
      freeBefore: scan.volume.availableBytes, freeAfter: scan.volume.availableBytes + freed
    )
    self.scan = scan.removing(receipt)
    receipts.insert(receipt, at: 0)
    resetSelection()
    cleanState = .finished(receiptID: receipt.id)
  }

  public func dismissCleanResult() {
    cleanState = .idle
  }

  public func receipt(_ id: String) -> Receipt? {
    receipts.first { $0.id == id }
  }

  /// Moves a clean’s Trash items back where they were.
  @discardableResult
  public func putBack(_ receipt: Receipt) -> Cleaner.RestoreResult {
    if isDemo { return Self.pretendRestore(receipt) }
    return Cleaner.restore(receipt)
  }

  // MARK: Assistant

  public func refreshProviders() async {
    providers = await AgentProviders.statuses()
  }

  /// The provider that would answer right now, in the person’s preferred order.
  public var activeProvider: ProviderStatus? {
    let ordered = config.assistant.order.compactMap { id in providers.first { $0.id == id } }
      + providers.filter { !config.assistant.order.contains($0.id) }
    return ordered.first(where: \.isReady)
  }

  /// Asks the assistant to refine the plan at the current level.
  public func adviseStorage(goal: String? = nil) async {
    guard let scan else { return }
    assistantState = .thinking("Looking at what’s safe to clear…")
    // Sample data is never sent to a real AI; a made-up answer arrives instead.
    if isDemo {
      try? await Task.sleep(for: .seconds(2.5))
      applySampleAdvice(SampleData.sampleAdvice(scan: scan))
      assistantState = .idle
      return
    }
    let base = Planner.plan(scan: scan, level: config.level, config: config)
    if apps.isEmpty { await refreshApps() }
    do {
      let result = try await Assistant.advise(
        scan: scan, plan: base, goal: goal, activity: MacDescription.activity(context: context, apps: apps),
        config: config, providers: AgentProviders.all
      )
      plan = result.plan
      advice = result.advice
      overrides = [:]
      messages.append(Message(role: .assistant, text: result.advice.summary, provider: result.advice.provider, model: result.advice.model, advice: result.advice))
      assistantState = .idle
    } catch {
      messages.append(Message(role: .problem, text: error.localizedDescription))
      assistantState = .failed(error.localizedDescription)
    }
  }

  /// Sends a question. Requests to free space change the plan; anything else gets a
  /// written answer.
  public func ask(_ question: String) async {
    let text = question.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !text.isEmpty else { return }
    messages.append(Message(role: .person, text: text))
    let lowered = text.lowercased()
    let wantsSpace = ["free", "clean", "clear", "space", "storage", " gb", "delete", "remove"].contains { lowered.contains($0) }
    if wantsSpace, scan != nil {
      await adviseStorage(goal: text)
      return
    }
    assistantState = .thinking("Thinking…")
    if isDemo {
      try? await Task.sleep(for: .seconds(2.5))
      messages.append(Message(role: .assistant, text: SampleData.formattedAnswer(snapshot: snapshot, apps: apps), provider: "claude"))
      assistantState = .idle
      return
    }
    await refreshApps()
    let description = MacDescription.build(
      snapshot: snapshot, apps: apps, context: context, suggestions: suggestions, scan: scan, plan: plan
    )
    do {
      let reply = try await Assistant.ask(text, snapshot: description, config: config, providers: AgentProviders.all)
      messages.append(Message(role: .assistant, text: reply.answer, provider: reply.provider, model: reply.model))
      assistantState = .idle
    } catch {
      messages.append(Message(role: .problem, text: error.localizedDescription))
      assistantState = .failed(error.localizedDescription)
    }
  }

  /// Demo mode only: applies made-up advice the way a real run’s would be.
  private func applySampleAdvice(_ sample: StorageAdvice?) {
    guard let sample, let scan, var updated = plan else { return }
    for note in sample.select { if let index = updated.items.firstIndex(where: { $0.id == note.id }) { updated.items[index].selected = true } }
    for note in sample.deselect { if let index = updated.items.firstIndex(where: { $0.id == note.id }) { updated.items[index].selected = false } }
    Planner.total(&updated, scan: scan, config: config)
    plan = updated
    overrides = [:]
    // The answer names the total the clean bar now shows.
    var answer = sample
    answer.summary = answer.summary.replacingOccurrences(of: "{total}", with: Format.bytes(immediateBytes))
    advice = answer
    messages.append(Message(role: .assistant, text: answer.summary, provider: answer.provider, model: answer.model, advice: answer))
  }

  public func clearConversation() {
    messages = []
    assistantState = .idle
  }

  // MARK: Apps

  /// Asks an app to quit. Returns a sentence describing what happened.
  @discardableResult
  public func quit(_ app: AppUsage, force: Bool = false) async -> String {
    do {
      let result = force ? try await AppControl.forceQuit(app.id) : try await AppControl.quit(app.id)
      await refreshApps()
      return result.message
    } catch {
      return error.localizedDescription
    }
  }

  @discardableResult
  public func relaunch(_ app: AppUsage) async -> String {
    do {
      let result = try await AppControl.relaunch(app.id)
      await refreshApps()
      return result.message
    } catch {
      return error.localizedDescription
    }
  }

  /// Adds or removes an app from the list the assistant never suggests quitting.
  public func setKeepRunning(_ app: AppUsage, _ keep: Bool) {
    let key = app.bundleIdentifier ?? app.name
    config.keepRunning.removeAll { $0 == key }
    if keep { config.keepRunning.append(key) }
  }

  public func keepsRunning(_ app: AppUsage) -> Bool {
    config.keepRunning.contains(app.bundleIdentifier ?? app.name)
  }

  // MARK: Permissions

  public func refreshPermissions() async {
    // Sample data stands for a Mac with access on, so every screen agrees.
    if !isDemo { hasFullDiskAccess = FullDiskAccess.isGranted }
    notificationsAllowed = await Notifier.isAllowed()
  }

  public func requestNotifications() async {
    notificationsAllowed = await Notifier.request()
  }

  public func openFullDiskAccessSettings() {
    NSWorkspace.shared.open(FullDiskAccess.settingsURL)
  }

  // MARK: Derived values for display

  /// The disk drawn as a bar: reclaimable space by family, then everything else.
  public var storageSegments: [BarSegment] {
    guard let volume = snapshot?.disk ?? scan?.volume else { return [] }
    var segments: [BarSegment] = []
    var reclaimable: Int64 = 0
    if let scan {
      var totals: [CategoryFamily: Int64] = [:]
      for finding in scan.findings where finding.within == nil {
        totals[finding.category.family, default: 0] += finding.bytes
      }
      for family in CategoryFamily.allCases {
        let bytes = totals[family] ?? 0
        guard bytes > 0 else { continue }
        reclaimable += bytes
        segments.append(BarSegment(id: family.rawValue, title: family.title, bytes: bytes, color: family.color))
      }
    }
    let other = max(0, volume.usedBytes - reclaimable)
    segments.append(BarSegment(id: "other", title: scan == nil ? "Used" : "Everything Else", bytes: other, color: Color.primary.opacity(0.16)))
    return segments
  }

  /// Fills the model with made-up data for rendering screens without touching the Mac.
  public func loadSample(_ sample: SampleData) {
    snapshot = sample.snapshot
    history = sample.history
    apps = sample.apps
    context = sample.context
    suggestions = sample.suggestions
    scan = sample.scan
    receipts = sample.receipts
    providers = sample.providers
    messages = sample.messages
    hasFullDiskAccess = true
    notificationsAllowed = true
    showsSetup = false
    rebuildPlan()
  }
}
