import GladeKit
import SwiftUI

/// The few words in a panel’s corner saying how things stand, with a symbol so the
/// state never rests on colour alone. Calm states stay quiet; the rest stand out.
struct PanelStatus: View {
  var text: String
  var symbol: String?
  var color: Color
  var prominent: Bool

  static let measuring = PanelStatus(text: "Measuring…", symbol: nil, color: .secondary, prominent: false)

  /// The word follows the same thresholds as the line’s colour, so a green line never
  /// says "Busy".
  static func load(_ percent: Double) -> PanelStatus {
    let fraction = percent / 100
    return PanelStatus(
      text: PerformanceFormat.load(percent), symbol: nil,
      color: Palette.load(fraction), prominent: fraction >= 0.7
    )
  }

  static func pressure(_ pressure: MemoryPressure) -> PanelStatus {
    PanelStatus(text: pressure.title, symbol: nil, color: pressure.color, prominent: pressure != .normal)
  }

  /// One style on every panel: a small dot in the state’s colour and a word, the word
  /// coloured too once the state needs attention.
  var body: some View {
    HStack(spacing: 5) {
      if color != .secondary {
        Circle()
          .fill(color)
          .frame(width: 6, height: 6)
          .accessibilityHidden(true)
      }
      Text(text)
        .foregroundStyle(prominent ? AnyShapeStyle(color) : AnyShapeStyle(.secondary))
    }
    .font(.subheadline.weight(prominent ? .semibold : .regular))
    .lineLimit(1)
  }
}
