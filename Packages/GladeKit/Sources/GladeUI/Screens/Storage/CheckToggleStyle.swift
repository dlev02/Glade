import SwiftUI

/// The storage list's checkbox: a square that fills with the accent, with a small
/// bounce when someone ticks it. Mixed shows a dash. In a window that isn't active it
/// turns grey, like the system's own checkboxes and the sidebar's selection. It reads
/// to VoiceOver as a toggle with its on, off or mixed state.
struct CheckToggleStyle: ToggleStyle {
  func makeBody(configuration: Configuration) -> some View {
    CheckBox(configuration: configuration)
  }
}

private struct CheckBox: View {
  var configuration: ToggleStyleConfiguration
  @Environment(\.isEnabled) private var isEnabled
  @Environment(\.appearsActive) private var appearsActive
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  /// Counts ticks made by clicking, so only those bounce, not a change of level
  /// that ticks dozens of rows at once.
  @State private var ticks = 0

  var body: some View {
    let filled = configuration.isOn || configuration.isMixed
    Button {
      if !configuration.isOn, !reduceMotion { ticks += 1 }
      configuration.isOn.toggle()
    } label: {
      Image(systemName: configuration.isMixed ? "minus.square.fill" : configuration.isOn ? "checkmark.square.fill" : "square")
        .symbolRenderingMode(.palette)
        .foregroundStyle(
          filled ? AnyShapeStyle(.white) : AnyShapeStyle(.secondary),
          filled ? (appearsActive ? AnyShapeStyle(.tint) : AnyShapeStyle(Palette.inactiveFill)) : AnyShapeStyle(.secondary)
        )
        .font(.system(size: 15))
        .symbolEffect(.bounce, options: .speed(1.5), value: ticks)
        .frame(width: 18, height: 18)
        .contentShape(.rect)
    }
    .buttonStyle(.plain)
    .opacity(isEnabled ? 1 : 0.4)
    .accessibilityLabel { _ in configuration.label }
    .accessibilityValue(configuration.isMixed ? "Mixed" : configuration.isOn ? "On" : "Off")
    .accessibilityAddTraits(.isToggle)
  }
}
