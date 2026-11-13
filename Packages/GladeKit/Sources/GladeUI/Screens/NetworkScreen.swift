import CoreLocation
import GladeKit
import SwiftUI

/// The network: whether the connection is healthy and, if not, where the trouble is;
/// latency second by second, the Wi-Fi link and the last speed test; what’s using it;
/// the router and the devices on it; and how much data has gone.
///
/// While it shows it pings the router, the provider and the internet once a second
/// each; nothing runs when it’s gone. A speed test only runs from Test Speed.
struct NetworkScreen: View {
  @Environment(AppModel.self) private var model
  @State private var size: CGSize = .zero
  @State private var confirmsTest = false

  var body: some View {
    let network = model.network
    let stats = Dictionary(uniqueKeysWithValues: NetworkTargets.Kind.allCases.compactMap { kind in network.stats(kind).map { (kind, $0) } })
    ScrollView {
      VStack(alignment: .leading, spacing: Metrics.l) {
        if !model.networkSetupAsked, model.isLive, model.locationStatus == .notDetermined {
          NetworkSetupCard()
        }
        if !model.config.network.enabled {
          Card {
            Text("Network is off in Settings › Network.")
              .foregroundStyle(.secondary)
          }
        }
        NetworkVerdictCard(verdicts: network.verdicts, medium: network.status?.path.medium, latency: stats)
        panels(network, stats: stats)
        HStack(alignment: .top, spacing: Metrics.l) {
          NetworkAppsCard(traffic: network.traffic, today: network.history.byApp(since: Calendar.current.startOfDay(for: Date())))
          RouterCard(report: network.status?.router, loading: network.loadingRouter)
            .frame(width: size.width > 0 ? min(320, size.width * 0.36) : 300)
        }
        DataUsedCard(history: network.history)
      }
      .frame(maxWidth: Metrics.contentWidth, alignment: .leading)
      .onGeometryChange(for: CGSize.self) { $0.size } action: { size = $0 }
      .padding(Metrics.xl)
      .frame(maxWidth: .infinity)
    }
    .navigationTitle("Network")
    .navigationSubtitle(subtitle(network))
    .toolbar {
      ToolbarItem(placement: .primaryAction) {
        Button {
          confirmsTest = true
        } label: {
          if network.testing {
            HStack(spacing: 6) {
              ProgressView().controlSize(.small)
              Text("Testing…")
            }
          } else {
            Label("Test Speed", systemImage: "speedometer")
              .labelStyle(.titleAndIcon)
          }
        }
        .disabled(network.testing || !model.config.network.enabled)
        .help("Runs macOS’s speed test against Apple’s servers")
      }
    }
    .alert("Test your connection’s speed?", isPresented: $confirmsTest) {
      Button("Test") { Task { await model.runSpeedTest() } }
      Button("Cancel", role: .cancel) {}
    } message: {
      Text(testMessage(network))
    }
    .onAppear { model.networkAppeared() }
    .onDisappear { model.networkDisappeared() }
  }

  @ViewBuilder private func panels(_ network: NetworkState, stats: [NetworkTargets.Kind: LatencyStats]) -> some View {
    let latency = LatencyPanel(live: network.live, stats: stats)
    let wifi = WiFiPanel(wifi: network.wifi ?? network.status?.wifi, medium: network.status?.path.medium, signal: network.signal)
    let speed = SpeedPanel(tests: network.tests, testing: network.testing, problem: network.testProblem)
    if size.width > 0, size.width < 642 {
      VStack(spacing: Metrics.l) {
        HStack(alignment: .top, spacing: Metrics.l) { latency; wifi }
          .fixedSize(horizontal: false, vertical: true)
        speed
      }
    } else {
      HStack(alignment: .top, spacing: Metrics.l) { latency; wifi; speed }
        .fixedSize(horizontal: false, vertical: true)
    }
  }

  private func subtitle(_ network: NetworkState) -> String {
    guard let status = network.status else { return "" }
    var parts = [status.path.medium.title]
    if let vpn = status.path.vpns.first(where: \.connected), status.path.vpnCarriesEverything { parts.append("through \(vpn.name)") }
    if status.receiving + status.sending > 0 || !network.traffic.isEmpty {
      let down = network.traffic.map(\.received).reduce(0, +)
      let up = network.traffic.map(\.sent).reduce(0, +)
      parts.append("↓ \(NetworkDiagnosis.rate(down))  ↑ \(NetworkDiagnosis.rate(up))")
    }
    return parts.joined(separator: " · ")
  }

  private func testMessage(_ network: NetworkState) -> String {
    let seconds = model.config.network.testSeconds
    var text = "It fills your connection for up to \(seconds) seconds"
    if let estimate = model.speedTestEstimate { text += " and uses about \(Format.bytes(estimate)) of data" }
    text += "."
    if network.status?.path.isLimited == true { text += " You’re on a hotspot or Low Data Mode." }
    return text
  }
}
