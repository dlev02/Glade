import ArgumentParser
import Foundation
import GladeKit

/// The network: how good the connection is, where a slowdown is, what’s using it and
/// how much data has gone.
struct Network: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    abstract: "Check the connection: Wi-Fi, latency to the router and the internet, what’s using it, and where a slowdown is.",
    discussion: """
      `\(Brand.cli) network` pings the router, your provider and \(GladeConfig().network.internetHost) a few times \
      (a few kilobytes) and reads the router’s status page if Glade knows it. A speed test runs only \
      with `\(Brand.cli) network test --confirm`.
      """,
    subcommands: [NetworkNow.self, NetworkWatchCommand.self, NetworkApps.self, NetworkUsage.self, NetworkTest.self, NetworkRouter.self, NetworkRouterAccess.self, NetworkCheck.self],
    defaultSubcommand: NetworkNow.self
  )
}

struct NetworkNow: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "now",
    abstract: "The verdict and the readings behind it (the default)."
  )

  @OptionGroup var output: OutputOptions

  func run() async throws {
    let status = await NetworkStatus.current()
    emit(status, json: output.json) {
      for line in NetworkText.lines(status) { print(line) }
    }
  }
}

struct NetworkWatchCommand: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "watch",
    abstract: "Watch latency second by second, with what was busiest at each spike.",
    discussion: "One ping a second to the router, your provider and the internet: about 10 KB a minute. Use it while a call stutters or a stream buffers."
  )

  @OptionGroup var output: OutputOptions

  @Option(name: .customLong("for"), help: "How many seconds to watch (5 to 600).")
  var seconds = 30

  func run() async throws {
    let config = ConfigStore.load()
    let path = await NetworkPath.current()
    guard path.connected else { throw ValidationError("This Mac isn’t connected to a network.") }
    let live = !output.json
    if live { print("Watching for \(seconds) seconds…   router · provider · internet   (ms; ✕ lost)") }
    let watch = await NetworkWatch.run(seconds: seconds, path: path, internetHost: config.network.internetHost) { sample in
      guard live else { return }
      let cells = NetworkTargets.Kind.allCases.map { kind in sample.value(kind).map { String(format: "%6.1f", $0) } ?? "     ✕" }
      let busy = sample.busiest.map { "  \($0) ↑\(NetworkDiagnosis.rate(sample.sending))" } ?? ""
      print("\(sample.date.formatted(date: .omitted, time: .standard))  \(cells.joined(separator: "  "))\(busy)")
    }
    emit(watch, json: output.json) {
      print("")
      for item in watch.summary { print("\(item.kind.title): \(item.stats?.sentence ?? "not measured")\(item.stats?.jitter.map { ", jitter \(LatencyStats.ms($0))" } ?? "")") }
      if watch.spikes.isEmpty {
        print("No spikes.")
      } else {
        print("\n\(watch.spikes.count) spikes:")
        for spike in watch.spikes.prefix(12) {
          let value = spike.milliseconds.map { LatencyStats.ms($0) } ?? "lost"
          let cause = spike.busiest.map { " while \($0) was busiest (sending \(NetworkDiagnosis.rate(spike.sending)))" } ?? ""
          print("  \(spike.date.formatted(date: .omitted, time: .standard)) \(spike.kind.title): \(value)\(cause)")
        }
      }
    }
  }
}

struct NetworkApps: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "apps",
    abstract: "What each app is sending and receiving right now, and today’s totals."
  )

  @OptionGroup var output: OutputOptions

  @Option(name: .long, help: "How many apps.")
  var limit = 15

  func run() async throws {
    let now = await TrafficReader.now(seconds: 2)
    let history = NetworkHistoryStore.load()
    let today = history.byApp(since: Calendar.current.startOfDay(for: Date()))
    struct Report: Encodable {
      var now: [AppTraffic]
      var today: [NetworkHistory.Total]
      var recordingSince: Date?
    }
    let report = Report(now: Array(now.prefix(limit)), today: Array(today.prefix(limit)), recordingSince: history.since)
    emit(report, json: output.json) {
      print("Right now (per second):")
      if report.now.isEmpty { print("  Nothing is using the network.") }
      for app in report.now { print("  \(app.name.padding(toLength: 28, withPad: " ", startingAt: 0)) ↓ \(NetworkDiagnosis.rate(app.received))   ↑ \(NetworkDiagnosis.rate(app.sent))") }
      print("\nToday:")
      if report.today.isEmpty { print("  Nothing recorded yet. The app records this while it’s open.") }
      for app in report.today { print("  \(app.name.padding(toLength: 28, withPad: " ", startingAt: 0)) ↓ \(Format.bytes(Int64(app.received)))   ↑ \(Format.bytes(Int64(app.sent)))") }
    }
  }
}

