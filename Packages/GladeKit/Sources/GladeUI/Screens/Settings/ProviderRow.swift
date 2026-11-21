import GladeKit
import SwiftUI

/// One AI in the assistant list: its name, whether it can be used, and for one that
/// can, which model it uses day to day.
struct ProviderRow: View {
  var provider: ProviderStatus
  @Binding var model: String
  /// How hard it thinks, for an AI that takes an effort.
  var effort: Binding<Effort>?
  /// Shows the drag handle of a row that can be reordered.
  var showsHandle: Bool
  /// Leaves the handle’s room empty, so rows without one share the text edge of rows
  /// that have one.
  var reservesHandle = false
  /// Called after Terminal opens to sign in, so the list can look again on return.
  var signingIn: () -> Void = {}

  var body: some View {
    HStack(spacing: Metrics.m) {
      if showsHandle || reservesHandle {
        Image(systemName: "line.3.horizontal")
          .foregroundStyle(.tertiary)
          .opacity(showsHandle ? 1 : 0)
          .help(showsHandle ? "Drag to change the order" : "")
          .accessibilityHidden(true)
      }
      VStack(alignment: .leading, spacing: 2) {
        Text(provider.name)
          .help(provider.verified ? "" : "This connection follows the tool’s documentation but hasn’t been tried for real yet.")
        status
          .font(.callout)
          .lineLimit(2)
      }
      Spacer(minLength: Metrics.m)
      if provider.isReady {
        HStack(spacing: Metrics.l) {
          if provider.takesModel {
            ModelField(title: provider.name, suggestions: provider.models, value: $model)
          }
          if provider.supportsEffort, let effort {
            EffortField(title: provider.name, value: effort)
          }
        }
      } else if let command = provider.signInCommand {
        signInButtons(command)
      }
    }
    .padding(.vertical, 2)
  }

  /// Opens Terminal running the sign-in command, or copies it to run by hand.
  private func signInButtons(_ command: String) -> some View {
    HStack(spacing: Metrics.s) {
      CopyButton(title: "Copy Command") { command }
        .labelStyle(.iconOnly)
        .buttonStyle(.borderless)
        .foregroundStyle(.secondary)
        .help("Copy “\(command)”")
      Button("Sign In…") {
        if SignInTerminal.open(provider) { signingIn() }
      }
      .help("Open Terminal and run “\(command)”")
    }
  }

  @ViewBuilder private var status: some View {
    switch provider.state {
    case .ready:
      Label(provider.isLocal ? "Ready · On this Mac" : "Ready", systemImage: "checkmark.circle.fill")
        .labelStyle(StatusLabelStyle(color: .green))
    case .needsSignIn(let hint):
      Label(Self.plain(hint), systemImage: "exclamationmark.circle.fill")
        .labelStyle(StatusLabelStyle(color: .orange))
    case .notInstalled:
      Label("Not installed", systemImage: "circle.dashed")
        .labelStyle(StatusLabelStyle(color: .secondary))
    case .unavailable(let reason):
      Label(Self.plain(reason), systemImage: "xmark.circle")
        .labelStyle(StatusLabelStyle(color: .secondary))
    }
  }

  /// Hints are written as sentences with Markdown-style backticks; a status is a
  /// label, so it shows as plain text with no full stop, like "Ready".
  private static func plain(_ hint: String) -> String {
    var text = hint.replacingOccurrences(of: "`", with: "")
    while text.hasSuffix(".") { text.removeLast() }
    return text
  }
}

/// A status line: a small coloured symbol and secondary text.
private struct StatusLabelStyle: LabelStyle {
  var color: Color

  func makeBody(configuration: Configuration) -> some View {
    HStack(alignment: .firstTextBaseline, spacing: 4) {
      configuration.icon
        .foregroundStyle(color)
        .imageScale(.small)
      configuration.title
        .foregroundStyle(.secondary)
    }
  }
}
