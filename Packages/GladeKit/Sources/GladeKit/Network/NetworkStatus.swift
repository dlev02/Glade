import Foundation

/// The network right now, in one reading: how the Mac is connected, the Wi-Fi link,
/// latency to the router, the provider and the internet, which apps are using it, what
/// the router reports, the last speed test, and the verdicts that follow.
///
/// Taking one sends 27 pings (a few kilobytes) and, if the router is one Glade knows,
/// reads its status page. Nothing else leaves the Mac.
public struct NetworkStatus: Codable, Sendable, Equatable {
  public struct Latency: Codable, Sendable, Equatable {
    public var kind: NetworkTargets.Kind
    /// The address pinged. Shown on this Mac only, never to an AI.
    public var host: String?
    public var stats: LatencyStats?

    public init(kind: NetworkTargets.Kind, host: String?, stats: LatencyStats?) {
      self.kind = kind
      self.host = host
      self.stats = stats
    }
  }

  public var date: Date
  public var path: NetworkPath
  public var wifi: WiFiLink?
  public var latency: [Latency]
  /// Bytes a second over two seconds, busiest first.
  public var apps: [AppTraffic]
  public var router: RouterReport?
  public var lastTest: SpeedTestResult?
  public var verdicts: [NetworkVerdict]

  public var headline: NetworkVerdict? { verdicts.first }
  public var receiving: Double { apps.map(\.received).reduce(0, +) }
  public var sending: Double { apps.map(\.sent).reduce(0, +) }

  public func latency(_ kind: NetworkTargets.Kind) -> LatencyStats? { latency.first { $0.kind == kind }?.stats }

  /// - Parameters:
  ///   - pings: Measure latency (27 pings in about two seconds).
  ///   - devices: Also read the router’s device list, which some routers take ten
  ///     seconds or more to build.
  public static func current(config: GladeConfig = ConfigStore.load(), pings: Bool = true, devices: Bool = false) async -> NetworkStatus {
    let path = await NetworkPath.current()
    let wifi = path.medium == .wifi ? WiFiLink.current() : nil
    var latency: [Latency] = []
    var router: RouterReport?
    async let traffic = TrafficReader.now(seconds: 2)
    if path.connected {
      async let report: RouterReport? = config.network.readRouter && path.router != nil
        ? RouterReader.read(router: path.router!, includeDevices: devices) : nil
      if pings {
        let targets = await NetworkTargets.current(path: path, internetHost: config.network.internetHost)
        latency = await withTaskGroup(of: Latency.self) { group in
          for kind in NetworkTargets.Kind.allCases {
            let host = targets.host(kind)
            group.addTask {
              guard let host else { return Latency(kind: kind, host: nil, stats: nil) }
              return Latency(kind: kind, host: host, stats: LatencyStats(await Pinger.burst(host)))
            }
          }
          var found: [Latency] = []
          for await item in group { found.append(item) }
          return NetworkTargets.Kind.allCases.compactMap { kind in found.first { $0.kind == kind } }
        }
      }
      router = await report
    }
    let apps = await traffic
    let lastTest = SpeedTest.last
    let verdicts = NetworkDiagnosis.verdicts(.init(
      path: path, wifi: wifi, router: latency.first { $0.kind == .router }?.stats, provider: latency.first { $0.kind == .provider }?.stats,
      internet: latency.first { $0.kind == .internet }?.stats, apps: apps, routerReport: router, lastTest: lastTest
    ))
    return NetworkStatus(date: Date(), path: path, wifi: wifi, latency: latency, apps: Array(apps.prefix(15)), router: router, lastTest: lastTest, verdicts: verdicts)
  }
}

extension NetworkStatus {
  /// The same reading with what identifies the network taken out, for an AI: no
  /// network or access point names, no addresses, and only counts of devices.
  public func forAI() -> NetworkStatus {
    var copy = self
    copy.wifi?.networkName = nil
    copy.wifi?.accessPoint = nil
    copy.path.router = nil
    // Which VPN is on matters; the ones merely set up don’t.
    copy.path.vpns = path.vpns.filter(\.connected)
    copy.latency = latency.map { Latency(kind: $0.kind, host: nil, stats: $0.stats) }
    copy.router = router?.forAI()
    copy.apps = apps.map(\.withoutHome)
    return copy
  }
}

extension RouterReport {
  /// Devices become anonymous: how each connects and its signal, no names.
  public func forAI(keepOffline: Bool = false) -> RouterReport {
    var copy = self
    copy.serial = nil
    copy.devices = devices?.map { Device(name: nil, online: $0.online, connection: $0.connection, signalBars: $0.signalBars, throughMesh: $0.throughMesh, lastActive: nil) }
      .filter { keepOffline || $0.online }
    return copy
  }
}

extension NetworkHistory {
  /// Network names replaced by “Network 1”, “Network 2”… in order of use, the one in
  /// use now marked, so an AI can tell home from a hotel without learning either name.
  public static func anonymised(_ totals: [Total], current: String?) -> [Total] {
    totals.enumerated().map { index, total in
      let generic = ["Wi-Fi", "Ethernet", "Other"].contains(total.name)
      var name = generic ? total.name : "Network \(index + 1)"
      if total.name == current { name += " (the one in use now)" }
      return Total(name: name, received: total.received, sent: total.sent)
    }
  }
}

extension NetworkWatch {
  /// Without the addresses pinged.
  public func forAI() -> NetworkWatch {
    var copy = self
    copy.summary = summary.map { NetworkStatus.Latency(kind: $0.kind, host: nil, stats: $0.stats) }
    return copy
  }
}
