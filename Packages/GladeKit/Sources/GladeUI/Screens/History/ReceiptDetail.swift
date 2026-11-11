import GladeKit
import SwiftUI

/// One clean in full: how much it removed, free space before and after, what happened
/// to each item, and Put Back for anything that went to the Trash.
struct ReceiptDetail: View {
  @Environment(AppModel.self) private var model
  var receipt: Receipt
  @State private var confirmsPutBack = false
  @State private var restore: Cleaner.RestoreResult?

  var body: some View {
    let trashed = receipt.entries.reduce(0) { $0 + $1.outcome.trashedCount }
    let deleted = receipt.entries.contains { $0.outcome == .deleted }
    ScrollView {
      VStack(alignment: .leading, spacing: Metrics.l) {
        VStack(alignment: .leading, spacing: 2) {
          Text(Format.bytes(receipt.removedBytes))
            .font(.figure(34))
          Text("removed by \(who) · \(receipt.date.formatted(date: .abbreviated, time: .shortened))")
            .font(.title3)
            .foregroundStyle(.secondary)
        }

        HStack(spacing: Metrics.s) {
          Text("Free space")
            .foregroundStyle(.secondary)
          Text(Format.bytes(receipt.freeBefore))
          Image(systemName: "arrow.right")
            .foregroundStyle(.tertiary)
            .accessibilityLabel("to")
          Text(Format.bytes(receipt.freeAfter))
            .fontWeight(.medium)
        }
        .monospacedDigit()
        .accessibilityElement(children: .combine)

        Card(padding: 0) {
          VStack(spacing: 0) {
            ForEach(Array(receipt.entries.enumerated()), id: \.element.id) { index, entry in
              if index > 0 { Divider().padding(.leading, 56) }
              EntryRow(entry: entry)
            }
          }
        }

        if trashed > 0 {
          putBack(count: trashed, alsoDeleted: deleted)
        } else if deleted {
          Text("Removed items rebuild or download again when they’re needed, so there’s nothing to put back.")
            .font(.callout)
            .foregroundStyle(.secondary)
        }
      }
      .padding(Metrics.xl)
      .frame(maxWidth: Metrics.contentWidth, alignment: .leading)
    }
  }

  private var who: String {
    switch receipt.initiator {
    case .user: "you"
    case .commandLine: "the command line"
    case .assistant(let provider): model.providerName(provider)
    case .automation(let rule): "automation (\(rule))"
    }
  }

  private func putBack(count: Int, alsoDeleted: Bool) -> some View {
    VStack(alignment: .leading, spacing: Metrics.s) {
      HStack(spacing: Metrics.m) {
        Button("Put Back", systemImage: "arrow.uturn.backward") { confirmsPutBack = true }
          .buttonStyle(.glassProminent)
          .controlSize(.large)
        if let restore {
          outcome(restore)
        }
      }
      .confirmationDialog(
        count == 1 ? "Put back 1 item from the Trash?" : "Put back \(count) items from the Trash?",
        isPresented: $confirmsPutBack
      ) {
        Button("Put Back") { restore = model.putBack(receipt) }
          .keyboardShortcut(.defaultAction)
        Button("Cancel", role: .cancel) {}
      } message: {
        Text("They go back where they were.")
      }
      if alsoDeleted {
        Text("Only items in the Trash can come back. Removed items rebuild or download again when they’re needed.")
          .font(.callout)
          .foregroundStyle(.secondary)
      }
    }
  }

  private func outcome(_ result: Cleaner.RestoreResult) -> some View {
    var parts: [String] = []
    let back = result.restored.count
    if back > 0 || (result.missing.isEmpty && result.blocked.isEmpty) {
      parts.append(back == 1 ? "1 item is back where it was." : "\(back) items are back where they were.")
    }
    if !result.missing.isEmpty {
      parts.append(result.missing.count == 1 ? "1 is no longer in the Trash." : "\(result.missing.count) are no longer in the Trash.")
    }
    if !result.blocked.isEmpty {
      parts.append(result.blocked.count == 1
        ? "1 couldn’t go back because something is already there."
        : "\(result.blocked.count) couldn’t go back because something is already there.")
    }
    let complete = result.missing.isEmpty && result.blocked.isEmpty
    return Label {
      Text(parts.joined(separator: " "))
        .fixedSize(horizontal: false, vertical: true)
    } icon: {
      Image(systemName: complete ? "checkmark.circle" : "exclamationmark.triangle")
        .foregroundStyle(complete ? Palette.good : Palette.warning)
    }
    .font(.callout)
  }
}
