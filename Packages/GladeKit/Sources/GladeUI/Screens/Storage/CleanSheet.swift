import GladeKit
import SwiftUI

/// The clean, start to finish, in one sheet: confirm, watch it run, see what
/// happened. It can't be dismissed while the clean is running.
struct CleanSheet: View {
  @Environment(AppModel.self) private var model
  /// Closes the sheet.
  var close: () -> Void

  var body: some View {
    Group {
      switch model.cleanState {
      case .idle:
        CleanConfirmation(cancel: close) {
          Task { await model.clean() }
        }
      case .cleaning(let done, let total, let title):
        CleanProgress(done: done, total: total, title: title)
      case .finished(let receiptID):
        if let receipt = model.receipt(receiptID) {
          CleanSummary(receipt: receipt, done: finish)
        } else {
          CleanFailure(message: "The clean finished, but its record couldn’t be read. See History for details.", done: finish)
        }
      case .failed(let message):
        CleanFailure(message: message, done: finish)
      }
    }
    .frame(width: 440)
    .interactiveDismissDisabled(model.isCleaning)
  }

  private func finish() {
    model.dismissCleanResult()
    close()
  }
}

/// Shown when a clean stopped with an error.
private struct CleanFailure: View {
  var message: String
  var done: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: Metrics.l) {
      Label("The clean stopped", systemImage: "xmark.octagon")
        .font(.title2.weight(.semibold))
        .symbolRenderingMode(.multicolor)
      Text(message)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
        .textSelection(.enabled)
      HStack {
        Spacer()
        Button("Done", action: done)
          .keyboardShortcut(.defaultAction)
      }
    }
    .padding(Metrics.xl)
  }
}
