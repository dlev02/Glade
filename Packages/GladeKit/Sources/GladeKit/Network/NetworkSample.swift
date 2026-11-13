import Foundation

/// Made-up network readings for screenshots and sample data, the same on any Mac and
/// naming no real network or device.
public enum NetworkSample {
  public enum Scene: String, Sendable {
    /// Good Wi-Fi, quick replies.
    case healthy
    /// An app filling the upload while latency climbs.
    case uploading
    /// A weak signal with spikes to the router.
    case weakWiFi
  }

  public struct Readings: Sendable {
    public var status: NetworkStatus
    public var live: [NetworkWatch.Sample]
    public var traffic: [AppTraffic]
    public var tests: [SpeedTestResult]
    public var history: NetworkHistory
    public var signal: [Int]
  }

  public static func readings(_ scene: Scene, now: Date = Date()) -> Readings {
    let weak = scene == .weakWiFi
    let path = NetworkPath(
      connected: true, medium: .wifi, interface: "en0", isExpensive: false, isConstrained: false, router: "192.168.1.1",
      defaultInterface: "en0", vpns: [.init(name: "Tailscale", connected: true)], proxy: false
    )
    let wifi = WiFiLink(
      interface: "en0", rssi: weak ? -76 : -54, noise: -93, band: weak ? "2.4 GHz" : "5 GHz", channel: weak ? 6 : 149, widthMHz: weak ? 20 : 80,
      generation: "Wi-Fi 6", linkRateMbps: weak ? 72 : 864, security: "WPA3", networkName: "Home", accessPoint: nil
    )
    var traffic = [
      AppTraffic(id: "com.apple.Safari", name: "Safari", bundlePath: "/Applications/Safari.app", isSystem: false, received: 1_840_000, sent: 42_000),
      AppTraffic(id: "com.apple.Music", name: "Music", bundlePath: "/System/Applications/Music.app", isSystem: false, received: 320_000, sent: 4_000),
      AppTraffic(id: "com.apple.mail", name: "Mail", bundlePath: "/System/Applications/Mail.app", isSystem: false, received: 18_000, sent: 6_000),
      AppTraffic(id: "process:nsurlsessiond", name: "nsurlsessiond", bundlePath: nil, isSystem: true, received: 9_000, sent: 2_000),
    ]
    if scene == .uploading {
      traffic.insert(AppTraffic(id: "com.apple.dt.Xcode", name: "Xcode", bundlePath: "/Applications/Xcode.app", isSystem: false, received: 60_000, sent: 4_300_000), at: 0)
    }

    // Two minutes a second at a time, with the scene’s character.
    var live: [NetworkWatch.Sample] = []
    for second in 0..<seconds {
      let date = now.addingTimeInterval(Double(second - seconds))
      let wobble = sin(Double(second) / 3) * 0.6 + Double(second % 7) * 0.12
      var router = 3.1 + wobble
      var provider = 4.6 + wobble
      var internet = 7.2 + wobble
      if weak, second % 11 == 0 { router += 38 }
      if weak { router += 6; provider += 6; internet += 6 }
      let uploading = scene == .uploading && second > 70
      if uploading { provider += 70 + Double(second % 5) * 9; internet += 74 + Double(second % 5) * 9 }
      live.append(NetworkWatch.Sample(
        date: date, router: weak && second == 55 ? nil : router, provider: provider, internet: internet,
        busiest: uploading ? "Xcode" : "Safari", sending: uploading ? 4_300_000 : 50_000, receiving: 2_200_000
      ))
    }
    let latency = NetworkTargets.Kind.allCases.map { kind in
      NetworkStatus.Latency(kind: kind, host: nil, stats: LatencyStats(live.suffix(60).map { $0.value(kind) }))
    }

    let tests = [
      SpeedTestResult(
        date: now.addingTimeInterval(-2 * 3_600), seconds: 15, downloadMbps: 486, uploadMbps: 212, idleLatency: 9, busyLatency: 41,
        responsiveness: 1_460, dataUsedBytes: 1_310_000_000, interface: "en0", medium: "Wi-Fi", throughVPN: nil
      ),
      SpeedTestResult(
        date: now.addingTimeInterval(-26 * 3_600), seconds: 15, downloadMbps: 451, uploadMbps: 198, idleLatency: 10, busyLatency: 48,
        responsiveness: 1_250, dataUsedBytes: 1_200_000_000, interface: "en0", medium: "Wi-Fi", throughVPN: nil
      ),
      SpeedTestResult(
        date: now.addingTimeInterval(-3 * 86_400), seconds: 15, downloadMbps: 402, uploadMbps: 176, idleLatency: 11, busyLatency: 63,
        responsiveness: 950, dataUsedBytes: 1_100_000_000, interface: "en0", medium: "Wi-Fi", throughVPN: nil
      ),
    ]

    let router = RouterReport(
      kind: "Router", maker: "Example", model: "Gateway", firmware: nil, serial: nil,
      line: .init(connected: true, source: "Fibre", portMbps: 1000, received: nil, sent: nil, errors: 0, drops: 0),
      devices: (0..<23).map { index in
        let names = ["Living Room TV", "Kitchen Speaker", "iPad", "iPhone", "Printer", "Thermostat", "Doorbell", "Watch"]
        let connection = index % 3 == 0 ? "Ethernet" : index % 3 == 1 ? "Wi-Fi 5 GHz" : "Wi-Fi 2.4 GHz"
        return RouterReport.Device(
          name: index < names.count ? names[index] : nil, online: true, connection: connection,
          signalBars: connection == "Ethernet" ? nil : index % 5 == 2 ? 2 : 4, throughMesh: false, lastActive: nil
        )
      },
      read: now
    )

    var history = NetworkHistory()
    let calendar = Calendar.current
    for day in 0..<7 {
      let date = calendar.startOfDay(for: now.addingTimeInterval(-Double(6 - day) * 86_400)).addingTimeInterval(13 * 3_600)
      let gigabytes = [3.1, 4.6, 2.2, 6.8, 3.9, 5.4, 2.7][day]
      history.add(received: UInt64(gigabytes * 0.86e9), sent: UInt64(gigabytes * 0.14e9), network: "Home", seconds: 3_600, now: date)
      history.add(apps: [
        AppTraffic(id: "com.apple.Safari", name: "Safari", bundlePath: nil, isSystem: false, received: gigabytes * 0.4e9, sent: 0.02e9),
        AppTraffic(id: "com.apple.TV", name: "TV", bundlePath: nil, isSystem: false, received: gigabytes * 0.3e9, sent: 0.001e9),
        AppTraffic(id: "com.apple.dt.Xcode", name: "Xcode", bundlePath: nil, isSystem: false, received: gigabytes * 0.1e9, sent: gigabytes * 0.08e9),
      ], now: date)
    }
    history.since = now.addingTimeInterval(-6.5 * 86_400)

    var status = NetworkStatus(date: now, path: path, wifi: wifi, latency: latency, apps: traffic, router: router, lastTest: tests.first, verdicts: [])
    status.verdicts = NetworkDiagnosis.verdicts(.init(
      path: path, wifi: wifi, router: latency[0].stats, provider: latency[1].stats, internet: latency[2].stats,
      apps: traffic, routerReport: router, lastTest: tests.first
    ))
    let signal = (0..<60).map { (weak ? -76 : -54) + Int(sin(Double($0) / 4) * 3) }
    return Readings(status: status, live: live, traffic: traffic, tests: tests, history: history, signal: signal)
  }

  /// Two minutes, as the live chart keeps.
  static let seconds = 120
}
