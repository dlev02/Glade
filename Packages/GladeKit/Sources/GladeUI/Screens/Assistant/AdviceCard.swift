import GladeKit
import SwiftUI

/// How an answer changed the storage plan: what was added, left alone or flagged,
/// the first few reasons, and every suggestion Glade refused and why.
struct AdviceCard: View {
  @Environment(AppModel.self) private var model
  var advice: StorageAdvice
  /// The newest advice, so the plan's size and the button describe the plan as it is.
  var isCurrent: Bool
  @State private var showsRefused = false

  private static let noteLimit = 3

  var body: some View {
    Card(padding: Metrics.l) {
      VStack(alignment: .leading, spacing: Metrics.m) {
        HStack(alignment: .center, spacing: Metrics.m) {
          VStack(alignment: .leading, spacing: 2) {
            if isCurrent {
              HStack(alignment: .firstTextBaseline, spacing: Metrics.s) {
                Text(Format.bytes(model.selectedBytes))
                  .font(.figure(22))
                  .foregroundStyle(.tint)
                  .contentTransition(.numericText())
                Text("in the plan")
                  .foregroundStyle(.secondary)
              }
              .accessibilityElement(children: .combine)
            }
            Text(counts)
              .font(.callout)
              .foregroundStyle(.secondary)
              .monospacedDigit()
          }
          Spacer(minLength: Metrics.m)
          if isCurrent {
            Button("Review Plan", systemImage: "list.bullet") { model.section = .storage }
              .buttonStyle(.glassProminent)
          }
        }

        let notes = self.notes
        if !notes.isEmpty {
          Divider()
          VStack(alignment: .leading, spacing: Metrics.s) {
            ForEach(notes) { note in
              NoteRow(note: note)
            }
          }
        }

        if advice.escalated || !advice.rejected.isEmpty {
          Divider()
        }
        if advice.escalated {
          Label("Called in a stronger model", systemImage: "brain")
            .font(.callout)
            .foregroundStyle(.secondary)
        }
        if !advice.rejected.isEmpty {
          DisclosureGroup(isExpanded: $showsRefused) {
            VStack(alignment: .leading, spacing: Metrics.s) {
              ForEach(Array(advice.rejected.enumerated()), id: \.offset) { _, note in
                refused(note)
              }
            }
            .padding(.top, Metrics.s)
            .padding(.leading, Metrics.xs)
          } label: {
            Label(advice.rejected.count == 1 ? "Glade refused 1 suggestion" : "Glade refused \(advice.rejected.count) suggestions", systemImage: "hand.raised")
              .font(.callout)
          }
        }
      }
    }
    .frame(maxWidth: 560, alignment: .leading)
  }

  private var counts: String {
    "+\(advice.select.count) added · \(advice.deselect.count) left alone · \(advice.review.count) to review"
  }

  /// The first few reasons, additions first.
  private var notes: [AdviceNote] {
    let all = advice.select.map { AdviceNote(kind: .added, note: $0, title: title(for: $0.id)) }
      + advice.deselect.map { AdviceNote(kind: .leftAlone, note: $0, title: title(for: $0.id)) }
      + advice.review.map { AdviceNote(kind: .review, note: $0, title: title(for: $0.id)) }
    return Array(all.prefix(Self.noteLimit))
  }

  private func title(for id: String) -> String? {
    model.scan?.finding(id)?.title
  }

  private func refused(_ note: StorageAdvice.Note) -> some View {
    VStack(alignment: .leading, spacing: 2) {
      if let title = title(for: note.id) {
        Text(title)
          .font(.callout)
      } else {
        // An identifier the assistant made up; show it exactly, as data.
        Text(verbatim: note.id)
          .font(.callout.monospaced())
          .lineLimit(1)
          .truncationMode(.middle)
      }
      Text(verbatim: note.why)
        .font(.caption)
        .foregroundStyle(.secondary)
    }
    .accessibilityElement(children: .combine)
  }
}

/// One "why" line in the advice card.
private struct NoteRow: View {
  var note: AdviceNote

  var body: some View {
    HStack(alignment: .firstTextBaseline, spacing: Metrics.s) {
      Image(systemName: note.kind.symbol)
        .foregroundStyle(note.kind.style)
        .accessibilityLabel(note.kind.title)
        .frame(width: 16)
      VStack(alignment: .leading, spacing: 1) {
        Text(note.title ?? note.kind.title)
          .font(.callout.weight(.medium))
          .lineLimit(1)
          .truncationMode(.middle)
        if !note.note.why.isEmpty {
          Text(verbatim: note.note.why)
            .font(.callout)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
      }
    }
    .accessibilityElement(children: .combine)
  }
}
