import GladeKit
import SwiftUI

/// How advice changed the selection, as small chips: "+2 added", "1 left alone",
/// "1 to review". Kinds that didn’t happen are left out. Given `reveal`, each chip
/// opens a short list of its findings and reasons, and choosing one shows its row.
struct AdviceChips: View {
  var advice: StorageAdvice
  /// The finding’s title from the scan, for the chips' lists.
  var title: (String) -> String? = { _ in nil }
  /// Shows a finding’s row in the list. Without it the chips are plain labels.
  var reveal: ((String) -> Void)?
  /// How far below the chips their lists open, so a list never half-covers a line
  /// that sits directly under them.
  var clearBelow: CGFloat = 0
  /// A chip’s height, for placing its list.
  private static let chipHeight: CGFloat = 22
  @Environment(\.accentMark) private var accentMark
  @State private var open: AdviceNote.Kind?

  var body: some View {
    HStack(spacing: Metrics.m) {
      ForEach(AdviceNote.Kind.allCases, id: \.self) { kind in
        let notes = kind.notes(in: advice)
        if !notes.isEmpty {
          if let reveal {
            chipButton(kind, notes: notes, reveal: reveal)
          } else {
            label(kind, count: notes.count)
          }
        }
      }
    }
    .font(.caption)
    .monospacedDigit()
    .accessibilityElement(children: reveal == nil ? .combine : .contain)
    .task {
      // `-demoAdviceChip added|leftAlone|review` opens that chip’s list, for screenshots.
      guard reveal != nil, let name = DemoState.value("demoAdviceChip") else { return }
      try? await Task.sleep(for: .seconds(1))
      open = AdviceNote.Kind.allCases.first { "\($0)" == name }
    }
  }

  private func label(_ kind: AdviceNote.Kind, count: Int) -> some View {
    Label {
      Text(kind.count(count))
        .foregroundStyle(.secondary)
    } icon: {
      Image(systemName: kind.symbol)
        .foregroundStyle(kind.style(mark: accentMark))
    }
    .labelStyle(ChipLabelStyle())
  }

  private func chipButton(_ kind: AdviceNote.Kind, notes: [StorageAdvice.Note], reveal: @escaping (String) -> Void) -> some View {
    Button {
      open = open == kind ? nil : kind
    } label: {
      label(kind, count: notes.count)
    }
    .buttonStyle(ChipButtonStyle(isOpen: open == kind))
    .accessibilityHint("Lists them")
    .accessibilityIdentifier("advice.chip.\(kind)")
    .popover(
      isPresented: Binding(get: { open == kind }, set: { if !$0, open == kind { open = nil } }),
      // Below the chip, or below the line under it, so the list never half-covers that line.
      attachmentAnchor: .point(UnitPoint(x: 0.5, y: 1 + clearBelow / Self.chipHeight)),
      arrowEdge: .bottom
    ) {
      ChipList(kind: kind, notes: notes, title: title) { id in
        open = nil
        reveal(id)
      }
    }
  }
}

/// A chip’s findings: each name and its size, with the assistant’s reason under it.
/// Choosing one shows its row in the list.
private struct ChipList: View {
  @Environment(AppModel.self) private var model
  var kind: AdviceNote.Kind
  var notes: [StorageAdvice.Note]
  var title: (String) -> String?
  var choose: (String) -> Void
  @State private var hovered: String?

  /// Each listed finding’s size, looked up once.
  private var sizes: [String: Int64] {
    let ids = Set(notes.map(\.id))
    var sizes: [String: Int64] = [:]
    for finding in model.scan?.findings ?? [] where ids.contains(finding.id) { sizes[finding.id] = finding.bytes }
    return sizes
  }

  var body: some View {
    let sizes = self.sizes
    ScrollView {
      VStack(alignment: .leading, spacing: 2) {
        ForEach(notes) { note in
          Button {
            choose(note.id)
          } label: {
            VStack(alignment: .leading, spacing: 1) {
              if let name = title(note.id) {
                HStack(alignment: .firstTextBaseline, spacing: Metrics.s) {
                  Text(name)
                    .lineLimit(2)
                  Spacer(minLength: Metrics.s)
                  if let bytes = sizes[note.id] {
                    Text(Format.bytes(bytes))
                      .monospacedDigit()
                      .foregroundStyle(.secondary)
                      .fixedSize()
                  }
                }
              } else {
                // An identifier the assistant made up; show it exactly, as data.
                Text(verbatim: note.id)
                  .monospaced()
                  .lineLimit(1)
                  .truncationMode(.middle)
              }
              if !note.why.isEmpty {
                Text(verbatim: note.why)
                  .font(.callout)
                  .foregroundStyle(.secondary)
                  .fixedSize(horizontal: false, vertical: true)
              }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Metrics.s)
            .padding(.vertical, 6)
            .background(Color.primary.opacity(hovered == note.id ? 0.07 : 0), in: .rect(cornerRadius: 6))
            .contentShape(.rect)
          }
          .buttonStyle(.plain)
          .disabled(title(note.id) == nil)
          .onHover { inside in
            if inside { hovered = note.id } else if hovered == note.id { hovered = nil }
          }
          .accessibilityElement(children: .combine)
        }
      }
      .padding(6)
    }
    .scrollBounceBehavior(.basedOnSize)
    // Its own type, not the chip’s caption and grey.
    .font(.body)
    .foregroundStyle(.primary)
    .frame(width: 320)
    .frame(maxHeight: 320)
    .fixedSize(horizontal: false, vertical: true)
  }
}

/// A chip that opens a list: no capsule at rest, so the first glyph keeps the text’s
/// edge; a faint fill under the pointer or while open.
private struct ChipButtonStyle: ButtonStyle {
  var isOpen: Bool
  @State private var isHovered = false

  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .padding(.horizontal, 5)
      .padding(.vertical, 2)
      .background(
        Color.primary.opacity(configuration.isPressed ? 0.12 : (isOpen || isHovered ? 0.07 : 0)),
        in: .capsule
      )
      .padding(.horizontal, -5)
      .contentShape(.capsule)
      .onHover { isHovered = $0 }
  }
}

/// A coloured glyph and grey words, with no capsule, so the first glyph sits on the
/// same leading edge as the text above it.
private struct ChipLabelStyle: LabelStyle {
  func makeBody(configuration: Configuration) -> some View {
    HStack(spacing: 4) {
      configuration.icon
        .imageScale(.small)
      configuration.title
    }
  }
}
