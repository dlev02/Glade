import GladeKit
import SwiftUI

/// The few things worth quitting right now, each with its numbers and, when Glade can
/// act on it, a button.
struct SuggestionsCard: View {
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  var suggestions: [PerformanceSuggestion]
  /// Shows the sentence describing what happened.
  var report: (String) -> Void

  var body: some View {
    // Headed and divided like Overview’s suggestions.
    VStack(alignment: .leading, spacing: Metrics.s) {
      HStack(alignment: .firstTextBaseline) {
        SectionTitle("Suggestions")
        Spacer(minLength: Metrics.s)
        FreeUpMemoryButton(style: .principal, identifier: "performance.freeUpMemory")
      }
      card
    }
  }

  private var card: some View {
    Card(padding: 0) {
      VStack(spacing: 0) {
        ForEach(Array(suggestions.enumerated()), id: \.element.id) { index, suggestion in
          VStack(spacing: 0) {
            // From the text edge to the content’s trailing edge.
            if index > 0 { Divider().padding(.leading, 52).padding(.trailing, Metrics.l) }
            SuggestionRow(suggestion, iconSize: 24, report: report)
              .padding(.horizontal, Metrics.l)
              .padding(.vertical, Metrics.s)
          }
          .suggestionTransition(reduceMotion: reduceMotion)
        }
      }
    }
    .animation(.smooth(duration: 0.3), value: suggestions.map(\.id))
  }
}
