import GladeKit
import SwiftUI

/// Typing the gateway’s Device Access Code: checked by signing in, then kept in the
/// Keychain. The field never shows it, and nothing in Glade shows it again.
struct RouterAccessSheet: View {
  @Environment(\.dismiss) private var dismiss
  var title: String
  var host: String
  @State private var code = ""
  @State private var checking = false
  @State private var problem: String?

  var body: some View {
    VStack(alignment: .leading, spacing: Metrics.m) {
      Text("Access Code for \(title)")
        .font(.headline)
      Text("It’s on the gateway’s label as Device Access Code. Glade keeps it in your Keychain and never shows it to an AI.")
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
      SecureField("Device Access Code", text: $code)
        .textContentType(.password)
        .onSubmit(save)
      if let problem {
        Text(problem).font(.callout).foregroundStyle(Palette.critical)
      }
      HStack {
        Spacer()
        Button("Cancel", role: .cancel) { dismiss() }
          .keyboardShortcut(.cancelAction)
        Button {
          save()
        } label: {
          if checking { ProgressView().controlSize(.small) } else { Text("Save") }
        }
        .keyboardShortcut(.defaultAction)
        .disabled(code.isEmpty || checking)
      }
    }
    .padding(Metrics.xl)
    .frame(width: 420)
  }

  private func save() {
    guard !code.isEmpty, !checking else { return }
    checking = true
    problem = nil
    Task {
      do {
        try await RouterReader.saveAccess(code, router: host)
        code = ""
        dismiss()
      } catch {
        problem = error.localizedDescription
      }
      checking = false
    }
  }
}
