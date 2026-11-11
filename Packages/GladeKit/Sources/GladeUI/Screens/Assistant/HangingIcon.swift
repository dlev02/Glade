import SwiftUI

/// Text on the conversation's leading edge with its icon hung in the gutter to the
/// left, so thinking and problem lines start exactly where answers do.
struct HangingIcon<Icon: View, Content: View>: View {
  @ViewBuilder var icon: Icon
  @ViewBuilder var text: Content

  private static var gutter: CGFloat { 16 + Metrics.s }

  var body: some View {
    HStack(alignment: .firstTextBaseline, spacing: Metrics.s) {
      icon
        .frame(width: 16)
      text
    }
    .padding(.leading, -Self.gutter)
  }
}
