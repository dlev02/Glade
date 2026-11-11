import SwiftUI

/// One thing to choose in a `ChoicePopover`.
public struct Choice<Value: Hashable>: Identifiable {
  public var value: Value
  public var title: String
  /// A line under the title saying what the choice means.
  public var subtitle: String?
  public var symbol: String?

  public var id: Value { value }

  public init(_ value: Value, _ title: String, subtitle: String? = nil, symbol: String? = nil) {
    self.value = value
    self.title = title
    self.subtitle = subtitle
    self.symbol = symbol
  }
}

/// A group of choices, with an optional small heading.
public struct ChoiceSection<Value: Hashable>: Identifiable {
  public var title: String?
  public var symbol: String?
  public var choices: [Choice<Value>]

  public var id: String { title ?? choices.map(\.title).joined() }

  public init(_ title: String? = nil, symbol: String? = nil, choices: [Choice<Value>]) {
    self.title = title
    self.symbol = symbol
    self.choices = choices
  }
}

/// An action under the choices, such as "Reset Selection" or "Assistant Settings…".
public struct ChoiceFooter {
  public var title: String
  public var symbol: String?
  public var action: () -> Void

  public init(_ title: String, symbol: String? = nil, action: @escaping () -> Void) {
    self.title = title
    self.symbol = symbol
    self.action = action
  }
}

/// A quiet "Balanced ⌄" control that opens a glass popover, arrow on the control,
/// listing a few choices: each with an optional symbol, a title, a line saying what
/// it means, and a tick on the current one. Works from the keyboard (Up, Down,
/// Return, Esc) and reads to VoiceOver as a control with a value.
public struct ChoicePopover<Value: Hashable>: View {
  @Environment(\.isEnabled) private var isEnabled
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  var label: String
  var value: String
  @Binding var selection: Value
  var sections: [ChoiceSection<Value>]
  var footer: ChoiceFooter?
  var arrowEdge: Edge
  @State private var isPresented = false
  @State private var hovering = false

  /// - Parameters:
  ///   - label: What's being chosen, for VoiceOver ("Clean level").
  ///   - value: The current choice as the control shows it.
  public init(
    _ label: String, value: String, selection: Binding<Value>, sections: [ChoiceSection<Value>],
    footer: ChoiceFooter? = nil, arrowEdge: Edge = .top
  ) {
    self.label = label
    self.value = value
    _selection = selection
    self.sections = sections
    self.footer = footer
    self.arrowEdge = arrowEdge
  }

  public var body: some View {
    Button {
      isPresented.toggle()
    } label: {
      HStack(spacing: 3) {
        Text(value)
        Image(systemName: "chevron.down")
          .font(.caption2.weight(.semibold))
          .imageScale(.small)
          .accessibilityHidden(true)
      }
      .padding(.horizontal, 6)
      .padding(.vertical, 2)
      .background(Color.primary.opacity(hovering || isPresented ? 0.08 : 0), in: .capsule)
      .contentShape(.capsule)
    }
    .buttonStyle(.plain)
    .foregroundStyle(.secondary)
    .opacity(isEnabled ? 1 : 0.5)
    .onHover { inside in
      withAnimation(reduceMotion ? nil : .snappy(duration: 0.12)) { hovering = inside }
    }
    .fixedSize()
    .accessibilityLabel(label)
    .accessibilityValue(value)
    .accessibilityHint("Shows the choices")
    .popover(isPresented: $isPresented, arrowEdge: arrowEdge) {
      ChoiceList(sections: sections, selection: selection, footer: footer) { chosen in
        selection = chosen
        isPresented = false
      } dismiss: {
        isPresented = false
      }
    }
  }
}

/// The popover's contents. Keeps a highlighted row for the keyboard, starting on the
/// current choice.
private struct ChoiceList<Value: Hashable>: View {
  var sections: [ChoiceSection<Value>]
  var selection: Value
  var footer: ChoiceFooter?
  var choose: (Value) -> Void
  var dismiss: () -> Void
  @State private var highlighted: Int?
  @FocusState private var isFocused: Bool

  /// Every row in order, the footer last, for moving with the arrow keys.
  private var rowCount: Int { sections.reduce(0) { $0 + $1.choices.count } + (footer == nil ? 0 : 1) }

