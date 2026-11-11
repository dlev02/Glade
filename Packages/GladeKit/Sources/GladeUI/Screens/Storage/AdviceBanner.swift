import GladeKit
import SwiftUI

/// What the assistant said about the selection, how it changed it, and, plainly,
/// any suggestions Glade refused because they broke a safety rule. Drawn like the
/// Assistant's advice card, so the two read as the same thing.
struct AdviceBanner: View {
  @Environment(AppModel.self) private var model
  @Environment(\.accentMark) private var accentMark
  var advice: StorageAdvice
  /// Looks up a finding's title for the refused suggestions.
  var title: (String) -> String?
  @State private var showsRejected = false

  var body: some View {
    HStack(alignment: .top, spacing: Metrics.m) {
      Image(systemName: Symbols.assistant)
        .foregroundStyle(accentMark)
        .accessibilityHidden(true)
      VStack(alignment: .leading, spacing: Metrics.s) {
        Text(advice.summary)
          .foregroundStyle(.primary)
          .lineLimit(4)
          .fixedSize(horizontal: false, vertical: true)
        HStack(spacing: Metrics.m) {
          AdviceChips(advice: advice)
          Spacer(minLength: Metrics.m)
          // Who answered, as quiet metadata at the end of the row.
          if advice.escalated {
            Label("Stronger model", systemImage: "brain")
              .help("A stronger model took a closer look")
          }
          Text(model.responderName(advice.provider))
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        if !advice.rejected.isEmpty {
          AdviceDisclosure(isExpanded: $showsRejected) {
            Text(advice.rejected.count == 1 ? "Glade refused 1" : "Glade refused \(advice.rejected.count)")
              .font(.caption)
              .foregroundStyle(.secondary)
          } content: {
            VStack(alignment: .leading, spacing: Metrics.xs) {
              ForEach(advice.rejected) { note in
                VStack(alignment: .leading, spacing: 1) {
                  Text(title(note.id) ?? note.id)
                  Text(verbatim: note.why)
                    .foregroundStyle(.secondary)
                }
                .font(.caption)
                .accessibilityElement(children: .combine)
              }
            }
          }
        }
      }
      Spacer(minLength: 0)
    }
    .padding(.horizontal, Metrics.l)
    .padding(.vertical, Metrics.m)
    .background(Palette.card, in: .rect(cornerRadius: Metrics.cardRadius))
  }
}
