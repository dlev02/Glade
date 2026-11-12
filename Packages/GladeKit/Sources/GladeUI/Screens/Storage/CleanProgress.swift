import SwiftUI

/// The clean while it runs: how far along it is and what it’s removing now. Free Up
/// Memory uses it too, with its own heading.
struct CleanProgress: View {
  var heading = "Freeing up space…"
  var done: Int
  var total: Int
  var title: String

  var body: some View {
    VStack(alignment: .leading, spacing: Metrics.m) {
      Text(heading)
        .font(.title2.weight(.semibold))
      ProgressView(value: Double(min(done, total)), total: Double(max(total, 1)))
        .accessibilityLabel("Progress")
        .accessibilityValue("\(done) of \(total)")
      HStack(spacing: Metrics.s) {
        Text(title.isEmpty ? "Starting…" : title)
          .lineLimit(1)
          .truncationMode(.middle)
        Spacer(minLength: Metrics.s)
        Text("\(done) of \(total)")
          .monospacedDigit()
          .contentTransition(.numericText())
      }
      .font(.callout)
      .foregroundStyle(.secondary)
    }
    .padding(Metrics.xl)
  }
}
