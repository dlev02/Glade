import SwiftUI

/// One live reading: a figure, what it means, and its recent history.
public struct MetricTile: View {
  var title: String
  var symbol: String
  var figure: String
  var caption: String
  /// A detail for the tooltip, such as the app using the most.
  var footnote: String?
  var history: [Double]
  var ceiling: Double?
  var color: Color

  public init(
    title: String, symbol: String, figure: String, caption: String, footnote: String? = nil,
    history: [Double], ceiling: Double? = 100, color: Color
  ) {
    self.title = title
    self.symbol = symbol
    self.figure = figure
    self.caption = caption
    self.footnote = footnote
    self.history = history
    self.ceiling = ceiling
    self.color = color
  }

  public var body: some View {
    Card(padding: 0) {
      VStack(alignment: .leading, spacing: 0) {
        VStack(alignment: .leading, spacing: Metrics.xs) {
          Label(title, systemImage: symbol)
            .font(.subheadline.weight(.medium))
            .foregroundStyle(.secondary)
          Text(figure)
            .font(.liveFigure(28))
            .foregroundStyle(figure == "—" ? .tertiary : .primary)
            .contentTransition(.numericText())
          Text(caption)
            .font(.callout)
            .foregroundStyle(.secondary)
            .lineLimit(1)
        }
        .padding([.horizontal, .top], Metrics.l)
        Spacer(minLength: Metrics.s)
        // Lifted off the bottom edge so the rounded corners don’t cut into the line.
        Sparkline(values: history, ceiling: ceiling, color: color)
          .frame(height: 40)
          .padding(.bottom, Metrics.s)
      }
      .frame(maxWidth: .infinity, minHeight: 148, alignment: .leading)
      .clipShape(.rect(cornerRadius: Metrics.cardRadius))
    }
    .help(footnote ?? "")
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(title)
    .accessibilityValue([figure, caption, footnote].compactMap { $0 }.joined(separator: ", "))
  }
}
