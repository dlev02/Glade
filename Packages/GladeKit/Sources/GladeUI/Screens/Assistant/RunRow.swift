import GladeKit
import SwiftUI

/// One run in the list of what was sent: what it was for, who answered, and when.
struct RunRow: View {
  @Environment(AppModel.self) private var model
  var run: AssistantRun

  var body: some View {
    VStack(alignment: .leading, spacing: 2) {
      HStack(spacing: Metrics.xs) {
        Text(run.purposeTitle)
          .lineLimit(1)
        Spacer(minLength: Metrics.xs)
        if run.proactive {
          Image(systemName: "bolt.badge.automatic")
            .foregroundStyle(.secondary)
            .accessibilityLabel("Started by Glade")
            .help("Started by Glade")
        }
        if run.error != nil {
          Image(systemName: "exclamationmark.triangle")
            .foregroundStyle(Palette.warning)
            .accessibilityLabel("Failed")
            .help("Failed")
        }
      }
      Text("\(model.providerName(run.provider)) · \(run.date.formatted(date: .abbreviated, time: .shortened))")
        .font(.caption)
        .foregroundStyle(.secondary)
        .lineLimit(1)
    }
    .padding(.vertical, 2)
  }
}
