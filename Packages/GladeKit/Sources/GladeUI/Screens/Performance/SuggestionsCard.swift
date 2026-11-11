import GladeKit
import SwiftUI

/// The few things worth quitting right now, each with its reason and, when Glade can
/// act on it, a Quit button.
struct SuggestionsCard: View {
  @Environment(AppModel.self) private var model
  var suggestions: [PerformanceSuggestion]
  var apps: [AppUsage]
  /// Shows the sentence describing what happened.
  var report: (String) -> Void
  @State private var working: Set<String> = []

  var body: some View {
    Card(padding: 0) {
      VStack(spacing: 0) {
        ForEach(Array(suggestions.enumerated()), id: \.element.id) { index, suggestion in
          if index > 0 { Divider().padding(.leading, 52) }
          row(suggestion)
        }
      }
    }
  }

  private func row(_ suggestion: PerformanceSuggestion) -> some View {
    let app = apps.first { $0.id == suggestion.appID }
    return HStack(spacing: Metrics.m) {
      if let symbol = model.symbol(for: suggestion) {
        Image(systemName: symbol)
          .font(.system(size: 14, weight: .medium))
          .foregroundStyle(.teal)
          .frame(width: 24, height: 24)
          .background(.teal.opacity(0.14), in: .rect(cornerRadius: 6))
          .accessibilityHidden(true)
      } else {
        AppIconView(path: app?.bundlePath, size: 24)
      }
      VStack(alignment: .leading, spacing: 1) {
        Text(suggestion.title)
          .lineLimit(1)
        Text(suggestion.reason)
          .font(.callout)
          .foregroundStyle(.secondary)
          .lineLimit(1)
          .help(suggestion.reason)
      }
      Spacer(minLength: Metrics.m)
      if let title = model.actionTitle(for: suggestion) {
        Button(title) {
          working.insert(suggestion.id)
          Task {
            report(await model.perform(suggestion))
            working.remove(suggestion.id)
          }
        }
        .disabled(working.contains(suggestion.id))
        .accessibilityLabel("\(title) \(suggestion.appName)")
      }
    }
    .padding(.horizontal, Metrics.l)
    .padding(.vertical, Metrics.s)
    .accessibilityElement(children: .combine)
  }
}
