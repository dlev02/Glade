import Charts
import GladeKit
import SwiftUI

/// How far back the charge chart looks.
enum ChargeRange: String, CaseIterable, Identifiable {
  case day, week, month

  var id: String { rawValue }

  var title: String {
    switch self {
    case .day: "24 Hours"
    case .week: "7 Days"
    case .month: "30 Days"
    }
  }

  var seconds: TimeInterval {
    switch self {
    case .day: 86_400
    case .week: 7 * 86_400
    case .month: 30 * 86_400
    }
  }
}

/// The charge over a day, a week or a month, with the stretches on the charger shaded
/// and the sleeps marked. Gaps where Glade wasn’t running are left as gaps.
struct ChargeChart: View {
  @Environment(\.accentMark) private var accentMark
  var samples: [BatteryHistory.Sample]
  var sleeps: [SleepRecord]
  var range: ChargeRange
  var now: Date

  /// One run of samples without a gap, drawn as its own line.
  private struct Point: Identifiable {
    var date: Date
    var percent: Int
    var segment: Int
    var id: Date { date }
  }

  private struct Band: Identifiable {
    var start: Date
    var end: Date
    var id: Date { start }
  }

  var body: some View {
    let start = now.addingTimeInterval(-range.seconds)
    let points = Self.points(samples, start: start, range: range)
    Chart {
      ForEach(Self.bands(samples, start: start, now: now)) { band in
        RectangleMark(xStart: .value("From", band.start), xEnd: .value("To", band.end), yStart: .value("Low", 0), yEnd: .value("High", 100))
          .foregroundStyle(Palette.glade.opacity(0.13))
      }
      ForEach(sleeps.filter { $0.end > start }) { sleep in
        RectangleMark(xStart: .value("From", max(sleep.start, start)), xEnd: .value("To", sleep.end), yStart: .value("Low", 0), yEnd: .value("High", 100))
          .foregroundStyle(Self.sleepColor.opacity(0.11))
      }
      ForEach(points) { point in
        AreaMark(x: .value("Time", point.date), y: .value("Charge", point.percent), series: .value("Run", point.segment))
          .foregroundStyle(LinearGradient(colors: [accentMark.opacity(0.22), accentMark.opacity(0.02)], startPoint: .top, endPoint: .bottom))
          .interpolationMethod(.monotone)
        LineMark(x: .value("Time", point.date), y: .value("Charge", point.percent), series: .value("Run", point.segment))
          .foregroundStyle(accentMark)
          .lineStyle(StrokeStyle(lineWidth: 1.75, lineCap: .round, lineJoin: .round))
          .interpolationMethod(.monotone)
      }
    }
    .chartYScale(domain: 0...100)
    .chartXScale(domain: start...now)
    .chartYAxis {
      AxisMarks(position: .trailing, values: [0, 50, 100]) { value in
        AxisGridLine(stroke: StrokeStyle(lineWidth: Metrics.hairline, dash: [2, 3]))
          .foregroundStyle(Palette.hairline)
        AxisValueLabel {
          if let percent = value.as(Int.self) { Text("\(percent)%").monospacedDigit() }
        }
      }
    }
    .chartXAxis {
      AxisMarks(values: Self.ticks(start: start, now: now, range: range)) { _ in
        AxisValueLabel(format: range == .day ? .dateTime.hour() : range == .week ? .dateTime.weekday(.abbreviated) : .dateTime.day().month(.abbreviated))
      }
    }
    .chartLegend(.hidden)
    .transaction { $0.animation = nil }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel("Charge over the last \(range.title.lowercased())")
    .accessibilityValue(summary(points))
  }

  static let sleepColor = Color.indigo

  /// Every three hours, every day or every five days, kept clear of both edges so no
  /// label is cut off.
  private static func ticks(start: Date, now: Date, range: ChargeRange) -> [Date] {
    let calendar = Calendar.current
    let (component, step): (Calendar.Component, Int) =
      switch range {
      case .day: (.hour, 3)
      case .week: (.day, 1)
      case .month: (.day, 5)
      }
    let margin = range.seconds * 0.04
    var date = range == .day
      ? calendar.dateInterval(of: .hour, for: start)?.end ?? start
      : calendar.startOfDay(for: start).addingTimeInterval(86_400)
    if range == .day {
      while calendar.component(.hour, from: date) % 3 != 0 { date = date.addingTimeInterval(3600) }
    }
    var ticks: [Date] = []
    while date < now {
      if date.timeIntervalSince(start) > margin && now.timeIntervalSince(date) > margin { ticks.append(date) }
      date = calendar.date(byAdding: component, value: step, to: date) ?? now
    }
    return ticks
  }

  /// Samples in range, split wherever Glade wasn’t watching for a while.
  private static func points(_ samples: [BatteryHistory.Sample], start: Date, range: ChargeRange) -> [Point] {
    let gap: TimeInterval = range == .day ? 20 * 60 : 75 * 60
    var segment = 0
    var previous: Date?
    var points: [Point] = []
    for sample in samples where sample.date >= start {
      if let previous, sample.date.timeIntervalSince(previous) > gap { segment += 1 }
      points.append(Point(date: sample.date, percent: sample.percent, segment: segment))
      previous = sample.date
    }
    return points
  }

  /// Stretches on the charger.
  private static func bands(_ samples: [BatteryHistory.Sample], start: Date, now: Date) -> [Band] {
    var bands: [Band] = []
    var open: Date?
    for (index, sample) in samples.enumerated() where sample.date >= start || index + 1 < samples.count && samples[index + 1].date >= start {
      if sample.isPluggedIn {
        if open == nil { open = max(sample.date, start) }
      } else if let began = open {
        bands.append(Band(start: began, end: sample.date))
        open = nil
      }
    }
    if let open, let last = samples.last { bands.append(Band(start: open, end: last.isPluggedIn ? now : last.date)) }
    return bands
  }

  private func summary(_ points: [Point]) -> String {
    guard let first = points.first, let last = points.last else { return "No readings yet" }
    let low = points.map(\.percent).min() ?? 0, high = points.map(\.percent).max() ?? 0
    return "From \(first.percent)% to \(last.percent)%, lowest \(low)%, highest \(high)%"
  }
}
