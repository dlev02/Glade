import AppKit
import GladeKit
import SwiftUI

/// The accent colours as a row of round swatches, the current one marked with a dot
/// and ringed, plus a rainbow swatch that opens the colours window for one of the
/// person's own.
struct AccentSwatches: View {
  @Environment(AppModel.self) private var model
  @State private var colorPanel = ColorPanelBridge()

  var body: some View {
    HStack(spacing: Metrics.s) {
      ForEach(Accent.allCases.filter { $0 != .custom }) { accent in
        AccentSwatch(title: accent.title, fill: AnyShapeStyle(accent.color().gradient), isSelected: model.accent == accent) {
          model.accent = accent
        }
      }
      AccentSwatch(title: "Custom", fill: customFill, isSelected: model.accent == .custom) {
        colorPanel.open(with: NSColor(Color(hex: model.customAccent) ?? Palette.glade)) { color in
          model.customAccent = Color(nsColor: color).hexString
          model.accent = .custom
        }
      }
    }
  }

  /// The person's own colour once they've chosen one, otherwise every colour.
  private var customFill: AnyShapeStyle {
    if model.accent == .custom, let color = Color(hex: model.customAccent) {
      return AnyShapeStyle(color.gradient)
    }
    return AnyShapeStyle(AngularGradient(colors: [.red, .yellow, .green, .cyan, .blue, .purple, .red], center: .center))
  }
}

/// One round swatch: a ring on hover, and a white dot plus a ring when chosen.
private struct AccentSwatch: View {
  var title: String
  var fill: AnyShapeStyle
  var isSelected: Bool
  var choose: () -> Void
  @State private var hovering = false
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    Button(action: choose) {
      Circle()
        .fill(fill)
        .frame(width: 18, height: 18)
        .overlay {
          if isSelected {
            Circle().fill(.white).frame(width: 6, height: 6)
          }
        }
        .padding(3)
        .overlay {
          Circle()
            .strokeBorder(ring, lineWidth: 2)
        }
        .contentShape(.circle)
    }
    .buttonStyle(.plain)
    .onHover { hovering = $0 }
    .animation(reduceMotion ? nil : .snappy(duration: 0.12), value: hovering)
    .animation(reduceMotion ? nil : .snappy(duration: 0.12), value: isSelected)
    .help(title)
    .accessibilityLabel(title)
    .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
  }

  private var ring: Color {
    if isSelected { return Color.primary.opacity(0.45) }
    return hovering ? Color.primary.opacity(0.2) : .clear
  }
}

/// Opens the shared colours window and reports each colour picked there.
@MainActor
private final class ColorPanelBridge: NSObject {
  private var onChange: (NSColor) -> Void = { _ in }

  func open(with color: NSColor, onChange: @escaping (NSColor) -> Void) {
    self.onChange = onChange
    let panel = NSColorPanel.shared
    panel.showsAlpha = false
    panel.color = color
    panel.setTarget(self)
    panel.setAction(#selector(colorChanged(_:)))
    panel.makeKeyAndOrderFront(nil)
  }

  @objc private func colorChanged(_ sender: NSColorPanel) {
    onChange(sender.color)
  }
}
