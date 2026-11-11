import AppKit
import SwiftUI

/// The system search field as an ordinary toolbar item. `.searchable` always puts its
/// field at the very end of the toolbar; this one sits wherever it's declared, so an
/// inspector button can follow it. ⌘F focuses it and Esc clears it, as with `.searchable`.
struct ToolbarSearchField: NSViewRepresentable {
  @Binding var text: String
  var prompt: String
  /// Bump to put the cursor in the field.
  var focusRequest: Int

  func makeNSView(context: Context) -> NSSearchField {
    let field = NSSearchField()
    field.placeholderString = prompt
    field.sendsSearchStringImmediately = true
    field.sendsWholeSearchString = false
    field.delegate = context.coordinator
    field.target = context.coordinator
    field.action = #selector(Coordinator.changed(_:))
    field.setAccessibilityIdentifier("storage.search")
    field.translatesAutoresizingMaskIntoConstraints = false
    field.widthAnchor.constraint(greaterThanOrEqualToConstant: 200).isActive = true
    field.widthAnchor.constraint(lessThanOrEqualToConstant: 280).isActive = true
    return field
  }

  func updateNSView(_ field: NSSearchField, context: Context) {
    if field.stringValue != text { field.stringValue = text }
    field.placeholderString = prompt
    if context.coordinator.focusRequest != focusRequest {
      context.coordinator.focusRequest = focusRequest
      field.window?.makeFirstResponder(field)
    }
  }

  func makeCoordinator() -> Coordinator {
    Coordinator(text: $text, focusRequest: focusRequest)
  }

  final class Coordinator: NSObject, NSSearchFieldDelegate {
    var text: Binding<String>
    var focusRequest: Int

    init(text: Binding<String>, focusRequest: Int) {
      self.text = text
      self.focusRequest = focusRequest
    }

    @objc func changed(_ sender: NSSearchField) {
      if text.wrappedValue != sender.stringValue { text.wrappedValue = sender.stringValue }
    }

    func controlTextDidChange(_ note: Notification) {
      if let field = note.object as? NSSearchField { changed(field) }
    }
  }
}