struct NetworkUsage: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "usage",
    abstract: "How much data this Mac has used, by day, app or network.",
    discussion: "The app records this while it’s open; time it wasn’t running isn’t counted, and the coverage figure says how much was seen. It includes traffic on your own network, so it isn’t what your provider bills."
  )

  enum Period: String, ExpressibleByArgument, CaseIterable {
    case today, week, month

    var start: Date {
      let calendar = Calendar.current
      switch self {
      case .today: return calendar.startOfDay(for: Date())
      case .week: return calendar.startOfDay(for: Date().addingTimeInterval(-6 * 86_400))
      case .month: return calendar.startOfDay(for: Date().addingTimeInterval(-29 * 86_400))
      }
    }
  }

  enum Grouping: String, ExpressibleByArgument, CaseIterable { case day, app, network }

  @OptionGroup var output: OutputOptions

  @Option(name: .long, help: "today, week or month.")
  var period: Period = .week

  @Option(name: .long, help: "day, app or network.")
  var by: Grouping = .day

  func run() async throws {
    let history = NetworkHistoryStore.load()
    let start = period.start
    let rows: [NetworkHistory.Total]
    switch by {
    case .day: rows = history.byDay(since: start).map(\.total)
    case .app: rows = history.byApp(since: start)
    case .network: rows = history.byNetwork(since: start)
    }
    struct Report: Encodable {
      var period: String
      var total: NetworkHistory.Total
      var rows: [NetworkHistory.Total]
      var recordingSince: Date?
      var coverage: Double
    }
    let report = Report(period: period.rawValue, total: history.total(since: start), rows: rows, recordingSince: history.since, coverage: history.coverage(since: start))
    emit(report, json: output.json) {
      guard let since = history.since else {
        print("Nothing recorded yet. Glade records data used while the app is open.")
        return
      }
      print("\(period == .today ? "Today" : period == .week ? "The last 7 days" : "The last 30 days"): \(Format.bytes(Int64(report.total.total))) (↓ \(Format.bytes(Int64(report.total.received))) ↑ \(Format.bytes(Int64(report.total.sent))))")
      print("Recorded since \(since.formatted(date: .abbreviated, time: .shortened)); Glade saw \(Format.percent(report.coverage)) of this period.")
      print("")
      for row in rows.prefix(30) { print("  \(row.name.padding(toLength: 28, withPad: " ", startingAt: 0)) \(Format.bytes(Int64(row.total)))") }
    }
  }
}

struct NetworkTest: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "test",
    abstract: "Run macOS’s speed test: download, upload, and how much slower the connection gets when busy.",
    discussion: "It fills the connection for its whole length against Apple’s servers, so it uses a lot of data: hundreds of megabytes, or gigabytes on a fast line. Without --confirm it only says what it would do."
  )

  @OptionGroup var output: OutputOptions

  @Option(name: .long, help: "How long to run, 5 to 60 seconds (default from settings).")
  var seconds: Int?

  @Flag(name: .long, help: "Run the test.")
  var confirm = false

  @Flag(name: .long, help: "Run even on a hotspot or in Low Data Mode.")
  var allowLimited = false

  func run() async throws {
    let config = ConfigStore.load()
    let length = seconds ?? config.network.testSeconds
    let path = await NetworkPath.current()
    let estimate = SpeedTest.estimatedBytes(seconds: length, last: SpeedTest.last)
    guard confirm else {
      struct Plan: Encodable {
        var wouldRun: Bool
        var seconds: Int
        var estimatedBytes: Int64?
        var limitedConnection: Bool
        var command: String
      }
      let plan = Plan(wouldRun: false, seconds: length, estimatedBytes: estimate, limitedConnection: path.isLimited, command: "\(Brand.cli) network test --confirm")
      emit(plan, json: output.json) {
        print("A speed test fills your connection for up to \(length) seconds against Apple’s servers.")
        if let estimate { print("At your last measured speed that’s about \(Format.bytes(estimate)) of data.") }
        if path.isLimited { print("You’re on a limited connection (a hotspot or Low Data Mode), so it would use your allowance.") }
        print("To run it: \(plan.command)\(path.isLimited ? " --allow-limited" : "")")
      }
      return
    }
    if path.isLimited, !allowLimited {
      throw ValidationError("This is a hotspot or Low Data Mode, where a test uses your allowance. Add --allow-limited to run it anyway.")
    }
    if !output.json { print("Testing for up to \(length) seconds…") }
    let result = try await SpeedTest.run(seconds: length, path: path)
    emit(result, json: output.json) {
      for line in NetworkText.test(result) { print(line) }
    }
  }
}

