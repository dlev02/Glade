import SwiftUI

/// A quiet header that folds its content in and out, with a chevron that turns, the
/// same way Storage's groups do.
struct AdviceDisclosure<Label: View, Content: View>: View {
  @Binding var isExpanded: Bool
  @ViewBuilder var label: Label
  @ViewBuilder var content: Content
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    VStack(alignment: .leading, spacing: Metrics.s) {
      Button {
        withAnimation(reduceMotion ? nil : .snappy(duration: 0.18)) { isExpanded.toggle() }
      } label: {
        HStack(spacing: Metrics.xs) {
          label
          Image(systemName: "chevron.right")
            .font(.caption2.weight(.semibold))
            .rotationEffect(.degrees(isExpanded ? 90 : 0))
            .accessibilityHidden(true)
        }
        .contentShape(.rect)
      }
      .buttonStyle(.plain)
      .accessibilityValue(isExpanded ? "Expanded" : "Collapsed")
      if isExpanded {
        content
          .transition(.opacity)
      }
    }
  }
}
