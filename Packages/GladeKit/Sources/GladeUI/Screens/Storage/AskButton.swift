import GladeKit
import SwiftUI

/// The storage toolbar's "Ask Claude": has the person's own AI refine the selection.
/// Shows its title as well as its symbol, because an AI action needs a word. While
/// the AI works it's a spinner with what it's doing.
struct AskButton: View {
  @Environment(AppModel.self) private var model

  var body: some View {
    if case .thinking(let activity) = model.assistantState {
      Label {
        Text("Asking…")
      } icon: {
        ProgressView()
          .controlSize(.small)
      }
      .labelStyle(.titleAndIcon)
      .help(activity)
      .accessibilityLabel(activity)
      .accessibilityIdentifier("toolbar.ask")
    } else {
      let provider = model.activeProvider
      Button("Ask \(provider.map(Self.shortName) ?? "Assistant")", systemImage: Symbols.assistant) {
        Task { await model.adviseStorage() }
      }
      .labelStyle(.titleAndIcon)
      .disabled(provider == nil || model.scan == nil || model.isScanning || model.isCleaning)
      .help(provider == nil ? "Set up an assistant in Settings to ask for advice" : "Ask \(provider?.name ?? "") to refine the selection")
      .accessibilityIdentifier("toolbar.ask")
    }
  }

  /// "Claude Code" reads as "Claude" on a button; other names stay as they are.
  static func shortName(_ provider: ProviderStatus) -> String {
    provider.name.hasSuffix(" Code") ? String(provider.name.dropLast(5)) : provider.name
  }
}
