import GladeKit
import SwiftUI

/// How boldly a clean selects, as a quiet menu: "Balanced ⌄". The level is a setting
/// that shapes the selection, not a view switch, so it isn't a segmented control.
public struct LevelMenu: View {
  @Environment(AppModel.self) private var model
  /// Offers "Reset Selection" when the person has changed choices by hand.
  var offersReset: Bool

  public init(offersReset: Bool = true) {
    self.offersReset = offersReset
  }

  public var body: some View {
    Menu {
      Picker("Clean level", selection: Binding(get: { model.level }, set: { level in
        withAnimation(.smooth(duration: 0.3)) { model.level = level }
      })) {
        ForEach(CleanLevel.allCases) { level in
          Text(level.title)
          Text(level.consequence)
        }
      }
      .pickerStyle(.inline)
      .labelsHidden()
      if offersReset, model.hasManualChoices {
        Divider()
        Button("Reset Selection", systemImage: "arrow.counterclockwise") {
          withAnimation(.snappy) { model.resetSelection() }
        }
      }
    } label: {
      Text(model.level.title)
    }
    .menuStyle(.borderlessButton)
    .menuIndicator(.visible)
    .fixedSize()
    // The accent fill is too dark to read as text on a dark surface.
    .tint(.secondary)
    .disabled(model.isCleaning)
    .accessibilityLabel("Clean level")
    .accessibilityValue(model.level.title)
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
