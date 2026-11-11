import GladeKit
import SwiftUI

/// One AI in the assistant list: its name, whether it can be used, and for one that
/// can, which model it uses day to day.
struct ProviderRow: View {
  var provider: ProviderStatus
  @Binding var model: String
  /// Shows the drag handle of a row that can be reordered.
  var showsHandle: Bool
  /// Leaves the handle’s room empty, so rows without one share the text edge of rows
  /// that have one.
  var reservesHandle = false

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
      if provider.isReady, provider.takesModel {
        ModelField(title: provider.name, suggestions: provider.models, value: $model)
      }
    }
    .padding(.vertical, 2)
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
