import GladeKit
import SwiftUI

/// Apps and tools whose leftovers and caches are always ticked, with a field to add one.
struct AlwaysClearRows: View {
  @Environment(AppModel.self) private var model
  @State private var draft = ""

  var body: some View {
    ForEach(model.config.alwaysClear, id: \.self) { rule in
      HStack {
        Text(rule)
        Spacer()
        if let count = matches(rule), count > 0 {
          Text(count == 1 ? "1 item now" : "\(count) items now")
            .foregroundStyle(.secondary)
            .monospacedDigit()
        }
        Button("Remove", systemImage: "minus.circle") { model.config.alwaysClear.removeAll { $0 == rule } }
          .labelStyle(.iconOnly)
          .buttonStyle(.borderless)
          .foregroundStyle(.secondary)
          .help("Remove")
      }
    }
    HStack {
      TextField("App or tool", text: $draft, prompt: Text("App name"))
        .labelsHidden()
        .onSubmit(add)
      Button("Add", action: add)
        .disabled(AlwaysClear.normalised(draft) == nil)
    }
  }

  private func matches(_ rule: String) -> Int? {
    model.scan.map { scan in scan.findings.filter { AlwaysClear.rule(for: $0, rules: [rule]) != nil }.count }
  }

  private func add() {
    guard let rule = AlwaysClear.normalised(draft) else { return }
    if !model.config.alwaysClear.contains(where: { $0.caseInsensitiveCompare(rule) == .orderedSame }) {
      model.config.alwaysClear.append(rule)
      Log.info(.app, "Added a rule to always clear \(rule)")
    }
    draft = ""
  }
}
