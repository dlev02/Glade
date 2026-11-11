import SwiftUI

/// The popover’s footer buttons: plain text or a symbol, like borderless buttons, with
/// a soft fill under the pointer so they read as clickable.
struct PopoverFooterButtonStyle: ButtonStyle {
  @Environment(\.isEnabled) private var isEnabled
  @State private var hovering = false

  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .foregroundStyle(hovering ? .primary : .secondary)
      .padding(.horizontal, Metrics.s)
      .frame(minWidth: 28, minHeight: 24)
      .background(.fill.opacity(configuration.isPressed ? 0.9 : hovering ? 0.6 : 0), in: .capsule)
      .opacity(isEnabled ? 1 : 0.45)
      .contentShape(.capsule)
      .onHover { hovering = $0 }
      .animation(.snappy(duration: 0.12), value: hovering)
      .animation(.snappy(duration: 0.12), value: configuration.isPressed)
  }
}
