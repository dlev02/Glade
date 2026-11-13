import Foundation
import GladeKit

/// The network tools offered to agents. Readings name no network, address or device:
/// verdicts, numbers and app names only.
extension MCPTools {
  static let network: [MCPTool] = [
    MCPTool(
      name: "glade_network",
      description: "The connection now, with verdicts: how the Mac is connected (Wi-Fi band, signal, noise, link rate), latency to the router, the internet provider's first hop and the internet (typical, slowest 5%, worst, jitter, loss), which apps are sending and receiving most, VPN or proxy in the way, what the router reports (line up, its speed, device counts), the last speed test, and plain verdicts ordered problems first, each with evidence and a next step. Compare the segments to place a slowdown: router spikes with a weak signal are the Wi-Fi; a steady router and a slow internet are the line or beyond. Sends 27 pings; takes about 3 seconds. Use it first for any question about slow internet, buffering, lag or calls breaking up.",
      schema: #"{"type":"object","properties":{"devices":{"type":"boolean","description":"Also count devices on the network from the router (slower, up to 20 seconds)."}},"additionalProperties":false}"#,
      readOnly: true
    ) { arguments in
      JSONFiles.string(await NetworkStatus.current(devices: arguments["devices"]?.bool ?? false).forAI())
    },
    MCPTool(
      name: "glade_network_watch",
      description: "Watch latency second by second to the router, the provider's first hop and the internet, with the busiest app each second. Returns each target's summary and every spike with what was busiest then. Use it while a call stutters, a stream buffers or a game lags, to catch intermittent spikes a single reading misses. One ping a second to each.",
      schema: #"{"type":"object","properties":{"seconds":{"type":"integer","description":"How long, 5 to 60 (default 20)."}},"additionalProperties":false}"#,
      readOnly: true
    ) { arguments in
      let path = await NetworkPath.current()
      guard path.connected else { throw MCPFailure(message: "This Mac isn’t connected to a network.") }
      let seconds = min(60, max(5, arguments["seconds"]?.int ?? 20))
      let watch = await NetworkWatch.run(seconds: seconds, path: path, internetHost: ConfigStore.load().network.internetHost)
      return JSONFiles.string(watch.forAI())
    },
    MCPTool(
      name: "glade_network_apps",
      description: "What each app is sending and receiving right now (bytes a second over two seconds) and today's totals from what Glade recorded. Traffic leaving the Mac only, not loopback. Background transfers macOS makes for an app (nsurlsessiond) show under that daemon.",
      schema: #"{"type":"object","properties":{"limit":{"type":"integer","description":"How many apps (default 15)."}},"additionalProperties":false}"#,
      readOnly: true
    ) { arguments in
      let limit = arguments["limit"]?.int ?? 15
      let now = await TrafficReader.now(seconds: 2)
      let today = NetworkHistoryStore.load().byApp(since: Calendar.current.startOfDay(for: Date()))
      struct Report: Encodable {
        var now: [AppTraffic]
        var today: [NetworkHistory.Total]
      }
      return JSONFiles.string(Report(now: Array(now.prefix(limit)), today: Array(today.prefix(limit))))
    },
    MCPTool(
      name: "glade_network_usage",
      description: "Data this Mac used, recorded while Glade's app was open: total, and by day, app or network for today, the last 7 or the last 30 days, with when recording began and how much of the period Glade saw. Networks are anonymised as Network 1, 2…; the one in use now is marked. It includes traffic on the local network, so it isn't a provider's bill.",
      schema: #"{"type":"object","properties":{"period":{"type":"string","enum":["today","week","month"]},"by":{"type":"string","enum":["day","app","network"]}},"additionalProperties":false}"#,
      readOnly: true
    ) { arguments in
      let history = NetworkHistoryStore.load()
      let calendar = Calendar.current
      let days = ["today": 0, "week": 6, "month": 29][arguments["period"]?.string ?? "week"] ?? 6
      let start = calendar.startOfDay(for: Date().addingTimeInterval(-Double(days) * 86_400))
      let rows: [NetworkHistory.Total]
      switch arguments["by"]?.string ?? "day" {
      case "app": rows = history.byApp(since: start)
      case "network": rows = NetworkHistory.anonymised(history.byNetwork(since: start), current: WiFiLink.current()?.networkName)
      default: rows = history.byDay(since: start).map(\.total)
      }
      struct Report: Encodable {
        var total: NetworkHistory.Total
        var rows: [NetworkHistory.Total]
        var recordingSince: Date?
        var coverage: Double
      }
      return JSONFiles.string(Report(total: history.total(since: start), rows: rows, recordingSince: history.since, coverage: history.coverage(since: start)))
    },
    MCPTool(
      name: "glade_network_test",
      description: "macOS's speed test against Apple's servers: download and upload in Mbps, latency idle and while the line is full (the gap is bufferbloat, why calls stutter during uploads), and ratings for video calls, streaming, game streaming and uploading. It fills the connection and uses a lot of data (hundreds of MB, gigabytes on a fast line). Without confirm it returns what it would do and an estimate of the data. Ask the person before confirming. Refused on a hotspot or Low Data Mode unless they allowed it in Settings. `last` returns recent results without testing.",
      schema: #"{"type":"object","properties":{"confirm":{"type":"boolean","description":"Run the test. Ask the person first."},"last":{"type":"boolean","description":"Return the recent results only."},"seconds":{"type":"integer","description":"5 to 30 (default from settings)."}},"additionalProperties":false}"#,
      readOnly: false
    ) { arguments in
      if arguments["last"]?.bool == true { return JSONFiles.string(Array(SpeedTest.history().prefix(10))) }
      let config = ConfigStore.load()
      let seconds = min(30, max(5, arguments["seconds"]?.int ?? config.network.testSeconds))
      let path = await NetworkPath.current()
      guard arguments["confirm"]?.bool == true else {
        struct Plan: Encodable {
          var wouldRun: Bool
          var seconds: Int
          var estimatedBytes: Int64?
          var limitedConnection: Bool
        }
        return JSONFiles.string(Plan(wouldRun: false, seconds: seconds, estimatedBytes: SpeedTest.estimatedBytes(seconds: seconds, last: SpeedTest.last), limitedConnection: path.isLimited))
      }
      if path.isLimited, !config.network.agentTestsWhenLimited {
        throw MCPFailure(message: "This is a hotspot or Low Data Mode. The person can run a test themselves in Glade, or allow agents to in Settings › Network.")
      }
      Log.info(.mcp, "An agent ran a speed test")
      return JSONFiles.string(try await SpeedTest.run(seconds: seconds, path: path))
    },
    MCPTool(
      name: "glade_network_check",
      description: "How quickly one site or service answers, step by step (finding its address, connecting, securing, first reply), beside apple.com for comparison, with a sentence saying whether the delay is that service or the connection. One small request to each. Use it when one site or streaming service is slow but others are fine.",
      schema: #"{"type":"object","properties":{"site":{"type":"string","description":"A host name such as www.netflix.com."}},"required":["site"],"additionalProperties":false}"#,
      readOnly: true
    ) { arguments in
      guard let site = arguments["site"]?.string, !site.isEmpty else { throw MCPFailure(message: "Name a site, such as www.netflix.com.") }
      let checks = await SiteCheck.compare(site)
      struct Report: Encodable {
        var site: SiteCheck
        var control: SiteCheck
        var verdict: String
      }
      return JSONFiles.string(Report(site: checks[0], control: checks[1], verdict: SiteCheck.sentence(checks[0], control: checks[1])))
    },
  ]
}
