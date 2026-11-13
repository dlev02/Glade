import AppKit
import GladeKit
import SwiftUI

/// One turn: the person’s words in a quiet bubble on the right, the assistant’s answer
/// as plain reading text on the left, or a notice when something went wrong.
/// Answers are rendered from their Markdown; Copy copies the Markdown itself.
struct MessageRow: View {
  @State private var backupProblem: String?
  @Environment(AppModel.self) private var model
  var message: AppModel.Message
  /// This message’s advice still describes the selection, so its card can act on it.
  var isLiveAdvice: Bool
  var showWhatWasSent: () -> Void
  @State private var isHovered = false
  @FocusState private var focusedAction: Action?

  private enum Action { case copy, sent }

  var body: some View {
    switch message.role {
    case .person: person
    case .assistant: assistant
    case .problem: problem
    }
  }

  private var person: some View {
    HStack {
      Spacer(minLength: Metrics.xxl * 3)
      Text(verbatim: message.text)
        .textSelection(.enabled)
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(.fill.secondary, in: .rect(cornerRadius: 18))
    }
  }

  private var assistant: some View {
    VStack(alignment: .leading, spacing: Metrics.s) {
      // Every answer says which AI wrote it, quietly.
      Text(model.responderName(message.provider, model: message.model))
        .font(.caption)
        .foregroundStyle(.secondary)
        .accessibilityLabel("\(model.responderName(message.provider, model: message.model)) answered")
      MarkdownText(message.text, spacing: Metrics.m)
        .lineSpacing(3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contextMenu {
          Button("Copy", systemImage: "document.on.document", action: copy)
          Button("Show What Was Sent", systemImage: Symbols.whatWasSent, action: showWhatWasSent)
        }
        // The hover buttons are invisible until the pointer is near; VoiceOver gets
        // the same two as actions on the answer itself.
        .accessibilityActions {
          Button("Copy", action: copy)
          Button("Show What Was Sent", action: showWhatWasSent)
        }
      if let advice = message.advice {
        AdviceCard(advice: advice, isLive: isLiveAdvice)
          .padding(.top, Metrics.xs)
      }
      if let proposal = message.proposal {
        ProposalCard(message: message.id, state: proposal)
          .padding(.top, Metrics.xs)
      }
      if message.offersCleanedBackup || message.rulesFile != nil {
        HStack(spacing: Metrics.m) {
          if message.offersCleanedBackup {
            Button("Save Cleaned Backup…", systemImage: "square.and.arrow.down") { saveCleanedBackup() }
              .help("Your backup without these rules, to restore in Little Snitch")
          }
          if let file = message.rulesFile {
            Button("Save New Rules…", systemImage: "plus.square.on.square") { save(file) }
          }
        }
        .padding(.top, Metrics.xs)
        if let backupProblem {
          Text(backupProblem).font(.caption).foregroundStyle(Palette.critical)
        }
      }
      if let note = message.suggestedNote {
        NoteSuggestion(message: message.id, note: note)
          .padding(.top, Metrics.xs)
      }
      actions
    }
    .onHover { hovering in
      withAnimation(.snappy(duration: 0.15)) { isHovered = hovering }
    }
  }

  /// Saves the cleaned backup next to where the person chooses; Little Snitch’s File ›
  /// Restore from Backup… takes it from there.
  private func saveCleanedBackup() {
    switch model.cleanedLittleSnitchBackup() {
    case .failure(let error):
      backupProblem = error.localizedDescription
    case .success(let cleaned):
      backupProblem = nil
      let panel = NSSavePanel()
      panel.nameFieldStringValue = cleaned.name
      panel.message = "Without \(cleaned.removed) rules. Then in Little Snitch: File › Restore from Backup…"
      guard panel.runModal() == .OK, let url = panel.url else { return }
      do {
        try cleaned.data.write(to: url, options: .atomic)
      } catch {
        backupProblem = error.localizedDescription
      }
    }
  }

  /// Saves suggested Little Snitch rules where the person chooses; opening the file
  /// imports it into Little Snitch.
  private func save(_ file: Data) {
    let panel = NSSavePanel()
    panel.nameFieldStringValue = "Glade suggested rules.lsrules"
    panel.canCreateDirectories = true
    guard panel.runModal() == .OK, let url = panel.url else { return }
    do {
      try file.write(to: url, options: .atomic)
      Log.info(.app, "Saved suggested Little Snitch rules")
    } catch {
      Log.warning(.app, "Couldn’t save the suggested rules: \(error.localizedDescription)")
    }
  }

  /// Shown on hover or when one of them has keyboard focus. VoiceOver reaches them as
  /// actions on the answer.
  private var actions: some View {
    HStack(spacing: Metrics.m) {
      CopyButton { message.text }
        .focused($focusedAction, equals: .copy)
        .help("Copy")
      Button("Show What Was Sent", systemImage: Symbols.whatWasSent, action: showWhatWasSent)
        .focused($focusedAction, equals: .sent)
        .help("Show What Was Sent")
    }
    .labelStyle(.iconOnly)
    .buttonStyle(.borderless)
    .foregroundStyle(.tertiary)
    .font(.system(size: 13))
    .padding(.top, -Metrics.xs)
    .opacity(isHovered || focusedAction != nil ? 1 : 0)
  }

  private var problem: some View {
    HangingIcon {
      Image(systemName: "exclamationmark.triangle")
        .foregroundStyle(Palette.warning)
        .accessibilityLabel("Problem")
    } text: {
      Text(verbatim: message.text)
        .textSelection(.enabled)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    .font(.callout)
  }

  private func copy() {
    Copying.copy(message.text)
  }
}
