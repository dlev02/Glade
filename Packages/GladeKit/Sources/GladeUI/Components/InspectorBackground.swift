import SwiftUI

extension View {
  /// The inspector on the same surface as the content beside it, so the page reads as
  /// one sheet with the system’s hairline between, rather than content beside a grey
  /// panel. Cards inside keep their own outline in light mode.
  func inspectorBackground() -> some View {
    scrollContentBackground(.hidden)
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
      .background(Palette.card)
  }
}
