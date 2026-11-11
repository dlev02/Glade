import GladeKit
import SwiftUI

/// How boldly a clean selects, as a quiet menu: "Balanced ⌄". The level is a setting
/// that shapes the selection, not a view switch, so it isn't a segmented control.
public struct LevelMenu: View {
  @Environment(AppModel.self) private var model
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  /// Offers "Reset Selection" when the person has changed choices by hand.
  var offersReset: Bool

  public init(offersReset: Bool = true) {
    self.offersReset = offersReset
  }

  public var body: some View {
    ChoicePopover(
      "Clean level",
      value: model.level.title,
      selection: Binding(get: { model.level }, set: { level in
        withAnimation(reduceMotion ? nil : .smooth(duration: 0.3)) { model.level = level }
      }),
      sections: [ChoiceSection(choices: CleanLevel.allCases.map { Choice($0, $0.title, subtitle: $0.consequence) })],
      footer: offersReset && model.hasManualChoices
        ? ChoiceFooter("Reset Selection", symbol: "arrow.counterclockwise") {
          withAnimation(reduceMotion ? nil : .snappy) { model.resetSelection() }
        }
        : nil
    )
    .disabled(model.isCleaning)
    .accessibilityIdentifier("levelMenu")
    .help("What a clean selects")
  }
}

extension CleanLevel {
  /// What the level adds, in a few words, for the menu.
  public var consequence: String {
    switch self {
    case .careful: "Only things that rebuild themselves"
    case .balanced: "Plus things that download again"
    case .aggressive: "Plus things you reinstall"
    }
  }
}
