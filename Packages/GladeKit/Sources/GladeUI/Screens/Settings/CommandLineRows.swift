import GladeKit
import SwiftUI

/// The `glade` command in Terminal: whether it's installed, where, and a button that
/// installs or removes it.
struct CommandLineRows: View {
  @Environment(\.screenOverrides) private var overrides
  @State private var status: CommandLineTool.Status?
  @State private var working = false
  @State private var problem: String?

  var body: some View {
    LabeledContent {
      if working || status == nil {
        ProgressView().controlSize(.small)
      } else {
        action
      }
    } label: {
      Text("Command line tool")
      Text(summary)
        .lineLimit(2)
        .truncationMode(.middle)
    }
    .task { await load() }
    if let problem {
      Text(problem)
        .font(.callout)
        .foregroundStyle(.secondary)
    }
  }

  @ViewBuilder private var action: some View {
    switch status {
    case .installed, .otherCopy:
      HStack {
        if case .otherCopy = status {
          Button("Update") { run { try await CommandLineTool.install() } }
            .secondaryAction()
        }
        Button("Remove") { run { try await CommandLineTool.remove() } }
          .secondaryAction()
      }
    case .notInstalled:
      Button("Install") { run { try await CommandLineTool.install() } }
        .secondaryAction()
    case .unavailable, .occupied, nil:
      EmptyView()
    }
  }

  private var summary: String {
    switch status {
    case nil: "Checking…"
    case .unavailable: "Available after installing the app."
    case .notInstalled: "Not installed"
    case .installed(let path, let onPath):
      onPath ? Redactor.tilde(path) : "\(Redactor.tilde(path)) · add \(Redactor.tilde((path as NSString).deletingLastPathComponent)) to your PATH to use it"
    case .otherCopy(let path, _): "\(Redactor.tilde(path)) opens another copy of \(Brand.name)."
    case .occupied(let path): "Something else named \(Brand.cli) is at \(Redactor.tilde(path))."
    }
  }

  private func load() async {
    if let fixed = overrides.commandLine {
      status = fixed
      return
    }
    status = await CommandLineTool.status()
  }

  private func run(_ change: @escaping () async throws -> Void) {
    working = true
    problem = nil
    Task {
      do {
        try await change()
      } catch {
        problem = error.localizedDescription
      }
      status = await CommandLineTool.status()
      working = false
    }
  }
}
