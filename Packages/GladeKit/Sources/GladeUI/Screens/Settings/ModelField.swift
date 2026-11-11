import SwiftUI

/// A model chosen from a quiet menu of the provider's suggestions, or typed in after
/// "Other…". Empty means the provider's default. A typed name is saved when editing
/// ends, and Escape puts the menu back without changing anything.
struct ModelField: View {
  var title: String
  var suggestions: [String]
  @Binding var value: String
  @State private var isTyping = false
  @State private var text = ""
  @FocusState private var focused: Bool

  var body: some View {
    if isTyping {
      TextField(title, text: $text, prompt: Text("Model name"))
        .labelsHidden()
        .textFieldStyle(.roundedBorder)
        .frame(width: 160)
        .focused($focused)
        .onSubmit(commit)
        .onExitCommand { isTyping = false }
        .onAppear {
          text = value
          focused = true
        }
        .onChange(of: focused) { _, isFocused in if !isFocused { commit() } }
        .accessibilityLabel("Model for \(title)")
    } else {
      Menu {
        Picker(title, selection: $value) {
          Text("Default").tag("")
          if !choices.isEmpty { Divider() }
          ForEach(choices, id: \.self) { name in
            Text(name).tag(name)
          }
        }
        .pickerStyle(.inline)
        .labelsHidden()
        Divider()
        Button("Other…") { isTyping = true }
      } label: {
        Text(value.isEmpty ? "Default" : value)
      }
      .menuStyle(.borderlessButton)
      .menuIndicator(.visible)
      .fixedSize()
      .tint(.secondary)
      .accessibilityLabel("Model for \(title)")
      .accessibilityValue(value.isEmpty ? "Default" : value)
      .help("Choose a model")
    }
  }

  /// The suggestions, plus a name typed earlier so it stays ticked.
  private var choices: [String] {
    value.isEmpty || suggestions.contains(value) ? suggestions : suggestions + [value]
  }

  private func commit() {
    guard isTyping else { return }
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmed != value { value = trimmed }
    isTyping = false
  }
}
