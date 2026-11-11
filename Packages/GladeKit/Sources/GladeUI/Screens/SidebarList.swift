import GladeKit
import SwiftUI

/// The sections, drawn by Glade rather than AppKit so the selection takes the colour
/// the person chose: a rounded fill in the readable accent with a white label while
/// the window is key, a neutral fill when it isn’t. Arrow keys move between
/// sections, ⌘1–⌘5 still work (from the View menu), and VoiceOver hears which one is
/// selected. The sidebar’s material comes from the split view, as before.
struct SidebarList: View {
  @Environment(AppModel.self) private var model
  @FocusState private var focused: Bool

  var body: some View {
    ScrollView {
      VStack(spacing: 2) {
        ForEach(AppModel.Section.allCases) { section in
          SidebarRow(section: section, metrics: SidebarMetrics.current, focused: focused)
        }
      }
      .padding(.horizontal, 10)
      .padding(.top, 2)
      .padding(.bottom, Metrics.s)
    }
    .scrollBounceBehavior(.basedOnSize)
    .focusable()
    .focused($focused)
    .focusEffectDisabled()
    .onKeyPress(.downArrow) { move(1) }
    .onKeyPress(.upArrow) { move(-1) }
    .accessibilityElement(children: .contain)
    .accessibilityLabel("Sections")
  }

  private func move(_ step: Int) -> KeyPress.Result {
    let all = AppModel.Section.allCases
    guard let index = all.firstIndex(of: model.section) else { return .ignored }
    let next = index + step
    guard all.indices.contains(next) else { return .handled }
    model.section = all[next]
    return .handled
  }
}

/// Sizes that follow the person’s sidebar icon size setting.
private struct SidebarMetrics {
  var font: Font
  var icon: CGFloat
  var height: CGFloat

  /// From System Settings › Appearance › Sidebar icon size, which AppKit’s own
  /// sidebars read from the same place.
  static var current: SidebarMetrics {
    switch UserDefaults.standard.integer(forKey: "NSTableViewDefaultSizeMode") {
    case 1: SidebarMetrics(font: .system(size: 11), icon: 14, height: 24)
    case 3: SidebarMetrics(font: .system(size: 15), icon: 22, height: 38)
    default: SidebarMetrics(font: .system(size: 13), icon: 16, height: 30)
    }
  }
}

private struct SidebarRow: View {
  @Environment(AppModel.self) private var model
  @Environment(\.accentMark) private var accentMark
  @Environment(\.controlActiveState) private var activeState
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  var section: AppModel.Section
  var metrics: SidebarMetrics
  var focused: Bool
  @State private var hovering = false

  var body: some View {
    let selected = model.section == section
    // Inactive windows show a quiet selection, as the system’s own sidebars do.
    let key = activeState == .key
    Button {
      model.section = section
    } label: {
      HStack(spacing: Metrics.s) {
        Image(systemName: section.symbol)
          .font(.system(size: metrics.icon * 0.82))
          .foregroundStyle(selected && key ? AnyShapeStyle(.white) : AnyShapeStyle(accentMark))
          .frame(width: metrics.icon + 4)
        Text(section.title)
          .font(metrics.font)
          .foregroundStyle(selected && key ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
        Spacer(minLength: 0)
      }
      .padding(.horizontal, Metrics.s)
      .frame(height: metrics.height)
      .background {
        RoundedRectangle(cornerRadius: 8)
          .fill(fill(selected: selected, key: key))
      }
      .contentShape(.rect(cornerRadius: 8))
    }
    .buttonStyle(.plain)
    .onHover { hovering = $0 }
    .animation(reduceMotion ? nil : .snappy(duration: 0.12), value: hovering)
    .accessibilityIdentifier("sidebar.\(section.rawValue)")
    .accessibilityAddTraits(selected ? .isSelected : [])
  }

  private func fill(selected: Bool, key: Bool) -> AnyShapeStyle {
    if selected { return key ? AnyShapeStyle(.tint) : AnyShapeStyle(.fill.tertiary) }
    return hovering ? AnyShapeStyle(.fill.quaternary) : AnyShapeStyle(.clear)
  }
}
