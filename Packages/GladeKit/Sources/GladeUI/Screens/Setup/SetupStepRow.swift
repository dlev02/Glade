import SwiftUI

/// One line of the setup checklist: what the step is, one line about it, and the one
/// control that does the next thing. Steps Glade needs show a circle that fills when
/// done; optional ones show only their control.
struct SetupStepRow<Action: View>: View {
  var title: String
  var detail: String
  /// An instruction that only applies now, such as restarting after granting access.
  var note: String?
  /// Whether the step is done; nil for an optional step, which has no circle.
  var done: Bool?
  @ViewBuilder var action: Action

  var body: some View {
    HStack(alignment: .center, spacing: Metrics.m) {
      if let done {
        Image(systemName: done ? "checkmark.circle.fill" : "circle")
          .font(.title2)
          .frame(width: 24)
          .foregroundStyle(done ? AnyShapeStyle(Palette.good) : AnyShapeStyle(.tertiary))
          .contentTransition(.symbolEffect(.replace))
          .accessibilityHidden(true)
      } else {
        // Optional steps keep the circle’s room empty, so every step’s words start
        // on one edge.
        Color.clear.frame(width: 24, height: 1)
      }
      VStack(alignment: .leading, spacing: 2) {
        Text(title)
          .font(.headline)
        Text(detail)
          .font(.callout)
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
        if let note {
          Text(note)
            .font(.callout)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
      }
      Spacer(minLength: Metrics.m)
      action
    }
    .padding(.horizontal, Metrics.l)
    .padding(.vertical, Metrics.m)
    .accessibilityElement(children: .contain)
    .accessibilityLabel(done.map { "\(title), \($0 ? "done" : "not done")" } ?? title)
  }
}
