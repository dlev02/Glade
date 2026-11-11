import GladeKit
import SwiftUI

/// The storage toolbar's "Ask Claude": has the person's own AI refine the selection.
/// Shows its title as well as its symbol, because an AI action needs a word. While
/// the AI works the button keeps its exact footprint and label, and only its sparkle
/// pulses, so nothing in the toolbar moves.
struct AskButton: View {
  @Environment(AppModel.self) private var model
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    let provider = model.activeProvider
    let asking: String? = if case .thinking(let activity) = model.assistantState { activity } else { nil }
    Button("Ask \(provider.map(Self.shortName) ?? "Assistant")", systemImage: Symbols.assistant) {
      guard asking == nil else { return }
      Task { await model.adviseStorage() }
    }
    .labelStyle(.titleAndIcon)
    .symbolEffect(.pulse, options: .repeat(.continuous), isActive: asking != nil && !reduceMotion)
    // Not `.disabled` while asking: a dimmed label would read as unavailable rather
    // than busy. A second click does nothing.
    .disabled(asking == nil && (provider == nil || model.scan == nil || model.isScanning || model.isCleaning))
    .help(asking ?? (provider == nil ? "Set up an assistant in Settings to ask for advice" : "Ask \(provider?.name ?? "") to refine the selection"))
    .accessibilityValue(asking ?? "")
    .accessibilityIdentifier("toolbar.ask")
  }

  /// "Claude Code" reads as "Claude" on a button. A long name ("Apple Intelligence")
  /// would crowd search and the inspector button out of the toolbar, so it becomes
  /// "AI"; the tooltip still names it.
  static func shortName(_ provider: ProviderStatus) -> String {
    let name = provider.name.hasSuffix(" Code") ? String(provider.name.dropLast(5)) : provider.name
    return name.count > 8 ? "AI" : name
  }
}
