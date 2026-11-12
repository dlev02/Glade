import GladeKit
import SwiftUI

/// A new conversation: a few questions to start with.
struct ConversationStart: View {
  @Environment(AppModel.self) private var model
  @Environment(\.accentMark) private var accentMark

  /// Two by two, with the battery question across the bottom on a Mac with a battery.
  private static let suggestions: [[(symbol: String, question: String)]] = {
    var rows: [[(symbol: String, question: String)]] = [
      [("internaldrive", "Free up 30 GB"), ("gauge.with.dots.needle.67percent", "Why is my Mac slow?")],
      [("memorychip", "What’s using memory?"), ("checkmark.shield", "What’s safe to remove?")],
    ]
    if BatteryReader.hasBattery { rows.append([("battery.50percent", "What’s draining my battery?")]) }
    return rows
  }()

  var body: some View {
    VStack(spacing: Metrics.xl) {
      VStack(spacing: Metrics.m) {
        Image(systemName: Symbols.assistant)
          .font(.system(size: 30, weight: .medium))
          .foregroundStyle(accentMark)
          .accessibilityHidden(true)
        Text("Ask about this Mac")
          .font(.title2.weight(.semibold))
      }
      GlassEffectContainer(spacing: Metrics.m) {
        Grid(horizontalSpacing: Metrics.m, verticalSpacing: Metrics.m) {
          ForEach(Self.suggestions.indices, id: \.self) { row in
            GridRow {
              ForEach(Self.suggestions[row], id: \.question) { suggestion in
                Button {
                  Task { await model.ask(suggestion.question) }
                } label: {
                  Label(suggestion.question, systemImage: suggestion.symbol)
                    .frame(maxWidth: .infinity)
                }
                .floatingAction()
                .controlSize(.large)
                .accessibilityIdentifier("assistant.chip.\(row).\(Self.suggestions[row].firstIndex { $0.question == suggestion.question } ?? 0)")
                .gridCellColumns(Self.suggestions[row].count == 1 ? 2 : 1)
              }
            }
          }
        }
      }
      .fixedSize()
    }
    .padding(Metrics.xl)
    // Sits a little above the centre, as the eye expects.
    .padding(.bottom, Metrics.xxl)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }
}
