import Foundation

/// Turns readings into answers by comparing the segments of the connection rather
/// than trusting any one number: spikes to the router with a weak signal mean the
/// Wi-Fi; a steady router with a slow internet means the line or beyond; an app
/// filling the upload while latency rises is the likely cause.
public enum NetworkDiagnosis {
  public struct Inputs: Sendable {
    public var path: NetworkPath
    public var wifi: WiFiLink?
    public var router: LatencyStats?
    public var provider: LatencyStats?
    public var internet: LatencyStats?
    /// Bytes a second, busiest first.
    public var apps: [AppTraffic]
    public var routerReport: RouterReport?
    public var lastTest: SpeedTestResult?

    public init(
      path: NetworkPath, wifi: WiFiLink?, router: LatencyStats?, provider: LatencyStats?, internet: LatencyStats?,
      apps: [AppTraffic], routerReport: RouterReport?, lastTest: SpeedTestResult?
    ) {
      self.path = path
      self.wifi = wifi
      self.router = router
      self.provider = provider
      self.internet = internet
      self.apps = apps
      self.routerReport = routerReport
      self.lastTest = lastTest
    }
  }

  /// Megabytes a second that count as “heavily”: 1.5 up is 12 megabits, enough to fill
  /// many home uploads; 6 down is 48 megabits.
  static let heavyUpload = 1_500_000.0
  static let heavyDownload = 6_000_000.0

  static func unsteady(_ stats: LatencyStats?, slow: Double, jitter: Double, loss: Double) -> Bool {
    guard let stats, stats.reachable else { return false }
    return (stats.slow ?? 0) > slow || (stats.jitter ?? 0) > jitter || stats.lossPercent >= loss
  }

