import GladeKit
import SwiftUI

/// What the assistant said about the selection, how it changed it, and, plainly,
/// any suggestions Glade refused because they broke a safety rule.
struct AdviceBanner: View {
  var advice: StorageAdvice
  /// Looks up a finding's title for the refused suggestions.
  var title: (String) -> String?
  @State private var showsRejected = false

  var body: some View {
    HStack(alignment: .top, spacing: Metrics.m) {
      Image(systemName: "sparkles")
        .foregroundStyle(.tint)
        .accessibilityHidden(true)
      VStack(alignment: .leading, spacing: Metrics.xs) {
        Text(advice.summary)
          .lineLimit(4)
        Text(counts)
          .font(.callout)
          .foregroundStyle(.secondary)
          .monospacedDigit()
        if !advice.rejected.isEmpty {
          DisclosureGroup(isExpanded: $showsRejected) {
            VStack(alignment: .leading, spacing: Metrics.xs) {
              ForEach(advice.rejected) { note in
                HStack(alignment: .firstTextBaseline, spacing: Metrics.s) {
                  Image(systemName: "hand.raised")
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                  Text("\(Text(title(note.id) ?? "An item").fontWeight(.medium)): \(note.why)")
                }
                .font(.callout)
              }
            }
            .padding(.top, Metrics.xs)
          } label: {
            Text(advice.rejected.count == 1 ? "Glade refused 1 suggestion" : "Glade refused \(advice.rejected.count) suggestions")
              .font(.callout)
          }
        }
      }
      Spacer(minLength: 0)
    }
    .padding(Metrics.m)
    .background(.tint.opacity(0.08), in: .rect(cornerRadius: Metrics.innerRadius))
  }

  /// "+4 added · 2 left alone · 3 to review", leaving out what didn't happen, and
  /// who answered.
  private var counts: String {
    var parts: [String] = []
    if !advice.select.isEmpty { parts.append("+\(advice.select.count) added") }
    if !advice.deselect.isEmpty { parts.append("\(advice.deselect.count) left alone") }
    if !advice.review.isEmpty { parts.append("\(advice.review.count) to review") }
    if parts.isEmpty { parts.append("No changes") }
    parts.append(advice.escalated ? "\(advice.provider), with a closer look" : advice.provider)
    return parts.joined(separator: " · ")
  }
}
