import GladeKit

/// What the current selection adds up to: the findings ticked, what a clean would work
/// through, and the space it frees. `AppModel` works this out once per change of the
/// selection, so the clean bar, Overview and the menu bar all read the same figures
/// without adding them up again.
struct SelectionSummary {
  /// Every ticked finding, in scan order.
  var ids: [String] = []
  /// What a clean works through, biggest first, nested findings left out.
  var items: [Finding] = []
  var selected: Int64 = 0
  var immediate: Int64 = 0

  init(scan: ScanResult?, plan: CleanPlan?, config: GladeConfig, isSelected: (String) -> Bool) {
    guard let scan else { return }
    ids = scan.findings.map(\.id).filter(isSelected)
    items = Planner.topLevel(ids, in: scan).sorted { $0.bytes > $1.bytes }
    guard var copy = plan else { return }
    let chosen = Set(ids)
    copy.items = scan.findings.map { PlanItem(id: $0.id, selected: chosen.contains($0.id), reason: "") }
    Planner.total(&copy, scan: scan, config: config)
    selected = copy.selectedBytes
    immediate = copy.immediateBytes
  }
}
