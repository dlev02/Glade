import SwiftUI

/// The three kinds of button outside toolbars, so each purpose looks the same on
/// every screen. Toolbars use the system's own items. Rows and menus use `.borderless`.
/// Never put a glass button inside a glass container: use `filledAction` there.
extension View {
  /// The one main action on a surface.
  public func principalAction() -> some View {
    buttonStyle(.glassProminent).buttonBorderShape(.capsule)
  }

  /// A standalone secondary action.
  public func secondaryAction() -> some View {
    // Clear tint, so the window's accent doesn't turn it into a second principal button.
    buttonStyle(.glass).buttonBorderShape(.capsule).tint(.clear)
  }

  /// The main action when it sits on glass already (the clean bar, the menu bar
  /// popover): a plain accent-filled capsule, so glass never sits on glass.
  public func filledAction() -> some View {
    buttonStyle(FilledActionStyle())
  }
}

/// An accent-filled capsule with white text that dims when pressed or disabled.
public struct FilledActionStyle: ButtonStyle {
  @Environment(\.isEnabled) private var isEnabled

  public init() {}

  public func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .font(.body.weight(.semibold))
      .foregroundStyle(.white)
      .padding(.horizontal, Metrics.l)
      .padding(.vertical, Metrics.s)
      .frame(minHeight: 32)
      .background(.tint, in: .capsule)
      .opacity(isEnabled ? (configuration.isPressed ? 0.8 : 1) : 0.4)
      .contentShape(.capsule)
      .animation(.snappy(duration: 0.12), value: configuration.isPressed)
  }
}
