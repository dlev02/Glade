import GladeKit
import SwiftUI

/// One thing worth doing for memory, processor or graphics, the same on Overview,
/// Performance and in the menu bar: what it is, the numbers in a few words, any doubt
/// worth seeing, and the action. The full sentence is in the tooltip.
public struct SuggestionRow: View {
  @Environment(AppModel.self) private var model
  @Environment(\.accentMark) private var accentMark
  var suggestion: PerformanceSuggestion
  var iconSize: CGFloat
  /// The row sits on glass (the menu bar popover), so its button can’t be glass too.
  var onGlass: Bool
  /// Shows the sentence describing what happened.
  var report: (String) -> Void
  @State private var working = false

  public init(
    _ suggestion: PerformanceSuggestion, iconSize: CGFloat = 28, onGlass: Bool = false,
    report: @escaping (String) -> Void
  ) {
    self.suggestion = suggestion
    self.iconSize = iconSize
    self.onGlass = onGlass
    self.report = report
  }

  public var body: some View {
    HStack(spacing: Metrics.m) {
      icon
      VStack(alignment: .leading, spacing: 1) {
        Text(suggestion.appName)
          .lineLimit(1)
        Text(suggestion.facts ?? suggestion.reason)
          .font(.callout)
          .foregroundStyle(.secondary)
          .monospacedDigit()
          .lineLimit(1)
        if let caveat = suggestion.caveat {
          Label {
            Text(caveat)
          } icon: {
            Image(systemName: "exclamationmark.circle.fill")
              .foregroundStyle(Palette.warning)
          }
          .labelStyle(.titleAndIcon)
          .font(.caption)
          .foregroundStyle(.secondary)
          .lineLimit(1)
        }
      }
      .accessibilityElement(children: .combine)
      Spacer(minLength: Metrics.s)
      if let title = model.actionTitle(for: suggestion) {
        action(title)
      }
    }
    .contentShape(.rect)
    .help(suggestion.reason)
  }

  @ViewBuilder private var icon: some View {
    if let symbol = model.symbol(for: suggestion) {
      let color = model.isWarning(suggestion) ? Palette.warning : accentMark
      Image(systemName: symbol)
        .font(.system(size: iconSize * 0.5, weight: .medium))
        .foregroundStyle(color)
        .frame(width: iconSize, height: iconSize)
        .background(color.opacity(0.14), in: .rect(cornerRadius: iconSize * 0.24))
        .accessibilityHidden(true)
    } else {
      AppIconView(path: model.apps.first { $0.id == suggestion.appID }?.bundlePath, size: iconSize)
    }
  }

  @ViewBuilder private func action(_ title: String) -> some View {
    let button = Button(title) {
      working = true
      Task {
        report(await model.perform(suggestion))
        working = false
      }
    }
    .controlSize(.small)
    .disabled(working)
    .accessibilityLabel("\(title) \(suggestion.appName)")
    if onGlass {
      button.buttonStyle(QuietCapsuleStyle())
    } else {
      button.secondaryAction()
    }
  }
}

/// A small capsule on a plain fill, for a secondary button that already sits on glass.
private struct QuietCapsuleStyle: ButtonStyle {
  @Environment(\.isEnabled) private var isEnabled
  @State private var hovering = false

  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .font(.callout.weight(.medium))
      .padding(.horizontal, 10)
      .padding(.vertical, 3)
      .background(.fill.opacity(configuration.isPressed ? 1 : hovering ? 0.8 : 0.55), in: .capsule)
      .opacity(isEnabled ? 1 : 0.45)
      .contentShape(.capsule)
      .onHover { hovering = $0 }
      .animation(.snappy(duration: 0.12), value: hovering)
      .animation(.snappy(duration: 0.12), value: configuration.isPressed)
  }
}

extension View {
  /// How a handled suggestion leaves its list: it folds away, or just fades with
  /// Reduce Motion on.
  func suggestionTransition(reduceMotion: Bool) -> some View {
    transition(reduceMotion ? AnyTransition.opacity : AnyTransition.opacity.combined(with: .scale(scale: 0.98, anchor: .top)))
  }
}
