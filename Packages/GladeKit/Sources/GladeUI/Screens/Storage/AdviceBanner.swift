import GladeKit
import SwiftUI

/// What the assistant said about the selection, how it changed it, and, plainly,
/// any suggestions Glade refused because they broke a safety rule. It is the storage
/// list's first row and follows the rows' grid: the sparkle in the checkbox column,
/// the words and chips on the titles' edge, who answered on the sizes' trailing edge.
struct AdviceBanner: View {
  @Environment(AppModel.self) private var model
  @Environment(\.accentMark) private var accentMark
  var advice: StorageAdvice
  /// Looks up a finding's title for the refused suggestions.
  var title: (String) -> String?
  @State private var showsRejected = false

  var body: some View {
    HStack(alignment: .firstTextBaseline, spacing: Metrics.s) {
      Image(systemName: Symbols.assistant)
        .foregroundStyle(accentMark)
        .frame(width: FindingRow.checkWidth)
        .alignmentGuide(.listRowSeparatorLeading) { $0[.leading] }
        .accessibilityHidden(true)
      VStack(alignment: .leading, spacing: Metrics.s) {
        MarkdownText(advice.summary)
          .fixedSize(horizontal: false, vertical: true)
        HStack(alignment: .firstTextBaseline, spacing: Metrics.m) {
          AdviceChips(advice: advice)
          Spacer(minLength: Metrics.m)
          // Who answered, as quiet metadata at the end of the row.
          if advice.escalated {
            Label("Stronger model", systemImage: "brain")
              .help("A stronger model took a closer look")
          }
          Text(model.responderName(advice.provider, model: advice.model))
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
    }
    // The same breathing room above and below: the list already adds its own top
    // margin, so the row gives back that much at the top.
    .padding(.top, -Metrics.s)
    .padding(.bottom, Metrics.m)
  }
}
