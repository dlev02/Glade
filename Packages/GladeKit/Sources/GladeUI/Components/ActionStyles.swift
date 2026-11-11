import SwiftUI

/// The kinds of button outside toolbars, so each purpose looks the same on every
/// screen. Liquid Glass belongs to what floats above the content (toolbars, the clean
/// bar, the composer, popovers, the prompt chips); buttons that sit in the content
/// (cards, rows, banners, forms, sheets) are plain filled capsules with words only.
/// Toolbars use the system’s own items. Minor row actions use `.borderless`.
extension View {
  /// The one main action on a surface: an accent-filled capsule with a white label.
  public func principalAction() -> some View {
    buttonStyle(FilledActionStyle()).labelStyle(.titleOnly)
  }

  /// A secondary action in the content: a quiet grey capsule with a primary label.
  public func secondaryAction() -> some View {
    buttonStyle(QuietFillStyle()).labelStyle(.titleOnly)
  }

  /// A button floating over the content on its own, such as the prompt chips on an
  /// empty Assistant page: neutral glass with a primary label.
  public func floatingAction() -> some View {
    buttonStyle(FloatingGlassStyle())
  }

  /// The main action when it sits on glass already (the clean bar, the menu bar
  /// popover). The same filled capsule, so glass never sits on glass.
  public func filledAction() -> some View {
    buttonStyle(FilledActionStyle())
  }
}

/// Padding and height for a capsule button at each control size.
private struct CapsuleMetrics {
  var horizontal: CGFloat
  var vertical: CGFloat
  var height: CGFloat

  init(_ size: ControlSize) {
    switch size {
    case .mini, .small: (horizontal, vertical, height) = (10, 2, 22)
    case .large, .extraLarge: (horizontal, vertical, height) = (16, 7, 34)
    default: (horizontal, vertical, height) = (12, 4, 28)
    }
  }
}

/// An accent-filled capsule with a white label that dims when pressed or disabled. In
/// a window that isn’t active it turns grey with a primary label, as the system’s
/// default buttons do.
public struct FilledActionStyle: ButtonStyle {
  @Environment(\.isEnabled) private var isEnabled
  @Environment(\.appearsActive) private var appearsActive
  @Environment(\.controlSize) private var controlSize
  @State private var hovering = false

  public init() {}

  public func makeBody(configuration: Configuration) -> some View {
    let metrics = CapsuleMetrics(controlSize)
    configuration.label
      .fontWeight(.semibold)
      .foregroundStyle(appearsActive ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
      .padding(.horizontal, metrics.horizontal)
      .padding(.vertical, metrics.vertical)
      .frame(minHeight: metrics.height)
      .background(appearsActive ? AnyShapeStyle(.tint) : AnyShapeStyle(.fill.secondary), in: .capsule)
      .overlay(Capsule().fill(.black.opacity(configuration.isPressed ? 0.18 : hovering ? 0.08 : 0)))
      .opacity(isEnabled ? 1 : 0.4)
      .contentShape(.capsule)
      .onHover { hovering = $0 }
      .animation(.snappy(duration: 0.12), value: configuration.isPressed)
      .animation(.snappy(duration: 0.12), value: hovering)
  }
}

/// A quiet grey capsule with a primary label, for secondary actions in the content.
public struct QuietFillStyle: ButtonStyle {
  @Environment(\.isEnabled) private var isEnabled
  @Environment(\.controlSize) private var controlSize
  @State private var hovering = false

  public init() {}

  public func makeBody(configuration: Configuration) -> some View {
    let metrics = CapsuleMetrics(controlSize)
    configuration.label
      .fontWeight(.medium)
      .foregroundStyle(.primary)
      .padding(.horizontal, metrics.horizontal)
      .padding(.vertical, metrics.vertical)
      .frame(minHeight: metrics.height)
      .background(fill(pressed: configuration.isPressed), in: .capsule)
      .opacity(isEnabled ? 1 : 0.45)
      .contentShape(.capsule)
      .onHover { hovering = $0 }
      .animation(.snappy(duration: 0.12), value: configuration.isPressed)
      .animation(.snappy(duration: 0.12), value: hovering)
  }

  private func fill(pressed: Bool) -> AnyShapeStyle {
    if pressed { return AnyShapeStyle(.fill) }
    return hovering && isEnabled ? AnyShapeStyle(.fill.secondary) : AnyShapeStyle(.fill.tertiary)
  }
}

/// Neutral glass with a primary label, for a button floating over the content.
public struct FloatingGlassStyle: ButtonStyle {
  @Environment(\.isEnabled) private var isEnabled
  @Environment(\.controlSize) private var controlSize

  public init() {}

  public func makeBody(configuration: Configuration) -> some View {
    let metrics = CapsuleMetrics(controlSize)
    configuration.label
      .foregroundStyle(.primary)
      .padding(.horizontal, metrics.horizontal)
      .padding(.vertical, metrics.vertical)
      .frame(minHeight: metrics.height)
      .contentShape(.capsule)
      .glassEffect(.regular.interactive(), in: .capsule)
      .opacity(isEnabled ? (configuration.isPressed ? 0.75 : 1) : 0.45)
  }
}
