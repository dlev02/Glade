import SwiftUI

/// One line of the setup checklist: a check once it's done, what the step is and why,
/// and the one control that does the next thing.
struct SetupStepRow<Action: View>: View {
  var title: String
  var detail: String
  /// A second, quieter line, such as what to try if a step looks done but isn't.
  var note: String?
  var done: Bool
  @ViewBuilder var action: Action

  var body: some View {
    HStack(alignment: .center, spacing: Metrics.m) {
      Image(systemName: done ? "checkmark.circle.fill" : "circle")
        .font(.title2)
        .frame(width: 24)
        .foregroundStyle(done ? AnyShapeStyle(Palette.good) : AnyShapeStyle(.tertiary))
        .contentTransition(.symbolEffect(.replace))
        .accessibilityHidden(true)
      VStack(alignment: .leading, spacing: 2) {
        Text(title)
          .font(.headline)
        Text(detail)
          .font(.callout)
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
        if let note {
          Text(note)
            .font(.caption)
            .foregroundStyle(.tertiary)
            .fixedSize(horizontal: false, vertical: true)
        }
      }
      Spacer(minLength: Metrics.m)
      action
    }
    .padding(.horizontal, Metrics.l)
    .padding(.vertical, 14)
    .accessibilityElement(children: .contain)
    .accessibilityLabel("\(title), \(done ? "done" : "not done")")
  }
}
