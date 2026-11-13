import Charts
import GladeKit
import SwiftUI

/// How much data this Mac has used: today, this week and this month, the last week as
/// bars, and the apps that used most. Recorded only while Glade is open, and it says so
/// when that leaves gaps.
struct DataUsedCard: View {
  var history: NetworkHistory
  var now = Date()

  var body: some View {
    let calendar = Calendar.current
    let today = calendar.startOfDay(for: now)
    let week = calendar.startOfDay(for: now.addingTimeInterval(-6 * 86_400))
    let month = calendar.startOfDay(for: now.addingTimeInterval(-29 * 86_400))
    Card {
      VStack(alignment: .leading, spacing: Metrics.m) {
        HStack(alignment: .firstTextBaseline) {
          SectionTitle("Data Used")
          Spacer()
          if let note = note(since: week) {
            Text(note)
              .font(.caption)
              .foregroundStyle(.secondary)
          }
        }
        if history.since == nil {
          Text("Glade counts from now, while it’s open.")
            .foregroundStyle(.secondary)
            .font(.subheadline)
        } else {
          HStack(alignment: .top, spacing: Metrics.xl) {
            VStack(alignment: .leading, spacing: Metrics.s) {
              figure("Today", history.total(since: today).total)
              figure("7 days", history.total(since: week).total)
              figure("30 days", history.total(since: month).total)
            }
            .frame(width: 110, alignment: .leading)
            chart(since: week)
              .frame(maxWidth: .infinity, minHeight: 120, maxHeight: 140)
            VStack(alignment: .leading, spacing: Metrics.xs) {
              Text("This week")
                .font(.caption)
                .foregroundStyle(.secondary)
              ForEach(history.byApp(since: week).prefix(5), id: \.name) { app in
                PanelFact(app.name, Format.bytes(Int64(app.total)))
              }
            }
            .font(.subheadline)
            .frame(width: 220)
          }
        }
      }
    }
  }

  /// Says when the record has gaps, so a small week isn’t mistaken for a quiet one.
  private func note(since week: Date) -> String? {
    guard let since = history.since else { return nil }
    if since > week { return "Counting since \(since.formatted(date: .abbreviated, time: .omitted))" }
    let coverage = history.coverage(since: week, now: now)
    return coverage < 0.9 ? "Glade was open for \(Format.percent(coverage)) of this week" : nil
  }

  private func figure(_ title: String, _ bytes: UInt64) -> some View {
    VStack(alignment: .leading, spacing: 0) {
      Text(Format.bytes(Int64(bytes)))
        .font(.liveFigure(20))
        .monospacedDigit()
      Text(title)
        .font(.caption)
        .foregroundStyle(.secondary)
    }
    .accessibilityElement(children: .combine)
  }

  private func chart(since start: Date) -> some View {
    let days = history.byDay(since: start)
    return Chart(days, id: \.day) { day in
      BarMark(x: .value("Day", day.day, unit: .day), y: .value("Used", Double(day.total.total)))
        .foregroundStyle(Palette.glade.opacity(0.75))
        .clipShape(.rect(cornerRadius: 3))
    }
    .chartXScale(domain: start...Calendar.current.startOfDay(for: now).addingTimeInterval(86_400))
    .chartXAxis {
      AxisMarks(values: .stride(by: .day)) { _ in
        AxisValueLabel(format: .dateTime.weekday(.abbreviated), centered: true)
      }
    }
    .chartYAxis {
      AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { value in
        AxisGridLine()
        AxisValueLabel {
          if let bytes = value.as(Double.self), bytes > 0 { Text(Format.bytes(Int64(bytes))) }
        }
      }
    }
    .accessibilityLabel("Data used each day this week")
  }
}
