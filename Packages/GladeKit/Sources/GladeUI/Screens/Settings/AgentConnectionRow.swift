import AppKit
import GladeKit
import SwiftUI

/// One coding agent that can use Glade's tools: whether it's connected, a button to
/// connect or disconnect, and the exact command that does it, to copy.
struct AgentConnectionRow: View {
  var agent: AgentConnection.Agent
  @Environment(\.screenOverrides) private var overrides
  @State private var state: AgentConnection.State?
  @State private var working = false
  @State private var problem: String?

  var body: some View {
    VStack(alignment: .leading, spacing: Metrics.s) {
      LabeledContent {
        if working || state == nil {
          ProgressView().controlSize(.small)
        } else {
          action
        }
      } label: {
        Text(agent.title)
        Text(summary)
      }
      HStack(spacing: Metrics.s) {
        Text(AgentConnection.commandLine(agent))
          .font(.caption.monospaced())
          .foregroundStyle(.secondary)
          .lineLimit(1)
          .truncationMode(.middle)
          .textSelection(.enabled)
          .help(AgentConnection.commandLine(agent))
        Spacer(minLength: 0)
        CopyButton { AgentConnection.commandLine(agent) }
        .labelStyle(.iconOnly)
        .buttonStyle(.borderless)
        .help("Copy the command")
      }
      .padding(.horizontal, Metrics.s)
      .padding(.vertical, 6)
      .background(Palette.track, in: .rect(cornerRadius: Metrics.innerRadius))
      if let problem {
        Text(problem)
          .font(.callout)
          .foregroundStyle(.secondary)
          .lineLimit(3)
      }
    }
    .task { await load() }
  }

  @ViewBuilder private var action: some View {
    switch state {
    case .connected:
      Button("Disconnect") { run { try await AgentConnection.disconnect(agent) } }
        .secondaryAction()
    case .notConnected, .connectedElsewhere:
      Button(state == .notConnected ? "Connect" : "Reconnect") { run { try await AgentConnection.connect(agent) } }
        .disabled(AgentConnection.gladeExecutable == nil && overrides.agents == nil)
        .secondaryAction()
    case .notInstalled, .unavailable, nil:
      EmptyView()
    }
  }

  private var summary: String {
    switch state {
    case nil: "Checking…"
    case .notInstalled: "Not installed"
    case .connected: "Connected"
    case .notConnected:
      AgentConnection.gladeExecutable == nil && overrides.agents == nil ? "Available after installing the app." : "Not connected"
    case .connectedElsewhere: "Connected to another copy of \(Brand.name)"
    case .unavailable(let reason): reason
    }
  }

  private func load() async {
    if let fixed = overrides.agents?[agent] {
      state = fixed
      return
    }
    state = await AgentConnection.state(agent)
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
      state = await AgentConnection.state(agent)
      working = false
    }
  }
}
