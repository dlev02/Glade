import GladeKit
import SwiftUI

/// What a finished clean did: space freed, free space before and after, anything
/// that was skipped or failed and why, and a way to put the Trash items back.
struct CleanSummary: View {
  @Environment(AppModel.self) private var model
  var receipt: Receipt
  var done: () -> Void
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var restored: Cleaner.RestoreResult?
  /// Flips once on appear, so the tick bounces a single time.
  @State private var appeared = false

  var body: some View {
    VStack(alignment: .leading, spacing: Metrics.l) {
      VStack(alignment: .leading, spacing: Metrics.xs) {
        HStack(spacing: Metrics.s) {
          Image(systemName: "checkmark.circle.fill")
            .foregroundStyle(.green)
            .symbolEffect(.bounce, options: .nonRepeating, value: appeared)
            .accessibilityHidden(true)
          Text("Freed \(Format.bytes(receipt.removedBytes))")
        }
        .font(.title2.weight(.semibold))
        HStack(spacing: Metrics.s) {
          Text("Free space")
          Text(Format.bytes(receipt.freeBefore))
          Image(systemName: "arrow.right")
            .font(.caption)
            .accessibilityLabel("to")
          Text(Format.bytes(receipt.freeAfter))
            .foregroundStyle(.primary)
            .fontWeight(.medium)
        }
        .foregroundStyle(.secondary)
        .monospacedDigit()
        .accessibilityElement(children: .combine)
      }

      if receipt.trashedBytes > 0 { trashSection }

      if !problems.isEmpty {
        VStack(alignment: .leading, spacing: Metrics.s) {
          Text(problems.count == 1 ? "1 item was left in place" : "\(problems.count) items were left in place")
            .font(.headline)
          ForEach(problems) { entry in
            HStack(alignment: .firstTextBaseline, spacing: Metrics.s) {
              Image(systemName: "exclamationmark.triangle")
                .foregroundStyle(.orange)
                .accessibilityHidden(true)
              VStack(alignment: .leading, spacing: 2) {
                Text(entry.title)
                  .lineLimit(1)
                  .truncationMode(.middle)
                Text(reason(entry.outcome))
                  .font(.callout)
                  .foregroundStyle(.secondary)
                  .fixedSize(horizontal: false, vertical: true)
              }
            }
            .accessibilityElement(children: .combine)
          }
        }
      }

      HStack(spacing: Metrics.s) {
        if receipt.trashedBytes > 0, restored == nil {
          Button(trashedCount == 1 ? "Put Back 1 Item" : "Put Back \(trashedCount) Items", systemImage: Symbols.putBack) {
            restored = model.putBack(receipt)
          }
          .secondaryAction()
          .controlSize(.large)
        }
        Spacer()
        Button("Done", action: done)
          .principalAction()
          .controlSize(.large)
          .keyboardShortcut(.defaultAction)
      }
    }
    .padding(Metrics.xl)
    .onAppear {
      if !reduceMotion { appeared = true }
    }
  }

  /// How many things went to the Trash, for the Put Back button.
  private var trashedCount: Int {
    receipt.entries.filter {
      if case .trashed = $0.outcome { return true }
      return false
    }.count
  }

  private var trashSection: some View {
    HStack(alignment: .firstTextBaseline, spacing: Metrics.m) {
      Image(systemName: "trash")
        .foregroundStyle(.secondary)
        .accessibilityHidden(true)
      VStack(alignment: .leading, spacing: 2) {
        if let restored {
          Text(restored.restored.count == 1 ? "1 item is back where it was." : "\(restored.restored.count) items are back where they were.")
          let stuck = restored.missing.count + restored.blocked.count
          if stuck > 0 {
            Text(stuck == 1 ? "1 couldn’t be put back: it’s no longer in the Trash or something took its place." : "\(stuck) couldn’t be put back: they’re no longer in the Trash or something took their place.")
              .font(.callout)
              .foregroundStyle(.secondary)
              .fixedSize(horizontal: false, vertical: true)
          }
        } else {
          Text("\(Format.bytes(receipt.trashedBytes)) is in the Trash")
            .monospacedDigit()
        }
      }
    }
  }

  private var problems: [ReceiptEntry] {
    receipt.entries.filter {
      switch $0.outcome {
      case .failed, .skipped: true
      default: false
      }
    }
  }

  private func reason(_ outcome: RemovalOutcome) -> String {
    switch outcome {
    case .failed(let reason), .skipped(let reason): reason
    default: ""
    }
  }
}
