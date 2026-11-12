import GladeKit
import SwiftUI

/// Free Up Memory, start to finish, in one sheet: choose, watch it run, see what
/// happened. The twin of the clean sheet. It can’t be dismissed while it’s running.
struct ReliefSheet: View {
  @Environment(AppModel.self) private var model

  var body: some View {
    Group {
      if let session = model.relief {
        switch session.step {
        case .confirm:
          ReliefConfirmation(session: session, cancel: model.dismissRelief) {
            Task { await model.performRelief() }
          }
        case .running(let done, let total, let name):
          CleanProgress(heading: "Freeing up memory…", done: done, total: total, title: name)
        case .finished(let result):
          ReliefSummary(result: result, done: model.dismissRelief)
        }
      }
    }
    .frame(width: 440)
    .interactiveDismissDisabled(model.relief?.isRunning ?? false)
  }
}
