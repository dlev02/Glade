import Foundation

/// AT&T’s gateways (BGW320, BGW210 and the Arris and Pace boxes before them) serve
/// status pages under `/cgi-bin/*.ha`. These three open without the Device Access Code.
enum ATTGateway {
  static func read(host: String, includeDevices: Bool, now: Date) async -> RouterReport? {
    guard let info = await RouterReader.page(host, "/cgi-bin/sysinfo.ha", timeout: 8) else { return nil }
    let system = HTMLRow.firstValues(in: info)
    guard let model = system["Model Number"], !model.isEmpty else { return nil }
    async let broadband = RouterReader.page(host, "/cgi-bin/broadbandstatistics.ha")
    async let devicePage = includeDevices ? RouterReader.page(host, "/cgi-bin/devices.ha", timeout: 25) : nil
    let (line, devices) = await (broadband.map(parseLine), devicePage.map(parseDevices))
    Log.info(.network, "Read the AT&T gateway \(model): line \(line?.connected.map { $0 ? "up" : "down" } ?? "unknown")\(devices.map { ", \($0.filter(\.online).count) devices online" } ?? "")")
    return RouterReport(
      kind: "AT&T gateway", maker: system["Manufacturer"].map(maker), model: model, firmware: system["Software Version"],
      line: line, devices: devices, read: now
    )
  }

  static func maker(_ name: String) -> String {
    name.uppercased() == name ? name.capitalized : name
  }

  /// The first value for each label is the IPv4 and Ethernet one; later repeats are IPv6 or the fibre unit.
  static func parseLine(_ html: String) -> RouterReport.Line {
    let values = HTMLRow.firstValues(in: html)
    func number(_ label: String) -> UInt64? { values[label].flatMap { UInt64($0.filter(\.isNumber)) } }
    let source = values["Broadband Connection Source"].map { $0.uppercased() == "FIBER" ? "Fibre" : $0.capitalized }
    let state = values["Broadband Connection"] ?? values["Line State"]
    return RouterReport.Line(
      connected: state.map { $0.lowercased() == "up" },
      source: source,
      portMbps: values["Current Speed (Mbps)"].flatMap { Int($0.filter(\.isNumber)) },
      received: number("Receive Bytes"),
      sent: number("Transmit Bytes"),
      errors: [number("Receive Errors"), number("Transmit Errors")].compactMap { $0 }.reduce(0, +).asInt,
      drops: [number("Receive Drops"), number("Transmit Drops")].compactMap { $0 }.reduce(0, +).asInt
    )
  }

  /// Each device is a run of rows starting with “MAC Address”. The address itself and
  /// the IP addresses aren’t kept.
  static func parseDevices(_ html: String) -> [RouterReport.Device] {
    var devices: [RouterReport.Device] = []
    var current: RouterReport.Device?
    func close() {
      if let current { devices.append(current) }
    }
    for row in HTMLRow.rows(in: html) {
      switch row.label {
      case "MAC Address":
        close()
        current = RouterReport.Device(name: nil, online: false, connection: "Unknown", signalBars: nil, throughMesh: nil, lastActive: nil)
      case "Name":
        if current?.name == nil, !row.value.isEmpty, row.value.lowercased() != "unknown" { current?.name = row.value }
      case "Status":
        current?.online = row.value.lowercased() == "on"
      case "Last Activity":
        current?.lastActive = row.value
      case "Mesh Client":
        current?.throughMesh = row.value.lowercased() == "yes"
      case "Connection Type":
        current?.connection = connection(row.value)
        current?.signalBars = HTMLRow.matches(#"alt="Wi-Fi (\d) bar"#, in: row.valueMarkup).first.flatMap { Int($0) }
      default:
        break
      }
    }
    close()
    return devices
  }

  /// “Wi-Fi\n5 GHz Radio-1\nType: Home\nName: …” becomes “Wi-Fi 5 GHz”; “Ethernet LAN-4” stays.
  static func connection(_ value: String) -> String {
    let lines = value.split(separator: "\n").map(String.init)
    guard let first = lines.first else { return "Unknown" }
    if first.hasPrefix("Wi-Fi") {
      let band = value.range(of: #"\d(\.\d)? GHz"#, options: .regularExpression).map { String(value[$0]) }
      return band.map { "Wi-Fi \($0)" } ?? "Wi-Fi"
    }
    return first.hasPrefix("Ethernet") ? "Ethernet" : first
  }
}

extension UInt64 {
  var asInt: Int { Int(clamping: self) }
}