  var body: some View {
    VStack(alignment: .leading, spacing: 2) {
      ForEach(Array(sections.enumerated()), id: \.element.id) { sectionIndex, section in
        if sectionIndex > 0 {
          Divider().padding(.vertical, 4).padding(.horizontal, 6)
        }
        if let title = section.title {
          Label {
            Text(title)
          } icon: {
            if let symbol = section.symbol { Image(systemName: symbol) }
          }
          .font(.caption.weight(.semibold))
          .foregroundStyle(.secondary)
          .padding(.horizontal, 10)
          .padding(.top, 4)
          .padding(.bottom, 2)
          .accessibilityAddTraits(.isHeader)
        }
        ForEach(Array(section.choices.enumerated()), id: \.element.id) { offset, choice in
          let index = flatIndex(section: sectionIndex, offset: offset)
          ChoiceRow(
            title: choice.title, subtitle: choice.subtitle, symbol: choice.symbol,
            isSelected: choice.value == selection, isHighlighted: highlighted == index
          ) {
            choose(choice.value)
          } hover: { inside in
            if inside { highlighted = index } else if highlighted == index { highlighted = nil }
          }
        }
      }
      if let footer {
        Divider().padding(.vertical, 4).padding(.horizontal, 6)
        ChoiceRow(
          title: footer.title, subtitle: nil, symbol: footer.symbol, isSelected: false,
          isHighlighted: highlighted == rowCount - 1
        ) {
          dismiss()
          footer.action()
        } hover: { inside in
          if inside { highlighted = rowCount - 1 } else if highlighted == rowCount - 1 { highlighted = nil }
        }
      }
    }
    .padding(6)
    .frame(minWidth: 220, alignment: .leading)
    .fixedSize()
    .focusable()
    .focusEffectDisabled()
    .focused($isFocused)
    .onAppear {
      // The tick marks the current choice; the fill is only the pointer's or the
      // keyboard's place, so nothing is filled until one of them moves.
      isFocused = true
    }
    .onKeyPress(.downArrow) { move(1) }
    .onKeyPress(.upArrow) { move(-1) }
    .onKeyPress(.return) { activate() }
    .onKeyPress(.space) { activate() }
  }

  private var currentIndex: Int? {
    var index = 0
    for section in sections {
      for choice in section.choices {
        if choice.value == selection { return index }
        index += 1
      }
    }
    return nil
  }

  private func flatIndex(section: Int, offset: Int) -> Int {
    sections.prefix(section).reduce(0) { $0 + $1.choices.count } + offset
  }

  private func move(_ step: Int) -> KeyPress.Result {
    guard rowCount > 0 else { return .ignored }
    let start = highlighted ?? currentIndex.map { $0 - step } ?? (step > 0 ? -1 : rowCount)
    highlighted = min(max(start + step, 0), rowCount - 1)
    return .handled
  }

  private func activate() -> KeyPress.Result {
    guard let highlighted else { return .ignored }
    if footer != nil, highlighted == rowCount - 1 {
      dismiss()
      footer?.action()
      return .handled
    }
    var index = 0
    for section in sections {
      for choice in section.choices {
        if index == highlighted {
          choose(choice.value)
          return .handled
        }
        index += 1
      }
    }
    return .ignored
  }
}

/// One roomy row: symbol, title and the line under it, and a tick when it's chosen.
private struct ChoiceRow: View {
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  var title: String
  var subtitle: String?
  var symbol: String?
  var isSelected: Bool
  var isHighlighted: Bool
  var action: () -> Void
  var hover: (Bool) -> Void

  var body: some View {
    Button(action: action) {
      HStack(alignment: subtitle == nil ? .center : .firstTextBaseline, spacing: Metrics.s) {
        if let symbol {
          Image(systemName: symbol)
            .foregroundStyle(.secondary)
            .frame(width: 18)
            .accessibilityHidden(true)
        }
        VStack(alignment: .leading, spacing: 1) {
          Text(title)
            .foregroundStyle(.primary)
          if let subtitle {
            Text(subtitle)
              .font(.callout)
              .foregroundStyle(.secondary)
          }
        }
        Spacer(minLength: Metrics.l)
        Image(systemName: "checkmark")
          .font(.callout.weight(.semibold))
          .foregroundStyle(.primary)
          .opacity(isSelected ? 1 : 0)
          .accessibilityHidden(true)
      }
      .padding(.horizontal, 10)
      .padding(.vertical, 7)
      .background(Color.primary.opacity(isHighlighted ? 0.08 : 0), in: .rect(cornerRadius: 8))
      .contentShape(.rect(cornerRadius: 8))
      .animation(reduceMotion ? nil : .snappy(duration: 0.1), value: isHighlighted)
    }
    .buttonStyle(.plain)
    .onHover(perform: hover)
    .accessibilityLabel(title)
    .accessibilityHint(subtitle ?? "")
    .accessibilityAddTraits(isSelected ? .isSelected : [])
  }
}
