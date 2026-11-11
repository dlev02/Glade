import GladeKit
import SwiftUI

/// The few words in a panel's corner saying how things stand, with a symbol so the
/// state never rests on colour alone. Calm states stay quiet; the rest stand out.
struct PanelStatus: View {
  var text: String
  var symbol: String?
  var color: Color
  var prominent: Bool

  static let measuring = PanelStatus(text: "Measuring…", symbol: nil, color: .secondary, prominent: false)

  static func load(_ percent: Double) -> PanelStatus {
    let fraction = percent / 100
    return PanelStatus(
      text: PerformanceFormat.load(percent),
      symbol: fraction < 0.7 ? nil : "exclamationmark.triangle.fill",
      color: Palette.load(fraction), prominent: fraction >= 0.7
    )
  }

  static func pressure(_ pressure: MemoryPressure) -> PanelStatus {
    switch pressure {
    case .normal: PanelStatus(text: pressure.title, symbol: "checkmark.circle.fill", color: Palette.good, prominent: false)
    case .warning: PanelStatus(text: pressure.title, symbol: "exclamationmark.triangle.fill", color: Palette.warning, prominent: true)
    case .critical: PanelStatus(text: pressure.title, symbol: "exclamationmark.octagon.fill", color: Palette.critical, prominent: true)
    }
  }

  var body: some View {
    HStack(spacing: 4) {
      if let symbol {
        Image(systemName: symbol)
          .foregroundStyle(color)
          .accessibilityHidden(true)
      }
      Text(text)
        .foregroundStyle(prominent ? AnyShapeStyle(color) : AnyShapeStyle(.secondary))
    }
    .font(.subheadline.weight(prominent ? .semibold : .regular))
    .lineLimit(1)
    // The capsule reaches above and below the text without making the row taller, so
    // the figure underneath never moves when the state changes.
    .background {
      if prominent {
        Capsule().fill(color.opacity(0.14)).padding(.vertical, -3).padding(.horizontal, -7)
      }
    }
  }
}
