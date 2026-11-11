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
    Card(padding: 0) {
      VStack(spacing: 0) {
        ForEach(Array(suggestions.enumerated()), id: \.element.id) { index, suggestion in
          VStack(spacing: 0) {
            if index > 0 { Divider().padding(.leading, 52) }
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
