import GladeKit
import SwiftUI

/// What an answer proposed doing: each action as Glade describes it, with what became
/// of it. Waiting ones have Approve and Not Now; a clean that sent things to the Trash
/// has Put Back. The words are Glade’s, never the AI’s.
struct ActionCard: View {
  @Environment(AppModel.self) private var model
  var message: UUID
  var state: ActionCardState

  var body: some View {
    Card(padding: 0) {
      VStack(alignment: .leading, spacing: Metrics.m) {
        ForEach(state.actions) { action in
          ActionRow(action: action, status: state.status[action.id] ?? .waiting(""), message: message, state: state)
        }
        footer
      }
      .padding(.horizontal, Metrics.xxl)
      .padding(.vertical, Metrics.l)
    }
    .padding(.horizontal, -Metrics.xxl)
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  private var footer: some View {
    HStack(alignment: .firstTextBaseline, spacing: Metrics.m) {
      Label(modeLine, systemImage: state.mode == .full ? "bolt.shield" : state.mode == .auto ? "person.2" : "hand.raised")
        .font(.caption)
        .foregroundStyle(.secondary)
      Spacer(minLength: Metrics.m)
      if state.waiting.count > 1 {
        Button("Approve All") { Task { await model.approveAllActions(in: message) } }
          .secondaryAction()
          .disabled(state.isBusy)
          .accessibilityIdentifier("actions.approveAll")
      }
    }
  }

  private var modeLine: String {
    switch state.mode {
    case .ask: return "Ask Every Time"
    case .full: return "Full Access"
    case .auto:
      guard let reviewer = state.reviewer else { return "Auto" }
      return "Auto · checked by \(model.responderName(reviewer, model: nil))"
    }
  }
}

private struct ActionRow: View {
  @Environment(AppModel.self) private var model
  var action: AgentAction
  var status: ActionCardState.Status
  var message: UUID
  var state: ActionCardState

  var body: some View {
    HStack(alignment: .firstTextBaseline, spacing: Metrics.m) {
      icon.frame(width: 16)
      VStack(alignment: .leading, spacing: 2) {
        Text(verbatim: action.title).fontWeight(.medium)
        Text(verbatim: action.detail)
          .font(.callout)
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
        if let line = statusLine {
          Text(verbatim: line)
            .font(.callout)
            .foregroundStyle(statusColour)
            .fixedSize(horizontal: false, vertical: true)
        }
      }
      Spacer(minLength: Metrics.m)
      buttons
    }
    .accessibilityElement(children: .contain)
  }

  @ViewBuilder private var icon: some View {
    switch status {
    case .checking, .running: ProgressView().controlSize(.small)
    case .waiting: Image(systemName: "circle.dotted").foregroundStyle(.secondary)
    case .done: Image(systemName: "checkmark.circle.fill").foregroundStyle(Palette.good)
    case .failed: Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Palette.warning)
    case .declined: Image(systemName: "minus.circle").foregroundStyle(.tertiary)
    }
  }

  private var statusLine: String? {
    switch status {
    case .checking: return "Getting a second opinion…"
    case .running: return "Working on it…"
    case .waiting(let why):
      guard state.mode != .ask else { return nil }
      return why.hasSuffix(".") || why.hasSuffix("?") ? why : why + "."
    case .done(let text):
      let prefix = state.ranByThemselves.contains(action.id) ? "Done without asking. " : "Done. "
      return state.putBack.contains(action.id) ? "Put back." : prefix + text
    case .failed(let text): return text
    case .declined: return "Not done."
    }
  }

  private var statusColour: Color {
    if case .failed = status { return Palette.warning }
    return .secondary
  }

  @ViewBuilder private var buttons: some View {
    switch status {
    case .waiting:
      HStack(spacing: Metrics.s) {
        Button("Not Now") { model.declineAction(action.id, in: message) }
          .buttonStyle(.link)
        Button("Approve") { Task { await model.approveAction(action.id, in: message) } }
          .principalAction()
          .disabled(state.isBusy)
          .accessibilityIdentifier("actions.approve.\(action.kind.rawValue)")
      }
    case .done where state.receipts[action.id] != nil && !state.putBack.contains(action.id):
      Button("Put Back") { model.putBackAction(action.id, in: message) }
        .secondaryAction()
    default:
      EmptyView()
    }
  }
}
