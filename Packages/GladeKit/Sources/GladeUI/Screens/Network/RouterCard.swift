import GladeKit
import SwiftUI

/// The router: its line to the provider, and the devices on the network by how they
/// connect, with the ones on a weak signal counted. The list opens on request.
struct RouterCard: View {
  var report: RouterReport?
  var host: String?
  var loading: Bool
  @State private var showsDevices = false
  @State private var addsCode = false
  @State private var accessRevision = 0

  var body: some View {
    Card {
      VStack(alignment: .leading, spacing: Metrics.m) {
        HStack(alignment: .firstTextBaseline) {
          SectionTitle("Your Network")
          Spacer()
          if let report { Text(report.title).foregroundStyle(.secondary).lineLimit(1) }
        }
        if let report {
          if let line = report.line {
            PanelFact("Internet line", lineText(line), dot: line.connected == false ? Palette.critical : Palette.good)
          }
          if let host, report.kind == "AT&T gateway" { accessRow(report, host: host) }
          if report.devices != nil {
            PanelFact("Devices online", "\(report.online.count)")
            ForEach(report.onlineByConnection, id: \.connection) { group in
              PanelFact(group.connection, "\(group.count)")
            }
            if report.weakDevices > 0 {
              PanelFact("On a weak signal", "\(report.weakDevices)", dot: Palette.warning)
            }
            Button(showsDevices ? "Hide Devices" : "Show Devices") {
              withAnimation(.snappy) { showsDevices.toggle() }
            }
            .buttonStyle(.link)
            if showsDevices { deviceList(report) }
          } else if loading {
            HStack(spacing: Metrics.s) {
              ProgressView().controlSize(.small)
              Text("Reading the device list…").foregroundStyle(.secondary)
            }
          }
        } else if loading {
          HStack(spacing: Metrics.s) {
            ProgressView().controlSize(.small)
            Text("Reading your router…").foregroundStyle(.secondary)
          }
        } else {
          Text("Glade can read AT&T gateways. Other routers show here as Glade learns them.")
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
      }
      .font(.subheadline)
    }
  }

  /// Whether Glade holds the gateway’s Device Access Code, with Add or Forget.
  private func accessRow(_ report: RouterReport, host: String) -> some View {
    let saved = accessRevision >= 0 && RouterReader.hasAccess(report, host: host)
    return HStack {
      Text("Access code").foregroundStyle(.secondary)
      Spacer()
      if saved {
        Text("In your Keychain")
        Button("Forget") {
          RouterReader.forgetAccess(report, host: host)
          accessRevision += 1
        }
        .buttonStyle(.link)
      } else {
        Button("Add…") { addsCode = true }
          .buttonStyle(.link)
      }
    }
    .sheet(isPresented: $addsCode, onDismiss: { accessRevision += 1 }) {
      RouterAccessSheet(title: report.title, host: host)
    }
  }

  private func lineText(_ line: RouterReport.Line) -> String {
    var parts: [String] = [line.connected == false ? "Down" : "Up"]
    if let source = line.source { parts.append(source) }
    if let speed = line.portMbps { parts.append(speed >= 1000 ? "\(speed / 1000) Gbps" : "\(speed) Mbps") }
    return parts.joined(separator: " · ")
  }

  private func deviceList(_ report: RouterReport) -> some View {
    VStack(alignment: .leading, spacing: 6) {
      ForEach(report.online.sorted { ($0.signalBars ?? 9, $0.name ?? "~") < ($1.signalBars ?? 9, $1.name ?? "~") }) { device in
        HStack(spacing: Metrics.s) {
          Image(systemName: device.connection.hasPrefix("Wi-Fi") ? "wifi" : "cable.connector")
            .foregroundStyle(.secondary)
            .frame(width: 16)
          Text(device.name ?? "Unnamed device")
            .lineLimit(1)
            .foregroundStyle(device.name == nil ? .secondary : .primary)
          Spacer(minLength: Metrics.s)
          if let bars = device.signalBars {
            SignalBars(bars: bars)
          }
          Text(device.connection.replacingOccurrences(of: "Wi-Fi ", with: ""))
            .foregroundStyle(.secondary)
            .monospacedDigit()
        }
        .accessibilityElement(children: .combine)
      }
    }
    .transition(.opacity)
  }
}

/// The router’s 1–5 bars, drawn small.
private struct SignalBars: View {
  var bars: Int

  var body: some View {
    HStack(alignment: .bottom, spacing: 1.5) {
      ForEach(1...5, id: \.self) { index in
        RoundedRectangle(cornerRadius: 1)
          .fill(index <= bars ? (bars <= 2 ? Palette.warning : Color.primary.opacity(0.7)) : Palette.track)
          .frame(width: 3, height: CGFloat(3 + index * 2))
      }
    }
    .accessibilityLabel("\(bars) of 5 bars")
  }
}
