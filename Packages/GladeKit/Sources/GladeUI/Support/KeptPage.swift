import AppKit
import SwiftUI

extension EnvironmentValues {
  /// Whether this section is the one on screen. Storage and Performance stay built
  /// while another section shows, so switching back to them is instant; while hidden
  /// they leave the toolbar, title and shortcuts to the section that is showing, and
  /// stop following live readings.
  @Entry var isPageShowing = true
}

/// Keeps a section built but out of sight, hearing and reach while another one shows.
struct KeptPage: ViewModifier {
  var isShowing: Bool

  func body(content: Content) -> some View {
    content
      .environment(\.isPageShowing, isShowing)
      .opacity(isShowing ? 1 : 0)
      .allowsHitTesting(isShowing)
      .accessibilityHidden(!isShowing)
      .zIndex(isShowing ? 1 : 0)
      .onChange(of: isShowing) {
        if !isShowing { Self.releaseFocus() }
      }
  }

  /// A hidden list would otherwise keep the keyboard: Space or the arrow keys would
  /// change rows nobody can see. The sidebar keeps focus, so arrowing through
  /// sections still works.
  private static func releaseFocus() {
    guard let window = NSApp.keyWindow, let focused = window.firstResponder as? NSView else { return }
    // The sidebar is the first pane of the outermost split view; the inspector nests
    // another split view inside the detail pane.
    var inFirstPane = false
    var view: NSView? = focused
    while let current = view {
      if let split = current.superview as? NSSplitView { inFirstPane = split.arrangedSubviews.first === current }
      view = current.superview
    }
    if !inFirstPane { window.makeFirstResponder(nil) }
  }
}

extension View {
  func keptPage(showing: Bool) -> some View {
    modifier(KeptPage(isShowing: showing))
  }
}