struct NetworkRouter: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "router",
    abstract: "What your router reports: its line to the provider and the devices on your network.",
    discussion: "Glade reads AT&T gateways’ status pages, which open without a password. Device names stay on this Mac."
  )

  @OptionGroup var output: OutputOptions

  @Flag(name: .long, help: "List every device, including ones that are off.")
  var all = false

  func run() async throws {
    let path = await NetworkPath.current()
    guard let router = path.router else { throw ValidationError("This Mac has no router right now.") }
    guard let report = await RouterReader.read(router: router, includeDevices: true, maximumAge: 60) else {
      throw ValidationError("Glade doesn’t know how to read this router yet. AT&T gateways are supported.")
    }
    var shown = report
    if !all { shown.devices = report.online }
    emit(shown, json: output.json) {
      print(report.title + (report.firmware.map { " (firmware \($0))" } ?? ""))
      print("Access code: \(RouterReader.hasAccess(report, host: router) ? "saved in the Keychain" : "not saved (\(Brand.cli) network router-access)")")
      if let line = report.line {
        print("Line: \(line.connected == true ? "up" : line.connected == false ? "DOWN" : "unknown")\(line.source.map { ", \($0)" } ?? "")\(line.portMbps.map { " at \($0) Mbps" } ?? "")")
        if let received = line.received, let sent = line.sent { print("Since the router started: ↓ \(Format.bytes(Int64(clamping: received))) ↑ \(Format.bytes(Int64(clamping: sent)))") }
        if let errors = line.errors, errors > 0 { print("Errors on the line: \(errors)") }
      }
      print("\n\(report.online.count) devices online: " + report.onlineByConnection.map { "\($0.count) on \($0.connection)" }.joined(separator: ", "))
      if report.weakDevices > 0 { print("\(report.weakDevices) on a weak signal (1–2 bars)") }
      print("")
      for device in (shown.devices ?? []).sorted(by: { ($0.name ?? "~") < ($1.name ?? "~") }) {
        let bars = device.signalBars.map { " · \($0) bars" } ?? ""
        print("  \((device.name ?? "Unnamed").padding(toLength: 30, withPad: " ", startingAt: 0)) \(device.connection)\(bars)\(device.online ? "" : " · off")")
      }
    }
  }
}

struct NetworkRouterAccess: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "router-access",
    abstract: "Save your router's admin code (an AT&T gateway's Device Access Code) in the Keychain, check it, or forget it.",
    discussion: "The code is typed at a hidden prompt, checked by signing in, and kept in your Keychain. It is never shown to an AI, written to the log, or printed."
  )

  @Flag(name: .long, help: "Check the saved code still works.") var check = false
  @Flag(name: .long, help: "Remove the saved code.") var forget = false

  func run() async throws {
    let path = await NetworkPath.current()
    guard let host = path.router, let report = await RouterReader.read(router: host, maximumAge: 0) else {
      throw ValidationError("Glade can’t read this router. AT&T gateways are supported so far.")
    }
    if forget {
      RouterReader.forgetAccess(report, host: host)
      print("Forgot the code for \(report.title).")
      return
    }
    if check {
      guard RouterReader.hasAccess(report, host: host) else { throw ValidationError("No code saved for \(report.title). Run this without --check to add one.") }
      print(await RouterReader.checkAccess(report, host: host) ? "The saved code works." : "The saved code didn’t work. Run this again to replace it.")
      return
    }
    // Typed at a hidden prompt, never as an argument, so it stays out of shell history.
    guard let typed = getpass("Device Access Code for \(report.title) (hidden): "), case let code = String(cString: typed), !code.isEmpty else {
      throw ValidationError("No code entered.")
    }
    do {
      try await RouterReader.saveAccess(code, router: host)
      print("Signed in and saved to your Keychain.")
    } catch {
      throw ValidationError(error.localizedDescription)
    }
  }
}

