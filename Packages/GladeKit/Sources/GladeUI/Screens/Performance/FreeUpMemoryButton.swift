import GladeKit
import SwiftUI

/// Opens Free Up Memory, labelled with what it would give back: "Free Up 7.4 GB of
/// Memory…". Shown only when the plan has something to do.
struct FreeUpMemoryButton: View {
  enum Style {
    /// The page’s main action. Its ⌘Return lives on the page, so it holds while the
    /// button comes and goes with the readings.
    case principal
    /// Beside another main action on the same page.
    case secondary
  }

  @Environment(AppModel.self) private var model
  var style: Style
  var identifier: String

  var body: some View {
    let plan = model.reliefPlan
    if !plan.actions.isEmpty {
      let button = Button(model.reliefButtonTitle(plan)) { model.openRelief() }
        .controlSize(.small)
        .monospacedDigit()
        .accessibilityIdentifier(identifier)
      switch style {
      case .principal:
        button
          .principalAction()
          .help("Choose what to quit or shut down (⌘Return)")
      case .secondary:
        button
          .secondaryAction()
          .help("Choose what to quit or shut down")
      }
    }
  }
}
