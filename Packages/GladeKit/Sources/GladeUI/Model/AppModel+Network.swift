import CoreLocation
import GladeKit
import SwiftUI

/// The bookkeeping behind the Network section, kept out of observation.
final class NetworkWork {
  var recorder: NetworkRecorder?
  var recording = false
  /// How many screens show the Network section, and how many show per-app traffic
  /// (Network, or Performance with its Network column).
  var watchers = 0
  var trafficWatchers = 0
  var liveTask: Task<Void, Never>?
  var trafficTask: Task<Void, Never>?
  var lastStatus: Date?
  var location: CLLocationManager?
  /// Sample data is showing; live readings leave it alone.
  var frozen = false
}

extension AppModel {
  /// How often the whole reading (path, Wi-Fi, router) is taken again while Network shows.
  static let networkStatusSeconds: TimeInterval = 30

  // MARK: The section

  /// The Network section appeared. Pair with `networkDisappeared`.
  public func networkAppeared() {
    networkWork.watchers += 1
    trafficAppeared()
    guard isLive, !networkWork.frozen, config.network.enabled else { return }
    network.tests = SpeedTest.history()
    network.history = NetworkHistoryStore.load()
    network.littleSnitch = LittleSnitchRules.load()
    startLive()
  }

  public func networkDisappeared() {
    networkWork.watchers = max(0, networkWork.watchers - 1)
    trafficDisappeared()
    if networkWork.watchers == 0 {
      networkWork.liveTask?.cancel()
      networkWork.liveTask = nil
    }
  }

  /// Per-app traffic is on screen (Network, or Performance’s Network column).
  public func trafficAppeared() {
    networkWork.trafficWatchers += 1
    guard isLive, !networkWork.frozen, networkWork.trafficTask == nil, networkWork.watchers == 0 else { return }
    // Network’s own live stream measures traffic too; this loop is for Performance.
    networkWork.trafficTask = Task { [weak self] in
      let sampler = SystemSampler()
      while !Task.isCancelled {
        let traffic = await TrafficReader.now(seconds: 2, sampler: sampler)
        guard !Task.isCancelled, let self else { return }
        self.network.traffic = traffic
      }
    }
  }

  public func trafficDisappeared() {
    networkWork.trafficWatchers = max(0, networkWork.trafficWatchers - 1)
    if networkWork.trafficWatchers == 0 {
      networkWork.trafficTask?.cancel()
      networkWork.trafficTask = nil
    }
  }

  /// One ping a second to the router, the provider and the internet, `nettop` every two
  /// seconds, and the whole reading every half minute, until the section goes.
  private func startLive() {
    guard networkWork.liveTask == nil else { return }
    networkWork.trafficTask?.cancel()
    networkWork.trafficTask = nil
    networkWork.liveTask = Task { [weak self] in
      guard let self else { return }
      await self.refreshNetworkStatus(devices: true)
      guard let path = self.network.status?.path, path.connected, !Task.isCancelled else { return }
      let targets = await NetworkTargets.current(path: path, internetHost: self.config.network.internetHost)
      self.network.targets = targets
      var ticks = 0
      for await tick in NetworkWatch.live(targets: targets) {
        if Task.isCancelled { break }
        self.network.live.append(tick.sample)
        if self.network.live.count > NetworkState.liveLength { self.network.live.removeFirst(self.network.live.count - NetworkState.liveLength) }
        self.network.traffic = tick.apps
        ticks += 1
        if ticks % 2 == 0 {
          self.network.wifi = path.medium == .wifi ? WiFiLink.current() : nil
          if let wifi = self.network.wifi { self.noteSignal(wifi.rssi) }
        }
        if ticks % 3 == 0 { self.updateNetworkVerdicts() }
        if let last = self.networkWork.lastStatus, Date().timeIntervalSince(last) >= Self.networkStatusSeconds {
          await self.refreshNetworkStatus(devices: false)
          // A new network means new targets; start again on it.
          if self.network.status?.path.router != path.router {
            self.network.live = []
            self.networkWork.liveTask = nil
            self.startLive()
            return
          }
        }
      }
    }
  }

  func noteSignal(_ rssi: Int, at date: Date = Date()) {
    network.signal.append(HistoryChart.Point(date: date, value: min(100, max(0, Double(rssi + 90) / 60 * 100))))
    if network.signal.count > NetworkState.liveLength / 2 { network.signal.removeFirst(network.signal.count - NetworkState.liveLength / 2) }
  }

  /// Takes the whole reading without pinging; the live stream does the latency.
  func refreshNetworkStatus(devices: Bool) async {
    networkWork.lastStatus = Date()
    network.loadingRouter = devices && network.status?.router?.devices == nil
    let status = await NetworkStatus.current(config: config, pings: false, devices: devices || network.status?.router?.devices != nil)
    network.status = status
    network.loadingRouter = false
    network.wifi = status.wifi
    if let wifi = status.wifi { noteSignal(wifi.rssi) }
    if network.traffic.isEmpty { network.traffic = status.apps }
    updateNetworkVerdicts()
  }

  /// The verdicts from the last minute’s live latency, the Wi-Fi now and the apps now.
  func updateNetworkVerdicts() {
    guard let status = network.status else { return }
    network.verdicts = NetworkDiagnosis.verdicts(.init(
      path: status.path, wifi: network.wifi ?? status.wifi, router: network.stats(.router), provider: network.stats(.provider),
      internet: network.stats(.internet), apps: network.traffic, routerReport: status.router, lastTest: network.lastTest
    ))
  }

