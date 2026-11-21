import GladeKit
import SwiftUI

/// How hard one AI thinks, from a quiet menu beside its model: "High effort ⌄".
struct EffortField: View {
  /// Whose effort this is, for VoiceOver.
  var title: String
  @Binding var value: Effort

  var body: some View {
    Menu {
      Picker(title, selection: $value) {
        ForEach(Effort.allCases) { effort in
          Text(effort.title).tag(effort)
        }
      }
      .pickerStyle(.inline)
      .labelsHidden()
    } label: {
      Text("\(value.title) effort")
    }
    .menuStyle(.borderlessButton)
    .menuIndicator(.visible)
    .fixedSize()
    .tint(.secondary)
    .accessibilityLabel("Effort for \(title)")
    .accessibilityValue(value.title)
    .help("How hard it thinks")
  }
}
