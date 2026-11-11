import GladeKit
import SwiftUI

/// How an answer changed the selection: its size and a way to review it, what was
/// added, left alone or flagged, the first few reasons, and what Glade refused.
/// Once anything else changes the selection, the card becomes an "Earlier selection"
/// that folds away and can't be acted on.
struct AdviceCard: View {
  @Environment(AppModel.self) private var model
  @Environment(\.accentMark) private var accentMark
  var advice: StorageAdvice
  /// The advice still describes the selection as it is.
  var isLive: Bool
  @State private var showsRefused = false
  @State private var showsEarlier = false

  private static let noteLimit = 3

  var body: some View {
    Group {
      if isLive {
        Card(padding: Metrics.l) {
          VStack(alignment: .leading, spacing: Metrics.m) {
            header
            details
          }
        }
      } else {
        // No card: an earlier selection is a note in the conversation, not a thing to act on.
        AdviceDisclosure(isExpanded: $showsEarlier) {
          Text("Earlier selection")
            .font(.callout)
            .foregroundStyle(.secondary)
        } content: {
          details
            .padding(.leading, Metrics.m)
        }
      }
    }
    .frame(maxWidth: 560, alignment: .leading)
  }

  private var header: some View {
    HStack(alignment: .center, spacing: Metrics.m) {
      VStack(alignment: .leading, spacing: 2) {
        Text("Current selection")
          .font(.callout)
          .foregroundStyle(.secondary)
        Text(Format.bytes(model.selectedBytes))
          .font(.figure(24))
          .foregroundStyle(accentMark)
          .contentTransition(.numericText())
      }
      .accessibilityElement(children: .combine)
      Spacer(minLength: Metrics.m)
      Button("Review Selection", systemImage: Symbols.review) { model.section = .storage }
        .principalAction()
    }
  }

  @ViewBuilder private var details: some View {
    VStack(alignment: .leading, spacing: Metrics.m) {
      AdviceChips(advice: advice)

      let notes = self.notes
      if !notes.isEmpty {
        VStack(alignment: .leading, spacing: Metrics.s) {
          ForEach(notes) { note in
            NoteRow(note: note)
          }
        }
      }

      if advice.escalated || !advice.rejected.isEmpty {
        HStack(alignment: .firstTextBaseline, spacing: Metrics.l) {
          if !advice.rejected.isEmpty {
            AdviceDisclosure(isExpanded: $showsRefused) {
              Text(advice.rejected.count == 1 ? "Glade refused 1" : "Glade refused \(advice.rejected.count)")
            } content: {
              VStack(alignment: .leading, spacing: Metrics.s) {
                ForEach(Array(advice.rejected.enumerated()), id: \.offset) { _, note in
                  refused(note)
                }
              }
            }
          }
          if advice.escalated {
            Label("Stronger model", systemImage: "brain")
              .help("A stronger model took a closer look")
          }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
      }
    }
  }

  /// The first few reasons, additions first.
  private var notes: [AdviceNote] {
    let all = AdviceNote.Kind.allCases.flatMap { kind in
      kind.notes(in: advice).map { note in
        let finding = model.scan?.finding(note.id)
        return AdviceNote(kind: kind, note: note, title: finding?.title, bytes: finding?.bytes)
      }
    }
    return Array(all.prefix(Self.noteLimit))
  }

  private func refused(_ note: StorageAdvice.Note) -> some View {
    VStack(alignment: .leading, spacing: 1) {
      if let title = model.scan?.finding(note.id)?.title {
        Text(title)
          .foregroundStyle(.primary)
      } else {
        // An identifier the assistant made up; show it exactly, as data.
        Text(verbatim: note.id)
          .monospaced()
          .foregroundStyle(.primary)
          .lineLimit(1)
          .truncationMode(.middle)
      }
      Text(verbatim: note.why)
    }
    .accessibilityElement(children: .combine)
  }
}

/// One reason in the advice card: what happened, to what, why, and its size.
private struct NoteRow: View {
  var note: AdviceNote
  @Environment(\.accentMark) private var accentMark

  var body: some View {
    HStack(alignment: .firstTextBaseline, spacing: Metrics.s) {
      Image(systemName: note.kind.symbol)
        .foregroundStyle(note.kind.style(mark: accentMark))
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
            .lineLimit(1)
            .help(note.note.why)
        }
      }
      Spacer(minLength: Metrics.m)
      if let bytes = note.bytes {
        Text(Format.bytes(bytes))
          .font(.callout)
          .foregroundStyle(.secondary)
          .monospacedDigit()
      }
    }
    .accessibilityElement(children: .combine)
  }
}
