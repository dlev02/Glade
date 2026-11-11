import GladeKit
import SwiftUI

/// The accent colours as a row of round swatches, the current one ringed, plus a
/// colour well for one of the person's own.
struct AccentSwatches: View {
  @Environment(AppModel.self) private var model

  var body: some View {
    HStack(spacing: Metrics.s) {
      ForEach(Accent.allCases.filter { $0 != .custom }) { accent in
        swatch(accent)
      }
      ColorPicker("Custom", selection: customColor, supportsOpacity: false)
        .labelsHidden()
        .overlay {
          if model.accent == .custom {
            Capsule()
              .strokeBorder(Color.primary.opacity(0.5), lineWidth: 1.5)
              .padding(-3)
              .allowsHitTesting(false)
          }
        }
        .help("Custom")
    }
  }

  private func swatch(_ accent: Accent) -> some View {
    let isCurrent = model.accent == accent
    return Button {
      model.accent = accent
    } label: {
      Circle()
        .fill(accent.color().gradient)
        .frame(width: 16, height: 16)
        .padding(3)
        .overlay {
          Circle()
            .strokeBorder(isCurrent ? Color.primary.opacity(0.5) : .clear, lineWidth: 1.5)
        }
        .contentShape(.circle)
    }
    .buttonStyle(.plain)
    .help(accent.title)
    .accessibilityLabel(accent.title)
    .accessibilityAddTraits(isCurrent ? .isSelected : [])
  }

  private var customColor: Binding<Color> {
    Binding(
      get: { Color(hex: model.customAccent) ?? Palette.glade },
      set: { color in
        model.customAccent = color.hexString
        model.accent = .custom
      }
    )
  }
}
