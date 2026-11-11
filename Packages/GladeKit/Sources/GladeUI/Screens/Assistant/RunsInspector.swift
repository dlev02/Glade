import GladeKit
import SwiftUI

/// The Assistant's Details: what cloud AIs can see, and every run Glade has recorded,
/// newest first. Choosing one shows exactly what was sent.
struct RunsInspector: View {
  /// `nil` until the records have been read.
  var runs: [AssistantRun]?
  var open: (AssistantRun) -> Void
  @State private var selection: String?

  var body: some View {
    List(selection: $selection) {
      // Wraps at any width rather than trailing off.
      HStack(alignment: .firstTextBaseline, spacing: Metrics.s) {
        Image(systemName: Symbols.protected)
          .accessibilityHidden(true)
        Text("Cloud AIs see names, sizes and dates only")
          .fixedSize(horizontal: false, vertical: true)
      }
      .font(.callout)
      .foregroundStyle(.secondary)
      .accessibilityElement(children: .combine)
      .selectionDisabled()

      Section("Sent") {
        if let runs {
          if runs.isEmpty {
            Text("Nothing sent yet")
              .foregroundStyle(.secondary)
              .selectionDisabled()
          } else {
            ForEach(runs) { run in
              RunRow(run: run)
                .tag(run.id)
            }
          }
        } else {
          ProgressView()
            .controlSize(.small)
            .frame(maxWidth: .infinity)
            .selectionDisabled()
        }
      }
    }
    .listStyle(.sidebar)
    .onChange(of: selection) { _, id in
      guard let id, let run = runs?.first(where: { $0.id == id }) else { return }
      open(run)
      // A run opens in a sheet; leave nothing highlighted behind it.
      selection = nil
    }
  }
}
