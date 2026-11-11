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
  /// `-demoExpandAdvice YES` opens every reason, for screenshots.
  @State private var showsAllNotes = DemoState.value("demoExpandAdvice") != nil

  private static let noteLimit = 3
  /// The live card's side padding: the hanging glyphs' gutter and room around them.
  private static let inset: CGFloat = Metrics.xxl

  var body: some View {
    Group {
      if isLive {
        Card(padding: 0) {
          VStack(alignment: .leading, spacing: Metrics.m) {
            header
            details
          }
          .padding(.horizontal, Self.inset)
          .padding(.vertical, Metrics.l)
        }
        // The card's fill reaches outside the answer's text edge, far enough for the
        // reasons' glyphs to hang in it, so every line of words starts exactly where
        // the answer's do.
        .padding(.horizontal, -Self.inset)
      } else {
        // No card: an earlier selection is a note in the conversation, not a thing to act on.
        AdviceDisclosure(isExpanded: $showsEarlier) {
          Text("Earlier selection")
            .font(.callout)
            .foregroundStyle(.secondary)
        } content: {
          details
        }
      }
    }
    // As wide as the answer's column, so the card ends where the text can.
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  private var header: some View {
    HStack(alignment: .center, spacing: Metrics.m) {
      // The same figures as the clean bar: what's freed now, and the Trash apart.
      let free = model.immediateBytes
      let trash = model.trashBytes
      VStack(alignment: .leading, spacing: 2) {
        Text("Current selection")
          .font(.callout)
          .foregroundStyle(.secondary)
        HStack(alignment: .firstTextBaseline, spacing: Metrics.s) {
          Text(Format.bytes(free > 0 ? free : trash))
            .font(.figure(24))
            .foregroundStyle(accentMark)
            .contentTransition(.numericText())
          if free > 0, trash > 0 {
            Text("+ \(Format.bytes(trash)) to the Trash")
              .font(.callout)
              .foregroundStyle(.secondary)
              .monospacedDigit()
          } else if free == 0, trash > 0 {
            Text("to the Trash")
              .font(.callout)
              .foregroundStyle(.secondary)
          }
        }
      }
      .accessibilityElement(children: .combine)
      Spacer(minLength: Metrics.m)
      Button("Review Selection") { model.section = .storage }
        .principalAction()
        .accessibilityIdentifier("advice.review")
    }
  }

  @ViewBuilder private var details: some View {
    VStack(alignment: .leading, spacing: Metrics.m) {
      AdviceChips(advice: advice)

      let notes = self.notes
      if !notes.isEmpty {
        VStack(alignment: .leading, spacing: Metrics.s) {
          ForEach(showsAllNotes ? notes : Array(notes.prefix(Self.noteLimit))) { note in
            NoteRow(note: note)
          }
          if notes.count > Self.noteLimit {
            AdviceDisclosure(isExpanded: $showsAllNotes) {
              Text(showsAllNotes ? "Fewer reasons" : moreReasons(notes.count - Self.noteLimit))
                .font(.caption)
                .foregroundStyle(.secondary)
            } content: {
              EmptyView()
            }
          }
        }
      }

      if advice.escalated || !advice.rejected.isEmpty {
        HStack(alignment: .firstTextBaseline, spacing: Metrics.l) {
          if !advice.rejected.isEmpty {
            AdviceDisclosure(isExpanded: $showsRefused) {
              Text(advice.rejected.count == 1 ? "1 suggestion refused" : "\(advice.rejected.count) suggestions refused")
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

  private func moreReasons(_ count: Int) -> String {
    count == 1 ? "1 more reason" : "\(count) more reasons"
  }

  /// Every reason, taking one of each kind in turn (to review, added, left alone) so
  /// the first few always include each kind there is.
  private var notes: [AdviceNote] {
    let kinds: [AdviceNote.Kind] = [.review, .added, .leftAlone]
    let lists = kinds.map { kind in
      kind.notes(in: advice).map { note in
        let finding = model.scan?.finding(note.id)
        return AdviceNote(kind: kind, note: note, title: finding?.title, bytes: finding?.bytes)
      }
    }
    var ordered: [AdviceNote] = []
    for index in 0..<(lists.map(\.count).max() ?? 0) {
      for list in lists where index < list.count { ordered.append(list[index]) }
    }
    return ordered
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
    // The glyph hangs in the gutter, so the reasons' words share the answer's edge.
    HangingIcon {
      Image(systemName: note.kind.symbol)
        .foregroundStyle(note.kind.style(mark: accentMark))
        .accessibilityLabel(note.kind.title)
    } text: {
      HStack(alignment: .firstTextBaseline, spacing: Metrics.s) {
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
        Spacer(minLength: Metrics.m)
        if let bytes = note.bytes {
          Text(Format.bytes(bytes))
            .font(.callout)
            .foregroundStyle(.secondary)
            .monospacedDigit()
        }
      }
    }
    .accessibilityElement(children: .combine)
  }
}
