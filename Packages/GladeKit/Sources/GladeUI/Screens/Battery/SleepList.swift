import GladeKit
import SwiftUI

/// Recent sleeps: when, how long, what it cost the battery and how often the Mac woke
/// by itself. A row opens to show why it woke.
struct SleepList: View {
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  var sleeps: [SleepRecord]
  var loaded: Bool
  var sleepDisabled: Bool
  var detail: BatterySettings.Detail
  /// How many sleeps to list.
  var limit = 6
  @State private var open: Set<Date> = []

  var body: some View {
    Card(padding: 0) {
      VStack(spacing: 0) {
        if !loaded {
          ProgressView()
            .controlSize(.small)
            .frame(maxWidth: .infinity)
            .padding(Metrics.l)
        } else if sleeps.isEmpty {
          Text(sleepDisabled ? "No sleeps: sleep is off for this whole Mac." : "No sleeps in the last two weeks.")
            .font(.callout)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Metrics.l)
            .padding(.vertical, Metrics.m)
        } else {
          ForEach(Array(sleeps.prefix(limit).enumerated()), id: \.element.id) { index, sleep in
            if index > 0 { Divider().padding(.horizontal, Metrics.l) }
            row(sleep)
          }
        }
      }
    }
  }

  private func row(_ sleep: SleepRecord) -> some View {
    let expanded = open.contains(sleep.id)
    return VStack(alignment: .leading, spacing: Metrics.s) {
      Button {
        withAnimation(reduceMotion ? nil : .snappy(duration: 0.2)) {
          if expanded { open.remove(sleep.id) } else { open.insert(sleep.id) }
        }
      } label: {
        HStack(spacing: Metrics.m) {
          Image(systemName: "chevron.right")
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(.tertiary)
            .rotationEffect(.degrees(expanded ? 90 : 0))
            .frame(width: 12)
            .accessibilityHidden(true)
          VStack(alignment: .leading, spacing: 1) {
            Text(when(sleep))
              .lineLimit(1)
            Text("\(PerformanceFormat.uptime(sleep.seconds)) asleep · \(sleep.wakes.isEmpty ? "didn’t wake" : sleep.wakes.count == 1 ? "woke once" : "woke \(sleep.wakes.count) times")")
              .font(.callout)
              .foregroundStyle(.secondary)
              .monospacedDigit()
              .lineLimit(1)
          }
          Spacer(minLength: Metrics.s)
          drain(sleep)
        }
        .contentShape(.rect)
      }
      .buttonStyle(.plain)
      .accessibilityElement(children: .combine)
      .accessibilityHint(expanded ? "Hides why it woke" : "Shows why it woke")

      if expanded {
        VStack(alignment: .leading, spacing: Metrics.xs) {
          PanelFact("Went to sleep", sleep.reason)
          ForEach(sleep.wakeCounts, id: \.reason) { count in
            PanelFact("Woke for \(count.reason)", count.count == 1 ? "once" : "\(count.count) times")
          }
          PanelFact("Woken by", sleep.wokeBy ?? "a restart")
          if detail == .technical {
            if let raw = sleep.rawWokeBy { PanelFact("Log says", raw).help(raw) }
            if let rate = sleep.drainPerHour { PanelFact("Per hour", String(format: "%.1f%%", rate)) }
          }
        }
        .font(.callout)
        .padding(.leading, 12 + Metrics.m)
        .transition(.opacity)
      }
    }
    .padding(.horizontal, Metrics.l)
    .padding(.vertical, Metrics.s)
  }

  @ViewBuilder private func drain(_ sleep: SleepRecord) -> some View {
    if let drain = sleep.drain {
      let heavy = (sleep.drainPerHour ?? 0) >= 2 && drain >= 6
      Text(drain > 0 ? "−\(drain)%" : drain < 0 ? "+\(-drain)%" : "0%")
        .monospacedDigit()
        .foregroundStyle(heavy ? AnyShapeStyle(Palette.warning) : drain > 0 ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
        .fontWeight(heavy ? .semibold : .regular)
        .help(sleep.onBattery ? "Charge lost while asleep" : "Plugged in while asleep")
        .accessibilityLabel(drain > 0 ? "Lost \(drain)%" : drain < 0 ? "Gained \(-drain)%" : "No change")
    }
  }

  /// "Last night, 11:02 PM", "Tuesday, 3:15 PM".
  private func when(_ sleep: SleepRecord) -> String {
    let time = sleep.start.formatted(date: .omitted, time: .shortened)
    let calendar = Calendar.current
    let hour = calendar.component(.hour, from: sleep.start)
    if calendar.isDateInToday(sleep.start) { return "Today, \(time)" }
    if calendar.isDateInYesterday(sleep.start) { return hour >= 18 ? "Last night, \(time)" : "Yesterday, \(time)" }
    return "\(sleep.start.formatted(.dateTime.weekday(.wide))), \(time)"
  }
}
