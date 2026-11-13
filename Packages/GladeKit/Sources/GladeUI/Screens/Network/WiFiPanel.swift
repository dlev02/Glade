import GladeKit
import SwiftUI

/// How good the Wi-Fi link is: one word for the signal, its last few minutes, and the
/// band, channel and rate beneath. On a cable it says so and shows the cable instead.
struct WiFiPanel: View {
  var wifi: WiFiLink?
  var medium: NetworkPath.Medium?
  var signal: [HistoryChart.Point]

  var body: some View {
    if let wifi {
      LivePanel(
        title: "Wi-Fi", symbol: "wifi",
        figure: wifi.quality.title, unit: wifi.band,
        status: PanelStatus(text: "\(wifi.rssi) dBm", symbol: nil, color: color(wifi.quality), prominent: wifi.quality <= .fair),
        history: signal, color: color(wifi.quality),
        summary: "\(wifi.sentence), \(wifi.rssi) dBm"
      ) {
        if let name = wifi.networkName { PanelFact("Network", name) }
        PanelFact("Channel", [wifi.channel.map(String.init), wifi.widthMHz.map { "\($0) MHz" }].compactMap { $0 }.joined(separator: " · "))
        PanelFact("Link rate", wifi.linkRateMbps.map { "\(Int($0)) Mbps" } ?? "—")
        PanelFact("Above noise", wifi.signalToNoise.map { "\($0) dB" } ?? "—")
        if wifi.networkName == nil { PanelFact("Standard", wifi.generation ?? "—") }
      }
    } else {
      LivePanel(
        title: medium == .ethernet ? "Ethernet" : "Wi-Fi", symbol: medium == .ethernet ? "cable.connector" : "wifi.slash",
        figure: medium == .ethernet ? "Wired" : medium == nil ? "—" : "Off", unit: nil,
        status: medium == nil ? .measuring : PanelStatus(text: medium == .ethernet ? "Connected" : "Not joined", symbol: nil, color: medium == .ethernet ? Palette.good : .secondary, prominent: false),
        history: [], color: Palette.good, summary: medium?.title ?? "Measuring"
      ) {
        PanelFact("Connection", medium?.title ?? "—")
      }
    }
  }

  private func color(_ quality: WiFiLink.Quality) -> Color {
    switch quality {
    case .excellent, .good: Palette.good
    case .fair: Palette.warning
    case .weak: Palette.critical
    }
  }
}
