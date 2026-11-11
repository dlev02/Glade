import GladeKit
import SwiftUI

/// Every run Glade has recorded, newest first, and exactly what each one sent and got
/// back, so a person can check the AI was shown names and sizes, not file contents.
struct RunsSheet: View {
  @Environment(\.dismiss) private var dismiss
  /// `nil` until the records have been read.
  @State private var runs: [AssistantRun]?
  @State private var selection: String?

  var body: some View {
    VStack(spacing: 0) {
      HStack {
        Text("What Was Sent")
          .font(.headline)
        Spacer()
        Button("Done") { dismiss() }
          .keyboardShortcut(.defaultAction)
      }
      .padding(.horizontal, Metrics.l)
      .padding(.vertical, Metrics.m)
      Divider()
      content
    }
    .frame(minWidth: 860, idealWidth: 980, minHeight: 560, idealHeight: 700)
    .task {
      // Reading the records touches files, so keep it off the main thread.
      let loaded = await Task.detached { Assistant.runs() }.value
      runs = loaded
      if selection == nil { selection = loaded.first?.id }
    }
  }

  @ViewBuilder
  private var content: some View {
    if let runs {
      if runs.isEmpty {
        EmptyState("Nothing sent yet", symbol: "text.page.badge.magnifyingglass")
      } else {
        HStack(spacing: 0) {
          List(runs, selection: $selection) { run in
            RunRow(run: run)
              .tag(run.id)
          }
          .frame(width: 300)
          Divider()
          if let run = runs.first(where: { $0.id == selection }) {
            RunDetail(run: run)
              .id(run.id)
          } else {
            EmptyState("No run selected", symbol: "text.page.badge.magnifyingglass")
          }
        }
      }
    } else {
      ProgressView()
        .controlSize(.small)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
  }
}
