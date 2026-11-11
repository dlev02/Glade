import GladeKit
import SwiftUI

/// How advice changed the selection, as small chips: "+2 added", "1 left alone",
/// "1 to review". Kinds that didn't happen are left out.
struct AdviceChips: View {
  var advice: StorageAdvice
  @Environment(\.accentMark) private var accentMark

  var body: some View {
    HStack(spacing: Metrics.m) {
      ForEach(AdviceNote.Kind.allCases, id: \.self) { kind in
        let count = kind.notes(in: advice).count
        if count > 0 {
          Label {
            Text(kind.count(count))
              .foregroundStyle(.secondary)
          } icon: {
            Image(systemName: kind.symbol)
              .foregroundStyle(kind.style(mark: accentMark))
          }
          .labelStyle(ChipLabelStyle())
        }
      }
    }
    .font(.caption)
    .monospacedDigit()
    .accessibilityElement(children: .combine)
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
