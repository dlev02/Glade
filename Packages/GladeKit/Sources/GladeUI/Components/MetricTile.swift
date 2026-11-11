import SwiftUI

/// One live reading: a figure, what it means, and its recent history.
public struct MetricTile: View {
  var title: String
  var symbol: String
  var figure: String
  var caption: String
  /// A second line, such as the app using the most.
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
            .font(.figure(28))
            .contentTransition(.numericText())
          Text(caption)
            .font(.callout)
            .foregroundStyle(.secondary)
            .lineLimit(1)
          if let footnote {
            Text(footnote)
              .font(.caption)
              .foregroundStyle(.tertiary)
              .lineLimit(1)
          }
        }
        .padding(Metrics.l)
        Spacer(minLength: 0)
        Sparkline(values: history, ceiling: ceiling, color: color)
          .frame(height: 44)
      }
      .frame(maxWidth: .infinity, minHeight: 168, alignment: .leading)
      .clipShape(.rect(cornerRadius: Metrics.cardRadius))
    }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(title)
    .accessibilityValue("\(figure), \(caption)")
  }
}
