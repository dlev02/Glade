import SwiftUI

/// A model name typed in or picked from the provider's suggestions. Empty means the
/// provider's default. Saved when editing ends rather than on every keystroke.
struct ModelField: View {
  var title: String
  var suggestions: [String]
  @Binding var value: String
  @State private var text = ""
  @FocusState private var focused: Bool

  var body: some View {
    HStack(spacing: 2) {
      TextField(title, text: $text, prompt: Text("Default"))
        .labelsHidden()
        .textFieldStyle(.roundedBorder)
        .multilineTextAlignment(.leading)
        .frame(width: 150)
        .focused($focused)
        .onSubmit(commit)
      Menu {
        Button("Default") { set("") }
        Divider()
        ForEach(suggestions, id: \.self) { name in
          Button(name) { set(name) }
        }
      } label: {
        Image(systemName: "chevron.down")
      }
      .menuStyle(.button)
      .buttonStyle(.borderless)
      .menuIndicator(.hidden)
      .fixedSize()
      .help("Choose a model")
      .accessibilityLabel("Choose a model for \(title)")
      // Keeps every field lined up when a provider has nothing to suggest.
      .opacity(suggestions.isEmpty ? 0 : 1)
      .disabled(suggestions.isEmpty)
      .accessibilityHidden(suggestions.isEmpty)
    }
    .onAppear { text = value }
    .onChange(of: value) { _, new in if !focused { text = new } }
    .onChange(of: focused) { _, isFocused in if !isFocused { commit() } }
    .onDisappear(perform: commit)
  }

  private func set(_ name: String) {
    text = name
    commit()
  }

  private func commit() {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmed != value { value = trimmed }
  }
}
