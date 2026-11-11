import AppKit
import GladeKit
import SwiftUI

/// What a finished clean did, told the way it is: "Freed" only for space that is free
/// now, "Moved to the Trash" for what still waits there, a warning when something was
/// left in place, and a way to put the Trash items back. Every line hangs its icon in
/// one 20-point column so the text shares one edge.
struct CleanSummary: View {
  @Environment(AppModel.self) private var model
  @Environment(\.accentMark) private var accentMark
  var receipt: Receipt
  var done: () -> Void
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var restored: Cleaner.RestoreResult?
  /// Flips once on appear, so the tick bounces a single time.
  @State private var appeared = false

  private static let iconWidth: CGFloat = 20

  var body: some View {
    let freed = receipt.freedBytes
    let trashed = receipt.trashedBytes
    VStack(alignment: .leading, spacing: Metrics.l) {
      headline(freed: freed, trashed: trashed)

      if freed > 0, trashed > 0 {
        line(
          symbol: restored.map { isComplete($0) ? Symbols.putBack : "exclamationmark.triangle" } ?? "trash",
          tint: restored.map { isComplete($0) ? Color.secondary : Palette.warning } ?? .secondary
        ) {
          if let restored {
            Text(backText(restored))
            stuckText(restored)
          } else {
            Text("\(Format.bytes(trashed)) is in the Trash")
              .monospacedDigit()
            Text("Space is freed when the Trash is emptied")
              .font(.callout)
              .foregroundStyle(.secondary)
          }
        }
      }

      if !problems.isEmpty { problemList }

      HStack(spacing: Metrics.s) {
        if trashed > 0, restored == nil {
          Button(trashedCount == 1 ? "Put Back 1 Item" : "Put Back \(trashedCount) Items") {
            restored = model.putBack(receipt)
          }
          .accessibilityIdentifier("result.putBack")
          .secondaryAction()
          .controlSize(.large)
        }
        if trashed > 0, !(restored.map(isComplete) ?? false) {
          // Only opens the Trash in Finder; emptying it is the person’s own choice.
          Button("Show Trash") { showTrash() }
            .accessibilityIdentifier("result.showTrash")
            .secondaryAction()
            .controlSize(.large)
        }
        Spacer()
        Button("Done", action: done)
          .principalAction()
          .controlSize(.large)
          .keyboardShortcut(.defaultAction)
          .accessibilityIdentifier("result.done")
      }
    }
    .padding(Metrics.xl)
    .onAppear {
      if !reduceMotion { appeared = true }
      if DemoState.value("demoClean") == "putback", receipt.trashedBytes > 0 { restored = model.putBack(receipt) }
    }
  }

  // MARK: Headline

  @ViewBuilder
  private func headline(freed: Int64, trashed: Int64) -> some View {
    let warns = !problems.isEmpty
    if freed == 0, trashed > 0, let restored {
      // Everything went to the Trash; it’s reassuring only once all of it is back.
      let complete = isComplete(restored)
      line(
        symbol: complete ? Symbols.putBack : "exclamationmark.triangle.fill",
        tint: complete ? accentMark : Palette.warning, large: true
      ) {
        Text(backText(restored))
          .font(.title2.weight(.semibold))
        if complete {
          Text("Back where they were")
            .foregroundStyle(.secondary)
        }
        stuckText(restored)
      }
    } else if freed == 0, trashed > 0 {
      line(symbol: warns ? "exclamationmark.triangle.fill" : "checkmark.circle.fill", tint: warns ? Palette.warning : accentMark, large: true) {
        Text("Moved \(Format.bytes(trashed)) to the Trash")
          .font(.title2.weight(.semibold))
          .monospacedDigit()
        Text("Space is freed when the Trash is emptied")
          .foregroundStyle(.secondary)
      }
    } else if freed > 0 {
      line(symbol: warns ? "exclamationmark.triangle.fill" : "checkmark.circle.fill", tint: warns ? Palette.warning : accentMark, large: true) {
        Text("Freed \(Format.bytes(freed))")
          .font(.title2.weight(.semibold))
          .monospacedDigit()
        freeSpace
      }
    } else {
      line(symbol: "exclamationmark.triangle.fill", tint: Palette.warning, large: true) {
        Text("Nothing was removed")
          .font(.title2.weight(.semibold))
      }
    }
  }

  /// Free space before and after, as measured. Left out when it didn’t move.
  @ViewBuilder private var freeSpace: some View {
    if receipt.freeAfter != receipt.freeBefore {
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
  }

  /// One line of the sheet: an icon in the shared column, then its text.
  private func line(
    symbol: String, tint: Color, large: Bool = false, @ViewBuilder content: () -> some View
  ) -> some View {
    HStack(alignment: .firstTextBaseline, spacing: Metrics.s) {
      Image(systemName: symbol)
        .font(large ? .title2 : .body)
        .foregroundStyle(tint)
        .symbolEffect(.bounce, options: .nonRepeating, value: large && appeared)
        .frame(width: Self.iconWidth)
        .accessibilityHidden(true)
      VStack(alignment: .leading, spacing: 2) {
        content()
      }
    }
    .accessibilityElement(children: .combine)
  }

  // MARK: Put back

  /// "Put back 19 items", "Put back 17 of 19 items" or "Nothing was put back".
  private func backText(_ result: Cleaner.RestoreResult) -> String {
    let back = result.restored.count
    let total = back + result.missing.count + result.blocked.count
    if back == 0 { return "Nothing was put back" }
    if back == total { return back == 1 ? "Put back 1 item" : "Put back \(back) items" }
    return "Put back \(back) of \(total) items"
  }

  private func isComplete(_ result: Cleaner.RestoreResult) -> Bool {
    !result.restored.isEmpty && result.missing.isEmpty && result.blocked.isEmpty
  }

  private func showTrash() {
    guard let trash = FileManager.default.urls(for: .trashDirectory, in: .userDomainMask).first else { return }
    NSWorkspace.shared.open(trash)
  }

  @ViewBuilder
  private func stuckText(_ result: Cleaner.RestoreResult) -> some View {
    let stuck = result.missing.count + result.blocked.count
    if stuck > 0 {
      // Grey, like every second line: the amber is on the glyph, where it can be seen.
      Text(stuck == 1 ? "1 couldn’t be put back: it’s no longer in the Trash or something took its place" : "\(stuck) couldn’t be put back: they’re no longer in the Trash or something took their place")
        .font(.callout)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
    }
  }

  /// How many things went to the Trash, for the Put Back button.
  private var trashedCount: Int {
    receipt.entries.filter {
      if case .trashed = $0.outcome { return true }
      return false
    }.count
  }

  // MARK: Problems

  private var problemList: some View {
    VStack(alignment: .leading, spacing: Metrics.s) {
      Text(problems.count == 1 ? "1 item was left in place" : "\(problems.count) items were left in place")
        .font(.headline)
        .padding(.leading, Self.iconWidth + Metrics.s)
      ScrollView {
        VStack(alignment: .leading, spacing: Metrics.s) {
          ForEach(problems) { entry in
            line(symbol: "exclamationmark.triangle", tint: Palette.warning) {
              Text(entry.title.keepingDashWithName)
                .lineLimit(1)
                .truncationMode(.middle)
              Text(reason(entry.outcome))
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }
          }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
      }
      .frame(maxHeight: 240)
      .fixedSize(horizontal: false, vertical: true)
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
