import Charts
import SwiftUI

/// The last few minutes of one reading as a soft area under a line, from 0 to 100,
/// with the newest reading at the right edge. Kept cheap: no per-point symbols, no
/// axes, no animation between readings.
struct HistoryChart: View {
  /// One reading, 0–100.
  struct Point: Identifiable {
    var date: Date
    var value: Double
    var id: Date { date }
  }

  var points: [Point]
  var color: Color

  var body: some View {
    Chart {
      ForEach(points) { point in
        AreaMark(x: .value("Time", point.date), y: .value("Use", point.value))
          .foregroundStyle(
            LinearGradient(colors: [color.opacity(0.26), color.opacity(0.02)], startPoint: .top, endPoint: .bottom)
          )
          .interpolationMethod(.monotone)
        LineMark(x: .value("Time", point.date), y: .value("Use", point.value))
          .foregroundStyle(color)
          .lineStyle(StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
          .interpolationMethod(.monotone)
      }
    }
    .chartYScale(domain: 0...100)
    .chartXScale(domain: domain)
    .chartXAxis(.hidden)
    .chartYAxis(.hidden)
    .chartLegend(.hidden)
    .transaction { $0.animation = nil }
    .accessibilityHidden(true)
  }

  /// From the oldest reading to the newest, so the line always fills the width.
  private var domain: ClosedRange<Date> {
    guard let first = points.first?.date, let last = points.last?.date, last > first else {
      let now = points.last?.date ?? Date()
      return now.addingTimeInterval(-60)...now
    }
    return first...last
  }
}
