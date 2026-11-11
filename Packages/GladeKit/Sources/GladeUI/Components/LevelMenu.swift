import GladeKit
import SwiftUI

/// How boldly a clean selects, as a quiet menu: "Balanced ⌄". The level is a setting
/// that shapes the selection, not a view switch, so it isn't a segmented control.
public struct LevelMenu: View {
  @Environment(AppModel.self) private var model
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  /// Offers "Reset Selection" when the person has changed choices by hand.
  var offersReset: Bool
  /// The trigger's edge the popover's arrow points from: `.bottom` opens it below
  /// the trigger, `.top` above (for the clean bar at the foot of the window).
  var arrowEdge: Edge

  public init(offersReset: Bool = true, arrowEdge: Edge = .bottom) {
    self.offersReset = offersReset
    self.arrowEdge = arrowEdge
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
        : nil,
      arrowEdge: arrowEdge
    )
    .disabled(model.isCleaning)
    .accessibilityIdentifier("levelMenu")
    .help("What a clean selects")
  }
}

extension CleanLevel {
  /// What the level selects, in a few words, for the menu. It follows `Planner` and
  /// the levels the catalog and scanners give: Careful takes what rebuilds itself once
  /// it has sat idle; Balanced adds package and installer downloads, idle simulators,
  /// worktrees and stale agent history (which can't be recreated, so its row and the
  /// confirm sheet say so); Aggressive adds installed toolkits and stops waiting.
  public var consequence: String {
    switch self {
    case .careful: "Things that rebuild themselves and haven’t been used lately"
    case .balanced: "Adds old downloads, idle simulators and stale agent history"
    case .aggressive: "Adds tools you’d reinstall and things used recently"
    }
  }
}
