import GladeKit
import SwiftUI

/// One run in the Details inspector: when, who answered, and whether it failed.
struct RunRow: View {
  @Environment(AppModel.self) private var model
  var run: AssistantRun

  var body: some View {
    HStack(spacing: Metrics.s) {
      VStack(alignment: .leading, spacing: 1) {
        Text(time)
          .monospacedDigit()
          .lineLimit(1)
        Text("\(model.responderName(run.provider)) · \(run.purposeTitle)")
          .font(.caption)
          .foregroundStyle(.secondary)
          .lineLimit(1)
      }
      Spacer(minLength: Metrics.xs)
      if run.proactive {
        Image(systemName: "bolt.badge.automatic")
          .foregroundStyle(.secondary)
          .accessibilityLabel("Started by Glade")
          .help("Started by Glade")
      }
      if run.error != nil {
        Image(systemName: "exclamationmark.triangle.fill")
          .foregroundStyle(Palette.warning)
          .accessibilityLabel("Failed")
          .help("Failed")
      }
    }
    .padding(.vertical, 2)
    .accessibilityElement(children: .combine)
  }

  /// "14:02" today, "Yesterday 14:02", or a short date.
  private var time: String {
    let calendar = Calendar.current
    let clock = run.date.formatted(date: .omitted, time: .shortened)
    if calendar.isDateInToday(run.date) { return clock }
    if calendar.isDateInYesterday(run.date) { return "Yesterday \(clock)" }
    return run.date.formatted(.dateTime.day().month(.abbreviated).hour().minute())
  }
}
