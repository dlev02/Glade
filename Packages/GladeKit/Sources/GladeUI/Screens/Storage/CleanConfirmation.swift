import GladeKit
import SwiftUI

/// Says exactly what a clean will do before it starts: how much goes for good, how
/// much goes to the Trash, and every selected item, with a warning on anything
/// nothing can bring back.
struct CleanConfirmation: View {
  @Environment(AppModel.self) private var model
  var cancel: () -> Void
  var confirm: () -> Void

  var body: some View {
    let total = model.selectedBytes
    let immediate = model.immediateBytes
    let trash = max(0, total - immediate)
    let items = selected
    VStack(alignment: .leading, spacing: Metrics.l) {
      Text("Free up \(Format.bytes(total))?")
        .font(.title2.weight(.semibold))
        .monospacedDigit()

      VStack(alignment: .leading, spacing: Metrics.s) {
        if immediate > 0 {
          outcome("\(Format.bytes(immediate)) removed straight away", symbol: "bolt", detail: "Rebuilds or downloads again")
        }
        if trash > 0 {
          outcome("\(Format.bytes(trash)) moved to the Trash", symbol: "trash", detail: "Can be put back")
        }
      }

      if !items.isEmpty {
        ScrollView {
          VStack(spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, finding in
              if index > 0 { Divider() }
              row(finding)
            }
          }
          .padding(.horizontal, Metrics.m)
          .padding(.vertical, Metrics.xs)
        }
        .frame(maxHeight: 260)
        .fixedSize(horizontal: false, vertical: true)
        .background(Palette.card, in: .rect(cornerRadius: Metrics.innerRadius))
        .overlay {
          RoundedRectangle(cornerRadius: Metrics.innerRadius)
            .strokeBorder(Palette.hairline.opacity(0.6), lineWidth: Metrics.hairline)
        }
      }

      HStack(spacing: Metrics.s) {
        Spacer()
        Button("Cancel", action: cancel)
          .secondaryAction()
          .controlSize(.large)
          .keyboardShortcut(.cancelAction)
        Button(total > 0 ? "Free Up \(Format.bytes(total))" : "Free Up", action: confirm)
          .principalAction()
          .controlSize(.large)
          .monospacedDigit()
          .keyboardShortcut(.defaultAction)
          .disabled(total == 0 && model.selectedIDs.isEmpty)
      }
    }
    .padding(Metrics.xl)
  }

  private func row(_ finding: Finding) -> some View {
    HStack(spacing: Metrics.s) {
      CategoryIcon(finding.category, size: 20)
      VStack(alignment: .leading, spacing: 1) {
        Text(finding.title)
          .lineLimit(1)
          .truncationMode(.middle)
        if finding.recovery == .permanent {
          Label(finding.recovery.explanation, systemImage: finding.recovery.symbol)
            .font(.caption)
            .foregroundStyle(finding.recovery.color)
            .fixedSize(horizontal: false, vertical: true)
        }
      }
      Spacer(minLength: Metrics.s)
      Text(Format.bytes(finding.bytes))
        .monospacedDigit()
        .foregroundStyle(.secondary)
    }
    .padding(.vertical, 6)
    .accessibilityElement(children: .combine)
  }

  private func outcome(_ title: String, symbol: String, detail: String) -> some View {
    HStack(alignment: .firstTextBaseline, spacing: Metrics.s) {
      Image(systemName: symbol)
        .foregroundStyle(.secondary)
        .frame(width: 20)
        .accessibilityHidden(true)
      VStack(alignment: .leading, spacing: 1) {
        Text(title)
          .fontWeight(.medium)
          .monospacedDigit()
        Text(detail)
          .font(.callout)
          .foregroundStyle(.secondary)
      }
    }
    .accessibilityElement(children: .combine)
  }

  /// Every selected finding, biggest first, leaving out ones inside another selected
  /// finding (they go with it).
  private var selected: [Finding] {
    guard let scan = model.scan else { return [] }
    let chosen = Set(model.selectedIDs)
    return scan.findings
      .filter { chosen.contains($0.id) && !($0.within.map(chosen.contains) ?? false) }
      .sorted { $0.bytes > $1.bytes }
  }
}
