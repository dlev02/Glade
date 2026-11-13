import GladeKit
import SwiftUI

/// The Assistant’s notes: each with its date and a remove button, and a field to add one.
struct NoteRows: View {
  @Environment(AppModel.self) private var model
  @State private var draft = ""
  @State private var problem: String?

  var body: some View {
    ForEach(model.notes) { note in
      HStack(alignment: .firstTextBaseline, spacing: Metrics.s) {
        VStack(alignment: .leading, spacing: 2) {
          Text(note.text)
          Text(note.added.formatted(date: .abbreviated, time: .omitted))
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        Spacer(minLength: Metrics.s)
        Button("Remove", systemImage: "minus.circle") { model.removeNote(note.id) }
          .labelStyle(.iconOnly)
          .buttonStyle(.borderless)
          .foregroundStyle(.secondary)
          .help("Remove")
      }
    }
    HStack {
      TextField("Add a note", text: $draft, prompt: Text("Such as “AT&T fibre with a BGW320 gateway”"))
        .labelsHidden()
        .onSubmit(add)
      Button("Add", action: add)
        .disabled(draft.trimmingCharacters(in: .whitespaces).isEmpty)
    }
    if let problem {
      Text(problem)
        .font(.caption)
        .foregroundStyle(Palette.critical)
    }
  }

  private func add() {
    problem = model.keepNote(draft, source: .person)
    if problem == nil { draft = "" }
  }
}
