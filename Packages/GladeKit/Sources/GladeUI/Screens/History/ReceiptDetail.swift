import GladeKit
import SwiftUI

/// One clean in full: how much it freed, who started it and when, free space before
/// and after, and its items grouped by what happened to them, with Put Back beside
/// the ones in the Trash.
struct ReceiptDetail: View {
  @Environment(AppModel.self) private var model
  var receipt: Receipt
  @State private var confirmsPutBack = false
  @State private var restore: Cleaner.RestoreResult?

  var body: some View {
    let trashed = receipt.entries.filter { $0.outcome.trashedCount > 0 }
    let removed = receipt.entries.filter { $0.outcome == .deleted }
    let kept = receipt.entries.filter { !$0.outcome.removedSomething }
    ScrollView {
      VStack(alignment: .leading, spacing: Metrics.xl) {
        header

        if !trashed.isEmpty {
          group("In the Trash", entries: trashed) {
            Button(trashed.count == 1 ? "Put Back 1 Item" : "Put Back \(trashed.count) Items") {
              confirmsPutBack = true
            }
            .secondaryAction()
            .controlSize(.small)
            .confirmationDialog(
              trashed.count == 1 ? "Put back 1 item from the Trash?" : "Put back \(trashed.count) items from the Trash?",
              isPresented: $confirmsPutBack
            ) {
              Button("Put Back") { restore = model.putBack(receipt) }
                .keyboardShortcut(.defaultAction)
              Button("Cancel", role: .cancel) {}
            } message: {
              Text("They go back where they were.")
            }
          } footer: {
            if let restore { outcome(restore) }
          }
        }
        if !removed.isEmpty {
          group("Deleted", entries: removed)
        }
        if !kept.isEmpty {
          group("Left in place", entries: kept, showsOutcome: true)
        }
      }
      .padding(Metrics.l)
      .frame(maxWidth: .infinity, alignment: .leading)
    }
  }

  private var header: some View {
    let name = receipt.initiator.name(providerName: { model.providerName($0) })
    let freed = receipt.freedBytes
    let trashed = receipt.trashedBytes
    return VStack(alignment: .leading, spacing: Metrics.s) {
      VStack(alignment: .leading, spacing: 2) {
        HStack(alignment: .firstTextBaseline, spacing: Metrics.s) {
          Text(Format.bytes(freed > 0 || trashed == 0 ? freed : trashed))
            .font(.figure(34))
          Text(freed > 0 || trashed == 0 ? "freed" : "moved to the Trash")
            .font(.title3)
            .foregroundStyle(.secondary)
        }
        Text("\(name) · \(receipt.date.formatted(date: .abbreviated, time: .shortened))")
          .foregroundStyle(.secondary)
      }
      .accessibilityElement(children: .combine)

      // Free space as measured; nothing to show when only the Trash filled up.
      if freed > 0, receipt.freeAfter != receipt.freeBefore {
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
      }
      if freed > 0, trashed > 0 {
        Text("\(Format.bytes(trashed)) moved to the Trash")
          .foregroundStyle(.secondary)
          .monospacedDigit()
      }
    }
  }

  /// A heading, an optional action level with it, and the items in one card.
  private func group(
    _ title: String, entries: [ReceiptEntry], showsOutcome: Bool = false,
    @ViewBuilder action: () -> some View = { EmptyView() },
    @ViewBuilder footer: () -> some View = { EmptyView() }
  ) -> some View {
    VStack(alignment: .leading, spacing: Metrics.s) {
      HStack(alignment: .center) {
        Text(title)
          .font(.headline)
          .foregroundStyle(.secondary)
          .accessibilityAddTraits(.isHeader)
        Spacer(minLength: Metrics.s)
        action()
      }
      .frame(minHeight: 24)
      Card(padding: 0) {
        VStack(spacing: 0) {
          ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
            if index > 0 { Divider().padding(.leading, 52) }
            EntryRow(entry: entry, showsOutcome: showsOutcome)
          }
        }
      }
      footer()
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