struct NetworkCheck: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "check",
    abstract: "Check how quickly one site or service answers, against apple.com, to tell a slow service from a slow connection.",
    discussion: "Makes one small request to each. Example: \(Brand.cli) network check www.netflix.com"
  )

  @OptionGroup var output: OutputOptions

  @Argument(help: "The site’s name, such as www.netflix.com.")
  var site: String

  func run() async throws {
    let host = site.replacingOccurrences(of: "https://", with: "").replacingOccurrences(of: "http://", with: "")
      .split(separator: "/").first.map(String.init) ?? site
    let checks = await SiteCheck.compare(host)
    struct Report: Encodable {
      var site: SiteCheck
      var control: SiteCheck
      var verdict: String
    }
    let report = Report(site: checks[0], control: checks[1], verdict: SiteCheck.sentence(checks[0], control: checks[1]))
    emit(report, json: output.json) {
      print(report.verdict)
      print("")
      for check in checks {
        func ms(_ value: Double?) -> String { value.map { "\(Int($0)) ms" } ?? "–" }
        print("  \(check.host.padding(toLength: 26, withPad: " ", startingAt: 0)) address \(ms(check.lookup)) · connect \(ms(check.connect)) · secure \(ms(check.secure)) · first reply \(ms(check.firstReply))\(check.throughProxy ? " · via proxy/relay" : "")")
      }
    }
  }
}

/// The plain-text forms of network readings, shared by the commands.
enum NetworkText {
  static func lines(_ status: NetworkStatus) -> [String] {
    var lines: [String] = []
    if let headline = status.headline {
      lines.append(headline.title)
      lines.append("  \(headline.detail)")
      if let next = headline.nextStep { lines.append("  → \(next)") }
      lines.append("")
    }
    let path = status.path
    var connection = "Connection: \(path.medium.title)"
    if let wifi = status.wifi {
      connection += " · \(wifi.sentence) · \(wifi.rssi) dBm"
      if let snr = wifi.signalToNoise { connection += ", \(snr) dB above the noise" }
      if let rate = wifi.linkRateMbps { connection += " · \(Int(rate)) Mbps link" }
      if let channel = wifi.channel { connection += " · channel \(channel)\(wifi.widthMHz.map { " (\($0) MHz)" } ?? "")" }
    }
    lines.append(connection)
    for vpn in path.vpns where vpn.connected {
      lines.append("VPN: \(vpn.name) is on\(path.vpnCarriesEverything ? " and carries all traffic" : ", but not all traffic goes through it")")
    }
    if !status.latency.isEmpty {
      lines.append("Latency: " + status.latency.map { "\($0.kind.title) \($0.stats?.sentence ?? "not found")" }.joined(separator: " · "))
    }
    var now = "Now: ↓ \(NetworkDiagnosis.rate(status.receiving)) ↑ \(NetworkDiagnosis.rate(status.sending))"
    if let busiest = status.apps.first, busiest.total >= 10_000 { now += " · busiest: \(busiest.name) (↓ \(NetworkDiagnosis.rate(busiest.received)) ↑ \(NetworkDiagnosis.rate(busiest.sent)))" }
    lines.append(now)
    if let router = status.router {
      var text = "Router: \(router.title)"
      if let line = router.line { text += " · \(line.source ?? "line") \(line.connected == false ? "down" : "up")\(line.portMbps.map { " at \($0) Mbps" } ?? "")" }
      if router.devices != nil { text += " · \(router.online.count) devices online" }
      lines.append(text)
    }
    if let test = status.lastTest {
      lines.append("Last speed test \(Format.age(test.date)): \(Int(test.downloadMbps)) down / \(Int(test.uploadMbps)) up Mbps · \(test.busySentence.lowercased())")
    } else {
      lines.append("No speed test yet: \(Brand.cli) network test")
    }
    let rest = status.verdicts.dropFirst()
    if !rest.isEmpty {
      lines.append("")
      for verdict in rest {
        lines.append("\(verdict.severity == .problem ? "✕" : verdict.severity == .good ? "✓" : "!") \(verdict.title)")
        lines.append("  \(verdict.detail)")
        for item in verdict.evidence { lines.append("    \(item)") }
        if let next = verdict.nextStep { lines.append("  → \(next)") }
      }
    }
    return lines
  }

  static func test(_ result: SpeedTestResult) -> [String] {
    var lines = [
      "Download: \(Int(result.downloadMbps)) Mbps · Upload: \(Int(result.uploadMbps)) Mbps",
      "Delay: \(result.idleLatency.map { LatencyStats.ms($0) } ?? "?") idle, \(result.busyLatency.map { LatencyStats.ms($0) } ?? "?") when busy. \(result.busySentence).",
      "",
    ]
    for activity in result.activities {
      let mark = activity.rating == .good ? "✓" : activity.rating == .okay ? "~" : "✕"
      lines.append("\(mark) \(activity.name): \(activity.sentence)")
    }
    lines.append("")
    lines.append("Used \(Format.bytes(result.dataUsedBytes)) over \(result.medium ?? "the network")\(result.throughVPN.map { " through \($0)" } ?? "").")
    return lines
  }
}
