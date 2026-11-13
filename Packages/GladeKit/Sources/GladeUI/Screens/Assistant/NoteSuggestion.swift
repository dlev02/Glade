import GladeKit
import SwiftUI

/// Under an answer: a fact the Assistant thinks is worth remembering, kept only if the
/// person saves it. Saved notes are in Settings › Assistant.
struct NoteSuggestion: View {
  @Environment(AppModel.self) private var model
  var message: AppModel.Message.ID
  var note: String
  @State private var problem: String?

  var body: some View {
    HStack(alignment: .firstTextBaseline, spacing: Metrics.s) {
      Image(systemName: "bookmark")
        .foregroundStyle(.tint)
        .accessibilityHidden(true)
      VStack(alignment: .leading, spacing: 2) {
        Text("Remember this?")
          .font(.caption)
          .foregroundStyle(.secondary)
        Text(note)
        if let problem {
          Text(problem)
            .font(.caption)
            .foregroundStyle(Palette.critical)
        }
      }
      Spacer(minLength: Metrics.m)
      Button("Not Now") { problem = model.resolveSuggestedNote(in: message, keep: false) }
        .buttonStyle(.borderless)
      Button("Remember") { problem = model.resolveSuggestedNote(in: message, keep: true) }
        .buttonStyle(.bordered)
    }
    .font(.callout)
    .padding(Metrics.m)
    .background(Palette.track, in: .rect(cornerRadius: Metrics.innerRadius))
    .accessibilityElement(children: .contain)
  }
}
