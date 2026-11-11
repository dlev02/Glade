import SwiftUI

/// System, Light and Dark as three small pictures of a window, the chosen one ringed
/// in the accent, each named below, as in System Settings.
struct AppearanceTiles: View {
  @Binding var selection: Appearance

  var body: some View {
    HStack(spacing: Metrics.l) {
      ForEach(Appearance.allCases) { appearance in
        AppearanceTile(appearance: appearance, isSelected: selection == appearance) {
          selection = appearance
        }
      }
    }
    .accessibilityElement(children: .contain)
    .accessibilityLabel("Appearance")
  }
}

private struct AppearanceTile: View {
  var appearance: Appearance
  var isSelected: Bool
  var choose: () -> Void
  @State private var hovering = false
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    Button(action: choose) {
      VStack(spacing: 6) {
        preview
          .frame(width: 64, height: 44)
          .clipShape(.rect(cornerRadius: Metrics.innerRadius))
          .overlay {
            RoundedRectangle(cornerRadius: Metrics.innerRadius)
              .strokeBorder(Palette.hairline, lineWidth: Metrics.hairline)
          }
          .padding(3)
          .overlay {
            RoundedRectangle(cornerRadius: Metrics.innerRadius + 3)
              .strokeBorder(ringStyle, lineWidth: 3)
          }
        Text(appearance.title)
          .font(.callout)
          .foregroundStyle(isSelected ? .primary : .secondary)
      }
      .contentShape(.rect)
    }
    .buttonStyle(.plain)
    .onHover { hovering = $0 }
    .animation(reduceMotion ? nil : .snappy(duration: 0.14), value: hovering)
    .animation(reduceMotion ? nil : .snappy(duration: 0.14), value: isSelected)
    .accessibilityLabel(appearance.title)
    .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
  }

  private var ringStyle: AnyShapeStyle {
    if isSelected { return AnyShapeStyle(.tint) }
    return hovering ? AnyShapeStyle(Color.primary.opacity(0.15)) : AnyShapeStyle(Color.clear)
  }

  @ViewBuilder private var preview: some View {
    switch appearance {
    case .light: WindowPicture(dark: false)
    case .dark: WindowPicture(dark: true)
    case .system:
      ZStack {
        WindowPicture(dark: false)
        WindowPicture(dark: true)
          .mask(alignment: .trailing) {
            Rectangle().frame(width: 32)
          }
      }
    }
  }
}

/// A tiny window: a desktop tint, a sidebar strip and a few lines of content.
private struct WindowPicture: View {
  var dark: Bool

  var body: some View {
    let desktop = dark ? Color(white: 0.16) : Color(white: 0.86)
    let window = dark ? Color(white: 0.24) : Color.white
    let sidebar = dark ? Color(white: 0.3) : Color(white: 0.93)
    let line = dark ? Color(white: 0.45) : Color(white: 0.78)
    ZStack(alignment: .topLeading) {
      desktop
      HStack(spacing: 0) {
        sidebar.frame(width: 14)
        VStack(alignment: .leading, spacing: 3) {
          Capsule().fill(.tint).frame(width: 18, height: 3)
          Capsule().fill(line).frame(width: 26, height: 3)
          Capsule().fill(line).frame(width: 20, height: 3)
        }
        .padding(5)
        Spacer(minLength: 0)
      }
      .background(window)
      .padding(.leading, 8)
      .padding(.top, 8)
    }
  }
}
