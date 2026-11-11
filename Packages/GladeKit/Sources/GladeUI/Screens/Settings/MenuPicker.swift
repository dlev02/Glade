import SwiftUI

/// A choice shown as its current value with a small chevron, "20 GB ⌄", opening a
/// menu of the options: the same quiet control as the clean level menu.
struct MenuPicker<Value: Hashable>: View {
  /// What the choice is, for VoiceOver.
  var title: String
  @Binding var selection: Value
  var options: [Value]
  var label: (Value) -> String

  /// Keeps the current value in the menu even when it isn’t one of the usual
  /// options, so a value set elsewhere still shows as chosen.
  init(_ title: String, selection: Binding<Value>, options: [Value], label: @escaping (Value) -> String) {
    self.title = title
    _selection = selection
    self.options = options.contains(selection.wrappedValue) ? options : options + [selection.wrappedValue]
    self.label = label
  }

  var body: some View {
    Menu {
      Picker(title, selection: $selection) {
        ForEach(options, id: \.self) { option in
          Text(label(option)).tag(option)
        }
      }
      .pickerStyle(.inline)
      .labelsHidden()
    } label: {
      Text(label(selection))
        .monospacedDigit()
    }
    .menuStyle(.borderlessButton)
    .menuIndicator(.visible)
    // The accent fill is dark enough for white text, too dark for text on a dark
    // form; a value reads as plain secondary text, as in System Settings.
    .tint(.secondary)
    .fixedSize()
    .accessibilityLabel(title)
    .accessibilityValue(label(selection))
  }
}

extension MenuPicker where Value == Double {
  /// Options in numeric order, with the current value slotted in where it belongs.
  init(_ title: String, value: Binding<Double>, options: [Double], label: @escaping (Double) -> String) {
    let all = Set(options + [value.wrappedValue]).sorted()
    self.init(title, selection: value, options: all, label: label)
  }
}
