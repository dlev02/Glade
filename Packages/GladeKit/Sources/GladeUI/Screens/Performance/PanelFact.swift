import SwiftUI

/// One detail line in a live panel: a label on the left, its value on the right, and
/// an optional colour dot when it's part of a stacked bar.
struct PanelFact: View {
  var label: String
  var value: String
  var dot: Color?

  init(_ label: String, _ value: String, dot: Color? = nil) {
    self.label = label
    self.value = value
    self.dot = dot
  }

  var body: some View {
    HStack(spacing: 6) {
      if let dot {
        Circle().fill(dot).frame(width: 7, height: 7)
          .accessibilityHidden(true)
      }
      Text(label)
        .foregroundStyle(.secondary)
        .lineLimit(1)
      Spacer(minLength: Metrics.xs)
      Text(value)
        .monospacedDigit()
        .lineLimit(1)
    }
  }
}
