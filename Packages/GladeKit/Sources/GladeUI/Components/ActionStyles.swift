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
    // Untinted glass, so the window's accent doesn't turn it into a second principal button.
    buttonStyle(SecondaryGlassStyle())
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

/// A neutral glass capsule with a primary label. The system's glass button takes the
/// window's tint, which made every secondary button look like the principal one.
public struct SecondaryGlassStyle: ButtonStyle {
  @Environment(\.isEnabled) private var isEnabled
  @Environment(\.controlSize) private var controlSize

  public init() {}

  public func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .foregroundStyle(.primary)
      .padding(.horizontal, horizontalPadding)
      .padding(.vertical, verticalPadding)
      .frame(minHeight: minHeight)
      .contentShape(.capsule)
      .glassEffect(.regular.interactive(), in: .capsule)
      .opacity(isEnabled ? (configuration.isPressed ? 0.75 : 1) : 0.45)
  }

  private var horizontalPadding: CGFloat {
    switch controlSize {
    case .mini, .small: 10
    case .large, .extraLarge: 16
    default: 12
    }
  }

  private var verticalPadding: CGFloat {
    switch controlSize {
    case .mini, .small: 2
    case .large, .extraLarge: 7
    default: 4
    }
  }

  private var minHeight: CGFloat {
    switch controlSize {
    case .mini, .small: 22
    case .large, .extraLarge: 34
    default: 28
    }
  }
}