  public static func verdicts(_ inputs: Inputs) -> [NetworkVerdict] {
    var verdicts: [NetworkVerdict] = []
    let path = inputs.path
    func add(_ id: String, _ severity: NetworkVerdict.Severity, _ title: String, _ detail: String, _ evidence: [String] = [], next: String? = nil) {
      verdicts.append(NetworkVerdict(id: id, severity: severity, title: title, detail: detail, evidence: evidence, nextStep: next))
    }
    func line(_ kind: NetworkTargets.Kind, _ stats: LatencyStats?) -> String? {
      stats.map { "\(kind.title): \($0.sentence)" }
    }

    guard path.connected else {
      add("offline", .problem, "Not connected", "This Mac isn’t on a network.", next: "Join a Wi-Fi network or plug in a cable.")
      return verdicts
    }

    if let line = inputs.routerReport?.line, line.connected == false {
      add("line-down", .problem, "Your internet line is down", "The \(inputs.routerReport?.title ?? "router") says its connection to the provider isn’t up.",
        ["Router: line down"], next: "Restart the router; if it stays down, it’s an outage to report to your provider.")
    }

    let routerReachable = inputs.router?.reachable ?? false
    let internetReachable = inputs.internet?.reachable ?? false
    if !routerReachable, !internetReachable, inputs.router != nil || inputs.internet != nil {
      add("unreachable", .problem, "Can’t reach the internet", "Neither the router nor the internet answered.",
        [line(.router, inputs.router), line(.internet, inputs.internet)].compactMap { $0 },
        next: "If you’re on a hotel or café network, open a web page to finish signing in.")
    }

    // The Wi-Fi itself.
    if let wifi = inputs.wifi, path.medium == .wifi {
      let evidence = ["Signal: \(wifi.rssi) dBm\(wifi.signalToNoise.map { ", \($0) dB above the noise" } ?? "")", wifi.band.map { "Band: \($0)" }].compactMap { $0 }
      if wifi.quality == .weak {
        add("wifi-weak", .problem, "Your Wi-Fi signal is weak here", "A weak signal slows everything and drops data now and then.", evidence,
          next: "Move closer to the router or a mesh point, or use a cable.")
      } else if wifi.quality == .fair {
        add("wifi-fair", .notice, "Your Wi-Fi signal is only fair", "Fine for browsing; video calls and game streaming may hitch.", evidence,
          next: "Closer to the router or a mesh point would help.")
      }
      if wifi.band == "2.4 GHz", (wifi.linkRateMbps ?? 0) < 150 {
        add("wifi-24", .notice, "On the slower 2.4 GHz band", "2.4 GHz reaches further but carries less and is more crowded.",
          evidence + (wifi.linkRateMbps.map { ["Link rate: \(Int($0)) Mbps"] } ?? []),
          next: "Nearer the router your Mac should move to 5 GHz by itself.")
      }
    }

    let routerShaky = unsteady(inputs.router, slow: 40, jitter: 15, loss: 5)
    let internetShaky = unsteady(inputs.internet, slow: 120, jitter: 25, loss: 3)
    let providerShaky = unsteady(inputs.provider, slow: 80, jitter: 20, loss: 5)
    if routerShaky {
      let wifi = path.medium == .wifi
      add("local-unsteady", .problem, wifi ? "Your Wi-Fi is delaying or dropping data" : "The connection to your router is unsteady",
        "Replies from your own router come back late or not at all, so the problem is inside your home network, before the internet.",
        [line(.router, inputs.router), line(.internet, inputs.internet)].compactMap { $0 },
        next: wifi ? "Move closer, use 5 GHz or a cable, or restart the router." : "Check the cable and restart the router.")
    } else if internetShaky {
      if providerShaky {
        add("line-unsteady", .problem, "The slowdown is on your internet line", "Your router answers quickly, but your provider’s first stop doesn’t, so it’s past your Wi-Fi.",
          [line(.router, inputs.router), line(.provider, inputs.provider), line(.internet, inputs.internet)].compactMap { $0 },
          next: "If it keeps up, restart the router, then report it to your provider.")
      } else {
        add("beyond-provider", .notice, "The slowdown is beyond your provider", "Your Wi-Fi and line look steady; the delay is further out on the internet.",
          [line(.router, inputs.router), line(.provider, inputs.provider), line(.internet, inputs.internet)].compactMap { $0 },
          next: "If one service is slow, the problem may be at its end.")
      }
    }

    // What this Mac is doing to its own connection.
    let busiestUp = inputs.apps.max { $0.sent < $1.sent }
    let busiestDown = inputs.apps.max { $0.received < $1.received }
    let baseline = inputs.lastTest?.idleLatency ?? 30
    let latencyRaised = (inputs.internet?.typical ?? 0) > baseline + 40 || internetShaky
    if let up = busiestUp, up.sent >= heavyUpload {
      let evidence = ["\(up.name): sending \(rate(up.sent))", line(.internet, inputs.internet)].compactMap { $0 }
      if latencyRaised {
        add("upload-saturating", .problem, "Uploads are making everything wait", "\(up.name) is filling your upload, and replies from the internet slowed down.", evidence,
          next: "Pause \(up.name)’s upload during calls or games, or let it finish.")
      } else {
        add("upload-heavy", .notice, "\(up.name) is uploading heavily", "Sending \(rate(up.sent)) right now.", evidence)
      }
    }
    if let down = busiestDown, down.received >= heavyDownload {
      add("download-heavy", .notice, "\(down.name) is downloading heavily", "Receiving \(rate(down.received)) right now, which leaves less for everything else.",
        ["\(down.name): receiving \(rate(down.received))"])
    }
    let macTraffic = inputs.apps.map(\.total).reduce(0, +)
    if internetShaky, !routerShaky, macTraffic < 500_000 {
      var evidence = ["This Mac: \(rate(macTraffic)) in total"]
      if let report = inputs.routerReport, report.devices != nil { evidence.append("\(report.online.count) devices online") }
      add("something-else", .notice, "Something else on your network may be busy", "This Mac is hardly using the network, yet replies are slow.", evidence,
        next: inputs.routerReport?.devices == nil ? "Check your router for other devices streaming or uploading." : "Another device streaming or uploading is the likely cause.")
    }

    // The route out.
    if path.vpnCarriesEverything {
      let name = path.vpns.first(where: \.connected)?.name ?? "A VPN"
      add("vpn", .notice, "Traffic goes through \(name)", "Everything takes a detour through the VPN, which adds delay and can slow some services.",
        ["Route: \(path.defaultInterface ?? "tunnel")"], next: "If one site or service is slow, try it with \(name) off.")
    }
    if path.proxy {
      add("proxy", .notice, "A web proxy is set", "Web traffic goes through a proxy set in System Settings.", next: "If sites are slow, check System Settings › Network › Proxies.")
    }
    if path.isLimited {
      add("limited", .notice, "You’re on a limited connection", path.medium == .cellular ? "This is a phone hotspot." : "macOS treats this network as costly or Low Data Mode is on.",
        next: "Speed tests and big downloads use your allowance here.")
    }

    if let test = inputs.lastTest, let added = test.addedWhenBusy, added > 100, Date().timeIntervalSince(test.date) < 7 * 86_400 {
      add("bufferbloat", .notice, "Your connection slows a lot when it’s busy", "The last speed test found replies took \(Int(added)) ms longer while the line was full. That is why calls stutter while something uploads.",
        ["Idle: \(test.idleLatency.map { LatencyStats.ms($0) } ?? "?")", "Busy: \(test.busyLatency.map { LatencyStats.ms($0) } ?? "?")"],
        next: "If your router has Smart Queue or QoS (sometimes called SQM), turning it on fixes this.")
    }

    if let report = inputs.routerReport, report.weakDevices >= 3 {
      add("devices-weak", .notice, "\(report.weakDevices) devices have a weak Wi-Fi signal", "Devices on one or two bars talk slowly, which takes air time from everyone.",
        ["\(report.online.count) devices online"], next: "A mesh point nearer them, or moving the router, would help the whole network.")
    }

    if !verdicts.contains(where: { $0.severity == .problem }) && !routerShaky && !internetShaky {
      var evidence = [line(.router, inputs.router), line(.internet, inputs.internet)].compactMap { $0 }
      if let wifi = inputs.wifi, path.medium == .wifi { evidence.insert(wifi.sentence, at: 0) }
      verdicts.insert(NetworkVerdict(
        id: "healthy", severity: .good, title: "Your connection looks healthy",
        detail: path.medium == .wifi ? "Good Wi-Fi, quick replies from the router and the internet." : "Quick replies from the router and the internet.",
        evidence: evidence, nextStep: nil
      ), at: 0)
    }
    return verdicts.enumerated().sorted { ($0.element.severity.listOrder, $0.offset) < ($1.element.severity.listOrder, $1.offset) }.map(\.element)
  }

  /// “2.4 MB/s”.
  public static func rate(_ bytesPerSecond: Double) -> String {
    "\(Format.bytes(Int64(bytesPerSecond)))/s"
  }
}
