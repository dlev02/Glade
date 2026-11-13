import GladeKit
import SwiftUI

/// The apps using the network right now, busiest first, with what each has used today.
struct NetworkAppsCard: View {
  var traffic: [AppTraffic]
  var today: [NetworkHistory.Total]
  var limit = 8

  var body: some View {
    let rows = Array(traffic.filter { $0.total >= 1_000 }.prefix(limit))
    let todayByName = Dictionary(today.map { ($0.name, $0.total) }, uniquingKeysWith: { first, _ in first })
    Card {
      VStack(alignment: .leading, spacing: Metrics.m) {
        SectionTitle("Using the Network")
        if rows.isEmpty {
          Text(traffic.isEmpty ? "Measuring…" : "Nothing is using the network right now.")
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, minHeight: 60)
        } else {
          Grid(alignment: .leading, horizontalSpacing: Metrics.l, verticalSpacing: Metrics.s) {
            GridRow {
              Text("")
              header("Receiving")
              header("Sending")
              if !today.isEmpty { header("Today") }
            }
            ForEach(rows) { app in
              GridRow {
                HStack(spacing: Metrics.s) {
                  AppIconView(path: app.bundlePath, size: 18)
                  Text(app.name)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .foregroundStyle(app.isSystem ? .secondary : .primary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                figure(NetworkFormat.rate(app.received))
                figure(NetworkFormat.rate(app.sent), strong: app.sent >= 1_500_000)
                if !today.isEmpty { figure(todayByName[app.name].map { Format.bytes(Int64($0)) } ?? "—") }
              }
              .accessibilityElement(children: .combine)
            }
          }
        }
      }
    }
  }

  private func header(_ text: String) -> some View {
    Text(text)
      .font(.subheadline)
      .foregroundStyle(.secondary)
      .gridColumnAlignment(.trailing)
  }

  private func figure(_ text: String, strong: Bool = false) -> some View {
    Text(text)
      .monospacedDigit()
      .fontWeight(strong ? .semibold : .regular)
      .foregroundStyle(text == "—" ? AnyShapeStyle(.tertiary) : strong ? AnyShapeStyle(Palette.warning) : AnyShapeStyle(.primary))
      .gridColumnAlignment(.trailing)
  }
}
