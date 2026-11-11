import SwiftUI

/// One compact live reading in the menu bar popover: a name, a figure, a word on how
/// it's doing, and a tiny line of its recent history. Three sit side by side in one
/// tile, which draws the background.
struct MenuReading: View {
  var title: String
  var figure: String
  var caption: String
  var history: [Double]
  var color: Color

  var body: some View {
    VStack(alignment: .leading, spacing: 2) {
      Text(title)
        .font(.caption)
        .foregroundStyle(.secondary)
      Text(figure)
        .font(.liveFigure(17))
        .foregroundStyle(figure == "—" ? .tertiary : .primary)
        .contentTransition(.numericText())
        .lineLimit(1)
      Text(caption)
        .font(.caption)
        .foregroundStyle(.secondary)
        .lineLimit(1)
      Sparkline(values: history, ceiling: 100, color: color)
        .frame(height: 18)
        .padding(.top, Metrics.xs)
    }
    .padding(Metrics.m)
    .frame(maxWidth: .infinity, alignment: .leading)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(title)
    .accessibilityValue("\(figure), \(caption)")
  }
}
