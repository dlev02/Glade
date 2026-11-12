import GladeKit
import SwiftUI

/// Says exactly what Free Up Memory will quit and shut down before it starts. Every
/// action has a tick; the plan’s own ticks are only the confident ones, and anything
/// with a doubt says so and starts unticked. The title and button follow the ticks.
/// Arrow keys move the highlight, Space ticks or unticks it, Return starts, Esc cancels.
struct ReliefConfirmation: View {
  @Environment(AppModel.self) private var model
  @Environment(\.accentMark) private var accentMark
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  var session: ReliefSession
  var cancel: () -> Void
  var confirm: () -> Void
  @State private var highlighted: String?
  @FocusState private var listFocused: Bool
  /// The highlight shows once the keyboard is used, so a pointer user never sees a
  /// second kind of mark beside the ticks.
  @State private var usingKeyboard = false
  @State private var listHeight: CGFloat = 0

  /// The list’s inner leading inset, shared with the line above it.
  private static let inset = Metrics.m
  private static let iconSize: CGFloat = 24
  /// About six rows, then the list scrolls.
  private static let maxListHeight: CGFloat = 330

  var body: some View {
    let plan = session.plan
    let chosen = session.chosenActions
    VStack(alignment: .leading, spacing: Metrics.l) {
      VStack(alignment: .leading, spacing: Metrics.xs) {
        Text(Self.title(chosen))
          .font(.title2.weight(.semibold))
          .fixedSize(horizontal: false, vertical: true)
        Text(expected(chosen, plan: plan))
          .foregroundStyle(.secondary)
          .monospacedDigit()
          .contentTransition(.numericText())
          .animation(reduceMotion ? nil : .snappy(duration: 0.2), value: chosen.count)
      }

      VStack(alignment: .leading, spacing: Metrics.s) {
        list(plan.actions)
        if let left = plan.leftAloneSummary {
          Text(left)
            .font(.callout)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, Self.inset)
            .accessibilityIdentifier("relief.leftAlone")
        }
      }

      HStack(spacing: Metrics.s) {
        Spacer()
        Button("Cancel", action: cancel)
          .secondaryAction()
          .controlSize(.large)
          .keyboardShortcut(.cancelAction)
          .accessibilityIdentifier("relief.cancel")
        Button(Self.buttonTitle(chosen), action: confirm)
          .principalAction()
          .controlSize(.large)
          .keyboardShortcut(.defaultAction)
          .disabled(chosen.isEmpty)
          .accessibilityIdentifier("relief.confirm")
      }
    }
    .padding(Metrics.xl)
    .onAppear {
      highlighted = plan.actions.first?.id
      listFocused = true
    }
  }

  // MARK: Words

  /// "Quit 3 apps and shut down 2 simulators?", "Quit Mail?", or a plain question when
  /// nothing is ticked.
  static func title(_ chosen: [ReliefPlan.Action]) -> String {
    if chosen.count == 1, let only = chosen.first {
      return "\(verb(only.kind, capitalised: true)) \(only.name)?"
    }
    let parts = counts(chosen).map { kind, count in
      "\(verb(kind, capitalised: false)) \(count) \(noun(kind, count))"
    }
    guard !parts.isEmpty else { return "Free up memory?" }
    let sentence = Format.listed(parts)
    return sentence.prefix(1).uppercased() + sentence.dropFirst() + "?"
  }

  /// "Quit 3 and Shut Down 2", "Quit 3 Apps", "Shut Down 1 Simulator".
  static func buttonTitle(_ chosen: [ReliefPlan.Action]) -> String {
    let counts = counts(chosen)
    if counts.count == 1, let (kind, count) = counts.first {
      return "\(verb(kind, capitalised: true, title: true)) \(count) \(noun(kind, count).capitalized)"
    }
    guard !counts.isEmpty else { return "Free Up Memory" }
    return Format.listed(counts.map { "\(verb($0.0, capitalised: true, title: true)) \($0.1)" })
  }

  private static func counts(_ chosen: [ReliefPlan.Action]) -> [(ReliefPlan.Action.Kind, Int)] {
    [ReliefPlan.Action.Kind.quit, .relaunch, .shutDown].compactMap { kind in
      let count = chosen.filter { $0.kind == kind }.count
      return count > 0 ? (kind, count) : nil
    }
  }

  private static func verb(_ kind: ReliefPlan.Action.Kind, capitalised: Bool, title: Bool = false) -> String {
    switch kind {
    case .quit: capitalised ? "Quit" : "quit"
    case .relaunch: capitalised ? "Relaunch" : "relaunch"
    case .shutDown: title ? "Shut Down" : capitalised ? "Shut down" : "shut down"
    }
  }

  private static func noun(_ kind: ReliefPlan.Action.Kind, _ count: Int) -> String {
    kind == .shutDown ? (count == 1 ? "simulator" : "simulators") : (count == 1 ? "app" : "apps")
  }

  /// "About 7.38 GB of memory", with the graphics share when that’s much of the point.
  private func expected(_ chosen: [ReliefPlan.Action], plan: ReliefPlan) -> String {
    guard !chosen.isEmpty else { return "Nothing ticked" }
    let bytes = plan.memoryBytes(of: session.chosen)
    let gpu = chosen.compactMap(\.gpuPercent).reduce(0, +)
    let memory = "About \(Format.bytes(bytes)) of memory"
    return gpu >= 10 ? "\(memory) · \(Int(gpu.rounded()))% GPU" : memory
  }

  // MARK: The list

  private func list(_ actions: [ReliefPlan.Action]) -> some View {
    ScrollViewReader { proxy in
      ScrollView {
        VStack(spacing: 0) {
          ForEach(Array(actions.enumerated()), id: \.element.id) { index, action in
            row(action)
              .id(action.id)
              .overlay(alignment: .top) {
                if index > 0 {
                  Divider().padding(.leading, Self.inset + 18 + Metrics.s + Self.iconSize + Metrics.s)
                }
              }
          }
        }
        .padding(.vertical, Metrics.xs)
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { listHeight = $0 }
      }
      .scrollIndicators(listHeight > Self.maxListHeight ? .visible : .hidden)
      .frame(height: min(max(listHeight, 1), Self.maxListHeight))
      .background(Palette.card, in: .rect(cornerRadius: Metrics.innerRadius))
      .overlay {
        RoundedRectangle(cornerRadius: Metrics.innerRadius)
          .strokeBorder(Palette.hairline.opacity(0.6), lineWidth: Metrics.hairline)
      }
      .focusable()
      .focused($listFocused)
      .focusEffectDisabled()
      .onKeyPress(.space) {
        guard let id = highlighted, let action = actions.first(where: { $0.id == id }) else { return .ignored }
        usingKeyboard = true
        model.setChosen(action, !model.isChosen(action))
        return .handled
      }
      .onKeyPress(.downArrow) { move(1, in: actions, proxy: proxy) }
      .onKeyPress(.upArrow) { move(-1, in: actions, proxy: proxy) }
    }
  }

  private func move(_ step: Int, in actions: [ReliefPlan.Action], proxy: ScrollViewProxy) -> KeyPress.Result {
    guard !actions.isEmpty else { return .ignored }
    // The first press shows where the highlight is rather than moving it.
    guard usingKeyboard else {
      usingKeyboard = true
      return .handled
    }
    let index = actions.firstIndex { $0.id == highlighted } ?? (step > 0 ? -1 : actions.count)
    let next = actions[min(max(index + step, 0), actions.count - 1)].id
    highlighted = next
    proxy.scrollTo(next)
    return .handled
  }

  private func row(_ action: ReliefPlan.Action) -> some View {
    let isOn = model.isChosen(action)
    let binding = Binding(get: { isOn }, set: { model.setChosen(action, $0) })
    return HStack(spacing: Metrics.s) {
      Toggle(isOn: binding) { Text(action.name) }
        .toggleStyle(CheckToggleStyle())
      icon(action)
      VStack(alignment: .leading, spacing: 1) {
        Text(action.name)
          .lineLimit(1)
          .truncationMode(.middle)
        Text(action.facts)
          .font(.callout)
          .foregroundStyle(.secondary)
          .monospacedDigit()
          .lineLimit(1)
        if let caveat = action.caveat {
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
      Spacer(minLength: 0)
    }
    .padding(.horizontal, Self.inset)
    .padding(.vertical, Metrics.s)
    .background {
      // The keyboard’s place in the list, shown only while the list has focus.
      if listFocused, usingKeyboard, highlighted == action.id {
        RoundedRectangle(cornerRadius: 6)
          .fill(.fill.tertiary)
          .padding(.horizontal, Metrics.xs)
          .padding(.vertical, 2)
      }
    }
    .contentShape(.rect)
    .onTapGesture {
      highlighted = action.id
      model.setChosen(action, !isOn)
    }
    .help(action.why)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel([action.name, action.facts, action.caveat].compactMap { $0 }.joined(separator: ", "))
    .accessibilityValue(isOn ? "On" : "Off")
    .accessibilityHint(action.why)
    .accessibilityAddTraits(.isToggle)
    .accessibilityAction { model.setChosen(action, !isOn) }
    .accessibilityIdentifier("relief.row.\(action.name)")
  }

  @ViewBuilder private func icon(_ action: ReliefPlan.Action) -> some View {
    if action.kind == .shutDown {
      Image(systemName: "iphone")
        .font(.system(size: Self.iconSize * 0.5, weight: .medium))
        .foregroundStyle(accentMark)
        .frame(width: Self.iconSize, height: Self.iconSize)
        .background(accentMark.opacity(0.14), in: .rect(cornerRadius: Self.iconSize * 0.24))
        .accessibilityHidden(true)
    } else {
      AppIconView(path: action.bundlePath ?? AppIcons.path(forAppID: action.appID), size: Self.iconSize)
    }
  }
}
