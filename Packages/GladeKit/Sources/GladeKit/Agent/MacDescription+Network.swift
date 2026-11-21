import Foundation

extension MacDescription {
  /// Whether a question is about the network; see `QuestionTopic`.
  public static func isAboutNetwork(_ question: String, earlier: [ConversationTurn] = []) -> Bool {
    QuestionTopic.isAboutNetwork(question, earlier: earlier)
  }

  /// NETWORK: the verdicts, the link, latency by segment, what’s using it, the router’s
  /// counts, the last speed test and data used. No network, access point or device
  /// names and no addresses.
  public static func describe(network status: NetworkStatus, history: NetworkHistory?, now: Date = Date()) -> [String] {
    let status = status.forAI()
    var lines = ["", "NETWORK (measured \(now.timeIntervalSince(status.date) < 120 ? "just now" : Format.age(status.date, now: now)))"]
    let path = status.path
    if let wifi = status.wifi, path.medium == .wifi {
      var text = "Connection: Wi-Fi, \(wifi.sentence); signal \(wifi.rssi) dBm"
      if let snr = wifi.signalToNoise { text += ", \(snr) dB above the noise" }
      if let rate = wifi.linkRateMbps { text += "; link rate \(Int(rate)) Mbps (the most the Wi-Fi link could carry, not internet speed)" }
      if let channel = wifi.channel { text += "; channel \(channel)\(wifi.widthMHz.map { " at \($0) MHz" } ?? "")" }
      lines.append(text)
    } else {
      lines.append("Connection: \(path.medium.title)\(path.connected ? "" : " (offline)")")
    }
    if path.isLimited { lines.append("Limited connection: \(path.medium == .cellular ? "phone hotspot" : "costly network or Low Data Mode")") }
    for vpn in path.vpns where vpn.connected {
      lines.append("VPN: \(vpn.name) is on\(path.vpnCarriesEverything ? " and carries all traffic" : "; not all traffic goes through it")")
    }
    if path.proxy { lines.append("A system web proxy is set.") }
    if !status.latency.isEmpty {
      lines.append("Latency in ms (where | typical | slowest 5% | worst | jitter | lost):")
      for item in status.latency {
        guard let stats = item.stats else {
          lines.append("\(item.kind.title) (\(item.kind.meaning)) | not found")
          continue
        }
        func ms(_ value: Double?) -> String { value.map { String(format: "%.1f", $0) } ?? "-" }
        lines.append("\(item.kind.title) (\(item.kind.meaning)) | \(ms(stats.typical)) | \(ms(stats.slow)) | \(ms(stats.worst)) | \(ms(stats.jitter)) | \(Int(stats.lossPercent))%")
      }
    }
    let busy = status.apps.filter { $0.total >= 2_000 }
    if busy.isEmpty {
      lines.append("Using the network now: nothing much")
    } else {
      lines.append("Using the network now (app | receiving | sending, per second):")
      for app in busy.prefix(8) { lines.append("\(app.name) | \(NetworkDiagnosis.rate(app.received)) | \(NetworkDiagnosis.rate(app.sent))") }
    }
    if let router = status.router {
      var text = "Router: \(router.title)"
      if let line = router.line {
        text += "; line to the provider \(line.connected == false ? "DOWN" : "up")\(line.source.map { ", \($0)" } ?? "")\(line.portMbps.map { " at \($0) Mbps" } ?? "")"
        if let errors = line.errors, errors > 0 { text += ", \(errors) errors" }
      }
      if router.devices != nil {
        text += "; \(router.online.count) devices online (" + router.onlineByConnection.map { "\($0.count) on \($0.connection)" }.joined(separator: ", ") + ")"
        if router.weakDevices > 0 { text += ", \(router.weakDevices) on a weak signal" }
      }
      lines.append(text)
      // What Glade itself can do with the router, so the AI doesn't guess.
      if router.kind == "AT&T gateway" {
        lines.append(router.accessSaved == true
          ? "Router access: Glade has this gateway's Device Access Code saved in the owner's Keychain (item “Glade router access”, which Keychain Access can show them) and uses it only to sign in. Glade reads the router's public status pages (line, devices) but does not yet read or change its settings (Wi-Fi channel, QoS); the owner changes those in the gateway's own settings page in a browser. You never see the code."
          : "Router access: no access code saved. The owner can add the Device Access Code in Glade (Network, Your Network, Access code). Glade reads the router's public status pages only and does not read or change its settings.")
      }
    }
    if let test = status.lastTest {
      lines.append("Last speed test \(Format.age(test.date, now: now)): \(Int(test.downloadMbps)) Mbps down, \(Int(test.uploadMbps)) up; latency \(test.idleLatency.map { "\(Int($0)) ms" } ?? "?") idle, \(test.busyLatency.map { "\(Int($0)) ms" } ?? "?") with the line full\(test.throughVPN.map { "; through \($0)" } ?? "")")
    } else {
      lines.append("No speed test yet (the person can run one in Network or with `glade network test`).")
    }
    if let history, let since = history.since {
      let today = history.total(since: Calendar.current.startOfDay(for: now))
      let week = history.total(since: now.addingTimeInterval(-7 * 86_400))
      lines.append("Data used (recorded while Glade was open, since \(Format.age(since, now: now))): today \(Format.bytes(Int64(today.total))), last 7 days \(Format.bytes(Int64(week.total)))")
    }
    lines.append("Verdicts:")
    for verdict in status.verdicts {
      lines.append("- [\(verdict.severity.rawValue)] \(verdict.title): \(verdict.detail)\(verdict.nextStep.map { " Next: \($0)" } ?? "")")
    }
    return lines
  }
}
