import SwiftUI

/// A list of folders inside a form section, each removable, with a button to add more.
struct FolderRows: View {
  @Binding var paths: [String]
  /// What the open panel's button says, such as "Protect".
  var prompt: String
  /// Ask before removing, for lists where removing one lowers protection.
  var confirmsRemoval = false
  @State private var pendingRemoval: String?
  @Environment(\.accentMark) private var accentMark

  var body: some View {
    if paths.isEmpty {
      Text("None")
        .foregroundStyle(.secondary)
    }
    ForEach(paths, id: \.self) { path in
      HStack(spacing: Metrics.s) {
        Image(systemName: "folder")
          .foregroundStyle(.secondary)
          .accessibilityHidden(true)
        Text(path)
          .lineLimit(1)
          .truncationMode(.middle)
          .help(path)
        Spacer(minLength: Metrics.s)
        Button("Remove", systemImage: "minus.circle.fill") {
          if confirmsRemoval { pendingRemoval = path } else { remove(path) }
        }
        .labelStyle(.iconOnly)
        .buttonStyle(.borderless)
        .foregroundStyle(.secondary)
        .help("Remove \(path)")
      }
    }
    Button("Add Folder…", systemImage: "plus") {
      FolderPicker.choose(prompt: prompt) { chosen in
        for path in chosen where !paths.contains(path) { paths.append(path) }
      }
    }
    .buttonStyle(.borderless)
    // The bright accent: the darker fill tint is hard to read as text on a dark form.
    .foregroundStyle(accentMark)
    .confirmationDialog(
      "Stop protecting \(pendingRemoval.map { ($0 as NSString).lastPathComponent } ?? "this folder")?",
      isPresented: Binding(get: { pendingRemoval != nil }, set: { if !$0 { pendingRemoval = nil } }),
      presenting: pendingRemoval
    ) { path in
      Button("Stop Protecting", role: .destructive) { remove(path) }
    } message: { _ in
      Text("Glade will be able to scan and list what’s inside it.")
    }
  }

  private func remove(_ path: String) {
    paths.removeAll { $0 == path }
  }
}
