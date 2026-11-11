import SwiftUI

/// The frame shared by the Memory, Processor and Graphics panels: a heading and status,
/// the current figure large, its recent history, and a few details underneath.
struct LivePanel<Details: View>: View {
  var title: String
  var symbol: String
  var figure: String
  /// Words after the figure, such as "of 16 GB".
  var unit: String?
  var status: PanelStatus
  var history: [HistoryChart.Point]
  var color: Color
  /// Read out by VoiceOver in place of the drawing.
  var summary: String
  @ViewBuilder var details: Details

  var body: some View {
    Card(padding: 0) {
      VStack(alignment: .leading, spacing: 0) {
        VStack(alignment: .leading, spacing: Metrics.xs) {
          HStack(alignment: .firstTextBaseline, spacing: Metrics.s) {
            Label(title, systemImage: symbol)
              .font(.subheadline.weight(.medium))
              .foregroundStyle(.secondary)
              .lineLimit(1)
            Spacer(minLength: Metrics.xs)
            status
          }
          HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(figure)
              .font(.liveFigure(28))
              .foregroundStyle(figure == "—" ? .tertiary : .primary)
              .contentTransition(.numericText())
              .lineLimit(1)
            if let unit {
              Text(unit)
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }
          }
        }
        .padding([.horizontal, .top], Metrics.l)

        HistoryChart(points: history, color: color)
          .frame(height: 44)
          .padding(.top, Metrics.s)

        Divider()

        VStack(alignment: .leading, spacing: Metrics.xs) {
          details
        }
        .font(.subheadline)
        .padding(.horizontal, Metrics.l)
        .padding(.vertical, Metrics.m)
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
      .clipShape(.rect(cornerRadius: Metrics.cardRadius))
    }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(title)
    .accessibilityValue(summary)
  }
}
