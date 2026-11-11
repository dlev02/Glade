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
    /// What it's doing, for a progress label.
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
    /// Set when the answer changed the storage plan.
    public var advice: StorageAdvice?
  }

  // MARK: Settings

  public var config: GladeConfig {
    didSet {
      guard config != oldValue else { return }
      ConfigStore.save(config)
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

  /// The person's own accent colour as `#RRGGBB`, used when `accent` is `.custom`.
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

  public init(live: Bool = true) {
    let loaded = live ? ConfigStore.load() : GladeConfig()
    config = loaded
    appearance = Appearance(rawValue: defaults.string(forKey: "appearance") ?? "") ?? .system
    accent = Accent(rawValue: defaults.string(forKey: "accent") ?? "") ?? .glade
    customAccent = defaults.string(forKey: "customAccent") ?? "#1C9A68"
    menuBarShowsFreeSpace = defaults.object(forKey: "menuBarShowsFreeSpace") as? Bool ?? false
    showsSetup = live && !defaults.bool(forKey: "setupComplete")
    monitor = ThresholdMonitor(settings: loaded.automation, stateFile: live ? GladePaths.support.appendingPathComponent("alerts.json") : nil)
    isLive = live
  }

  /// Starts background work. Call once when the app launches.
  public func start() {
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

    // The per-app breakdown costs a few milliseconds, so only do it when it's on
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

  public func refreshApps() async {
    let listing = await sampler.apps()
    let current = ActivityContext.current(apps: listing, power: snapshot?.power)
    // Only worth working out when simulators are actually running.
    let running = listing.contains { $0.name.localizedCaseInsensitiveContains("simulator") }
    let devices = running ? await sampler.simulators() : []
    apps = listing
    context = current
    simulators = devices
    if let snapshot {
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
      if let freed = await automaticClean() { body += " Glade cleared \(Format.bytes(freed)) of caches." }
    } else if alert.kind == .lowStorage, let scan {
      let reclaim = Planner.plan(scan: scan, level: config.level, config: config).selectedBytes
      if reclaim > 0 { body += " A \(config.level.title) clean would free \(Format.bytes(reclaim))." }
    } else if alert.kind == .memoryPressure || alert.kind == .sustainedCPU {
      await refreshApps()
      if let top = suggestions.first(where: \.actionable) { body += " \(top.title)." }
    }
    await Notifier.post(title: alert.title, body: body, kind: alert.kind.rawValue)
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
    return receipt.removedBytes
  }

  // MARK: Scanning

  public var isScanning: Bool { scanState != .idle }

  public func startScan(deep: Bool = false) {
    guard !isScanning else { return }
    let cancel = CancelFlag()
    scanCancel = cancel
    scanState = .scanning(done: 0, total: 1)
    hasFullDiskAccess = FullDiskAccess.isGranted
    let config = config
    Task {
      let result = await ScanEngine.run(config: config, deep: deep, cancel: cancel) { [weak self] progress in
        Task { @MainActor in
          guard let self, self.isScanning else { return }
          self.scanState = .scanning(done: progress.finished, total: progress.total)
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

  /// Why the plan did or didn't select a finding.
  public func reason(for id: String) -> String? {
    if overrides[id] != nil { return "You chose this." }
    return plan?.items.first { $0.id == id }?.reason
  }

  /// Selects or deselects a finding by hand. Blocked findings can't be selected.
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

  /// The selection's total, with nested folders counted once.
  public var selectedBytes: Int64 { totals.selected }
  /// How much of it is freed straight away; the rest goes to the Trash first.
  public var immediateBytes: Int64 { totals.immediate }

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
    let ids = selectedIDs
    guard !ids.isEmpty else { return }
    cleanState = .cleaning(done: 0, total: ids.count, title: "")
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

  public func dismissCleanResult() {
    cleanState = .idle
  }

  public func receipt(_ id: String) -> Receipt? {
    receipts.first { $0.id == id }
  }

  /// Moves a clean's Trash items back where they were.
  @discardableResult
  public func putBack(_ receipt: Receipt) -> Cleaner.RestoreResult {
    Cleaner.restore(receipt)
  }

  // MARK: Assistant

  public func refreshProviders() async {
    providers = await AgentProviders.statuses()
  }

  /// The provider that would answer right now, in the person's preferred order.
  public var activeProvider: ProviderStatus? {
    let ordered = config.assistant.order.compactMap { id in providers.first { $0.id == id } }
      + providers.filter { !config.assistant.order.contains($0.id) }
    return ordered.first(where: \.isReady)
  }

  /// Asks the assistant to refine the plan at the current level.
  public func adviseStorage(goal: String? = nil) async {
    guard let scan else { return }
    assistantState = .thinking("Looking at what's safe to clear…")
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
      messages.append(Message(role: .assistant, text: result.advice.summary, provider: result.advice.provider, advice: result.advice))
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
    await refreshApps()
    let description = MacDescription.build(
      snapshot: snapshot, apps: apps, context: context, suggestions: suggestions, scan: scan, plan: plan
    )
    do {
      let reply = try await Assistant.ask(text, snapshot: description, config: config, providers: AgentProviders.all)
      messages.append(Message(role: .assistant, text: reply.answer, provider: reply.provider))
      assistantState = .idle
    } catch {
      messages.append(Message(role: .problem, text: error.localizedDescription))
      assistantState = .failed(error.localizedDescription)
    }
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
    hasFullDiskAccess = FullDiskAccess.isGranted
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
    segments.append(BarSegment(id: "other", title: scan == nil ? "Used" : "Everything Else", bytes: other, color: Color.primary.opacity(0.28)))
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
