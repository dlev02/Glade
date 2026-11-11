import GladeKit
import SwiftUI

/// Says exactly what a clean will do before it starts: how much goes for good, how
/// much goes to the Trash, and the biggest things by name.
struct CleanConfirmation: View {
  @Environment(AppModel.self) private var model
  var cancel: () -> Void
  var confirm: () -> Void

  private static let shownItems = 4

  var body: some View {
    let total = model.selectedBytes
    let immediate = model.immediateBytes
    let trash = max(0, total - immediate)
    let largest = largestSelected
    VStack(alignment: .leading, spacing: Metrics.l) {
      Text("Free up \(Format.bytes(total))?")
        .font(.title2.weight(.semibold))

      VStack(alignment: .leading, spacing: Metrics.m) {
        if immediate > 0 {
          outcome(
            "\(Format.bytes(immediate)) removed straight away", symbol: "bolt",
            detail: "Things that rebuild or download again."
          )
        }
        if trash > 0 {
          outcome(
            "\(Format.bytes(trash)) moved to the Trash", symbol: "trash",
            detail: "You can put it back."
          )
        }
      }

      if !largest.items.isEmpty {
        VStack(spacing: 0) {
          ForEach(Array(largest.items.enumerated()), id: \.element.id) { index, finding in
            if index > 0 { Divider() }
            HStack(spacing: Metrics.s) {
              CategoryIcon(finding.category, size: 20)
              Text(finding.title)
                .lineLimit(1)
                .truncationMode(.middle)
              Spacer(minLength: Metrics.s)
              Text(Format.bytes(finding.bytes))
                .monospacedDigit()
                .foregroundStyle(.secondary)
            }
            .padding(.vertical, 6)
          }
          if largest.others > 0 {
            Divider()
            Text("and \(largest.others) more")
              .foregroundStyle(.secondary)
              .frame(maxWidth: .infinity, alignment: .leading)
              .padding(.vertical, 6)
          }
        }
        .padding(.horizontal, Metrics.m)
        .padding(.vertical, Metrics.xs)
        .background(Palette.card, in: .rect(cornerRadius: Metrics.innerRadius))
        .overlay {
          RoundedRectangle(cornerRadius: Metrics.innerRadius)
            .strokeBorder(Palette.hairline.opacity(0.6), lineWidth: Metrics.hairline)
        }
      }

      HStack {
        Spacer()
        Button("Cancel", action: cancel)
          .keyboardShortcut(.cancelAction)
        Button("Free Up", action: confirm)
          .keyboardShortcut(.defaultAction)
          .disabled(total == 0 && model.selectedIDs.isEmpty)
      }
    }
    .padding(Metrics.xl)
  }

  private func outcome(_ title: String, symbol: String, detail: String) -> some View {
    HStack(alignment: .firstTextBaseline, spacing: Metrics.m) {
      Image(systemName: symbol)
        .foregroundStyle(.secondary)
        .frame(width: 20)
        .accessibilityHidden(true)
      VStack(alignment: .leading, spacing: 2) {
        Text(title)
          .font(.headline)
          .monospacedDigit()
        Text(detail)
          .foregroundStyle(.secondary)
      }
    }
    .accessibilityElement(children: .combine)
  }

  /// The biggest selected findings, leaving out ones inside another selected finding,
  /// and how many more there are.
  private var largestSelected: (items: [Finding], others: Int) {
    guard let scan = model.scan else { return ([], 0) }
    let chosen = Set(model.selectedIDs)
    let top = scan.findings
      .filter { chosen.contains($0.id) && !($0.within.map(chosen.contains) ?? false) }
      .sorted { $0.bytes > $1.bytes }
    return (Array(top.prefix(Self.shownItems)), max(0, top.count - Self.shownItems))
  }
}