  // MARK: Speed test

  /// Roughly how much data a test would use, from the last one.
  public var speedTestEstimate: Int64? {
    SpeedTest.estimatedBytes(seconds: config.network.testSeconds, last: network.lastTest)
      ?? network.status?.router?.line?.portMbps.map { SpeedTest.estimatedBytes(seconds: config.network.testSeconds, mbps: Double($0)) }
  }

  public func runSpeedTest() async {
    guard !network.testing else { return }
    network.testing = true
    network.testStarted = Date()
    network.testProblem = nil
    defer {
      network.testing = false
      network.testStarted = nil
    }
    if isDemo {
      try? await Task.sleep(for: .seconds(2))
      return
    }
    let path = await NetworkPath.current()
    do {
      let result = try await SpeedTest.run(seconds: config.network.testSeconds, path: path)
      network.tests.insert(result, at: 0)
      updateNetworkVerdicts()
    } catch {
      network.testProblem = error.localizedDescription
    }
  }

  // MARK: Recording

  /// Called on every reading of the sampling loop; records data used once a minute.
  func sampleNetwork() async {
    guard isLive, config.network.enabled, !networkWork.recording else { return }
    networkWork.recording = true
    defer { networkWork.recording = false }
    if networkWork.recorder == nil { networkWork.recorder = NetworkRecorder() }
    if let updated = await networkWork.recorder?.record(), networkWork.watchers > 0 { network.history = updated }
  }

  /// Saves the data-used record, for when the app quits.
  public func flushNetwork() async {
    await networkWork.recorder?.flush()
  }

  // MARK: Location, for the Wi-Fi network’s name

  public var locationStatus: CLAuthorizationStatus {
    networkWork.location?.authorizationStatus ?? CLLocationManager().authorizationStatus
  }

  /// Asks macOS for Location access, which it requires before telling any app the
  /// Wi-Fi network’s name. Glade never asks where the Mac is.
  public func requestLocation() {
    let manager = networkWork.location ?? CLLocationManager()
    networkWork.location = manager
    manager.requestWhenInUseAuthorization()
    defaults.set(true, forKey: "networkSetupAsked")
    Log.info(.network, "Asked for Location access for the Wi-Fi network’s name")
  }

  public var networkSetupAsked: Bool {
    get { defaults.bool(forKey: "networkSetupAsked") }
    set { defaults.set(newValue, forKey: "networkSetupAsked") }
  }

  // MARK: Little Snitch

  /// Reads an export the person chose. Returns why not when it can’t be read.
  public func importLittleSnitch(_ url: URL) -> String? {
    let scoped = url.startAccessingSecurityScopedResource()
    defer { if scoped { url.stopAccessingSecurityScopedResource() } }
    do {
      let rules = try LittleSnitchRules.parse(try Data(contentsOf: url))
      try rules.save()
      network.littleSnitch = rules
      Log.info(.network, "Imported \(rules.rules.count) Little Snitch rules from a \(rules.source)")
      return nil
    } catch {
      Log.warning(.network, "Little Snitch export couldn’t be read: \(error.localizedDescription)")
      return error.localizedDescription
    }
  }

  /// Has the AI review the imported rules, in the Assistant’s conversation.
  /// - Parameter asked: The person typed the request, so it’s already on screen.
  public func reviewLittleSnitch(goal: String? = nil, asked: Bool = false) async {
    guard let rules = network.littleSnitch ?? LittleSnitchRules.load() else { return }
    section = .assistant
    if !asked { messages.append(Message(role: .person, text: "Review my Little Snitch rules")) }
    assistantState = .thinking("Reading \(rules.rules.count) Little Snitch rules…")
    do {
      let review = try await Assistant.reviewLittleSnitch(rules, request: goal, config: config, providers: AgentProviders.all)
      var text = review.summary
      for point in review.points { text += "\n\n**\(point.title)**  \n\(point.detail)" }
      if !review.remove.isEmpty {
        text += "\n\n### Worth deleting in Little Snitch\n" + review.remove.map { "- \($0.sentence)" }.joined(separator: "\n")
      }
      if !review.add.isEmpty {
        text += "\n\n\(review.add.count == 1 ? "One new rule is" : "\(review.add.count) new rules are") ready to import into Little Snitch as a group that starts switched off."
      }
      var message = Message(role: .assistant, text: text, provider: review.provider, model: review.model)
      message.rulesFile = review.rulesFile()
      messages.append(message)
      assistantState = .idle
    } catch {
      messages.append(Message(role: .problem, text: error.localizedDescription))
      assistantState = .failed(error.localizedDescription)
    }
  }

  // MARK: The Assistant

  /// The network for a question about it: what’s on screen if it’s fresh, else a new
  /// reading. `nil` for questions about anything else.
  func networkForAssistant(_ question: String) async -> NetworkStatus? {
    guard config.network.enabled, MacDescription.isAboutNetwork(question) else { return nil }
    if var status = network.status, Date().timeIntervalSince(status.date) < 60, !network.live.isEmpty {
      status.latency = NetworkTargets.Kind.allCases.map { NetworkStatus.Latency(kind: $0, host: nil, stats: network.stats($0)) }
      status.apps = network.traffic
      status.verdicts = network.verdicts
      return status
    }
    if isDemo { return network.status }
    return await NetworkStatus.current(config: config, devices: true)
  }

  // MARK: Sample data

  func loadNetworkSample(_ sample: NetworkState) {
    networkWork.frozen = true
    network = sample
  }
}
