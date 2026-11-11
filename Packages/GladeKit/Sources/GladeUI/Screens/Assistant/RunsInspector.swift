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
    // The privacy line sits above the list, not in it: a list row keeps one line's
    // height at narrow widths, and this must wrap and show in full.
    VStack(alignment: .leading, spacing: 0) {
      privacy
      list
    }
  }

  private var privacy: some View {
    HStack(alignment: .firstTextBaseline, spacing: Metrics.s) {
      Image(systemName: Symbols.protected)
        .accessibilityHidden(true)
      Text("Cloud AIs see names, sizes and dates only")
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    .font(.callout)
    .foregroundStyle(.secondary)
    .padding(.horizontal, Metrics.l)
    .padding(.top, Metrics.m)
    .padding(.bottom, Metrics.xs)
    .accessibilityElement(children: .combine)
  }

  private var list: some View {
    List(selection: $selection) {
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
