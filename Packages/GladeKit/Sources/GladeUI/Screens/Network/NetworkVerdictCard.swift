import GladeKit
import SwiftUI

/// The answer first: the leading verdict, what to try, and the connection drawn as its
/// segments (this Mac, the router, the provider, the internet) so a slow one shows
/// where it is. Other verdicts follow as single lines.
struct NetworkVerdictCard: View {
  var verdicts: [NetworkVerdict]
  var medium: NetworkPath.Medium?
  var latency: [NetworkTargets.Kind: LatencyStats]

  var body: some View {
    Card {
      VStack(alignment: .leading, spacing: Metrics.m) {
        HStack(alignment: .top, spacing: Metrics.xl) {
          headline
          Spacer(minLength: Metrics.s)
          PathStrip(medium: medium, latency: latency)
        }
        let rest = Array(verdicts.dropFirst().prefix(3))
        if !rest.isEmpty {
          Divider()
          VStack(alignment: .leading, spacing: Metrics.s) {
            ForEach(rest) { verdict in VerdictLine(verdict: verdict) }
          }
        }
      }
    }
  }

  @ViewBuilder private var headline: some View {
    if let first = verdicts.first {
      HStack(alignment: .firstTextBaseline, spacing: Metrics.s) {
        Image(systemName: NetworkFormat.symbol(first.severity))
          .foregroundStyle(NetworkFormat.color(first.severity))
          .font(.title3)
          .accessibilityHidden(true)
        VStack(alignment: .leading, spacing: Metrics.xs) {
          Text(first.title)
            .font(.title3.weight(.semibold))
          Text(first.detail)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
          if let next = first.nextStep {
            Text(next)
              .font(.callout)
              .padding(.top, 2)
              .fixedSize(horizontal: false, vertical: true)
          }
        }
      }
      .accessibilityElement(children: .combine)
    } else {
      HStack(spacing: Metrics.s) {
        ProgressView().controlSize(.small)
        Text("Checking your connection…")
          .foregroundStyle(.secondary)
      }
    }
  }
}

/// One further verdict: its mark, title and a short detail.
private struct VerdictLine: View {
  var verdict: NetworkVerdict

  var body: some View {
    HStack(alignment: .firstTextBaseline, spacing: Metrics.s) {
      Image(systemName: NetworkFormat.symbol(verdict.severity))
        .foregroundStyle(NetworkFormat.color(verdict.severity))
        .accessibilityHidden(true)
      Text(verdict.title).fontWeight(.medium)
      Text(verdict.nextStep ?? verdict.detail)
        .foregroundStyle(.secondary)
        .lineLimit(1)
        .truncationMode(.tail)
        .help(([verdict.detail] + verdict.evidence).joined(separator: "\n"))
    }
    .font(.callout)
    .accessibilityElement(children: .combine)
  }
}

/// This Mac → Router → Provider → Internet, each hop with its latency and coloured by
/// how it’s doing, so the eye goes straight to the slow one.
private struct PathStrip: View {
  var medium: NetworkPath.Medium?
  var latency: [NetworkTargets.Kind: LatencyStats]

  var body: some View {
    HStack(alignment: .top, spacing: 0) {
      node(symbol: "laptopcomputer", title: "This Mac", value: medium?.title ?? " ", health: .good, first: true)
      ForEach(NetworkTargets.Kind.allCases, id: \.self) { kind in
        let stats = latency[kind]
        let health = NetworkFormat.health(kind, stats)
        link(health)
        node(symbol: symbol(kind), title: kind.title, value: stats.map { $0.reachable ? NetworkFormat.ms($0.typical) : "No reply" } ?? "—", health: health, first: false)
      }
    }
    .fixedSize()
    .accessibilityElement(children: .ignore)
    .accessibilityLabel("Latency")
    .accessibilityValue(NetworkTargets.Kind.allCases.map { "\($0.title) \(latency[$0]?.sentence ?? "not measured")" }.joined(separator: ", "))
  }

  private func symbol(_ kind: NetworkTargets.Kind) -> String {
    switch kind {
    case .router: "wifi.router"
    case .provider: "building.2"
    case .internet: "globe"
    }
  }

  private func node(symbol: String, title: String, value: String, health: NetworkFormat.Health, first: Bool) -> some View {
    VStack(spacing: 4) {
      Image(systemName: symbol)
        .font(.system(size: 17))
        .foregroundStyle(first ? AnyShapeStyle(.secondary) : AnyShapeStyle(health == .unknown ? Color.secondary : health.color))
        .frame(width: 36, height: 36)
        .background(Palette.track, in: .circle)
      Text(title)
        .font(.caption)
        .foregroundStyle(.secondary)
      Text(value)
        .font(.caption.weight(.medium))
        .monospacedDigit()
        .foregroundStyle(health == .bad ? AnyShapeStyle(Palette.critical) : AnyShapeStyle(.primary))
    }
    .frame(width: 64)
  }

  private func link(_ health: NetworkFormat.Health) -> some View {
    Capsule()
      .fill(health == .unknown ? Palette.track : health.color.opacity(health == .good ? 0.45 : 0.9))
      .frame(width: 22, height: 3)
      .padding(.top, 17)
  }
}
