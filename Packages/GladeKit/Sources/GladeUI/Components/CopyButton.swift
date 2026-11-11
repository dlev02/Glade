import AppKit
import SwiftUI

/// Copies text and shows that it worked: the symbol turns into a tick for a moment
/// and VoiceOver hears "Copied". Styled by whoever places it.
struct CopyButton: View {
  var title = "Copy"
  /// What to copy, read at the moment of the click.
  var text: () -> String
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var copied = false
  @State private var reset: Task<Void, Never>?

  var body: some View {
    Button {
      Copying.copy(text())
      copied = true
      reset?.cancel()
      reset = Task {
        try? await Task.sleep(for: .seconds(1.5))
        if !Task.isCancelled { copied = false }
      }
    } label: {
      Label(copied ? "Copied" : title, systemImage: copied ? "checkmark" : "document.on.document")
        .contentTransition(reduceMotion ? .identity : .symbolEffect(.replace))
    }
  }
}

/// Puts text on the pasteboard and tells VoiceOver, for copy commands in menus too.
enum Copying {
  static func copy(_ text: String) {
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(text, forType: .string)
    AccessibilityNotification.Announcement("Copied").post()
  }
}
