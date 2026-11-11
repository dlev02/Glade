import GladeKit
import SwiftUI

/// The inspector when no single finding is highlighted: a set of findings (what’s
/// selected, or the highlighted rows) broken down by category, with their total when
/// nothing else on screen already shows it.
struct SelectionTotals: View {
  @Environment(AppModel.self) private var model
  var title: String
  var findings: [Finding]
  /// Shows the total and item count above the breakdown. Off for the selection, whose
  /// total the clean bar already shows.
  var showsTotal = true

  var body: some View {
    // Nested findings count once, by the same rule as the clean itself.
    let items = model.scan.map { Planner.topLevel(findings.map(\.id), in: $0) } ?? findings
    let rows = byCategory(items)
    if items.isEmpty {
      // Nothing to add up: say so plainly instead of "0 KB, 0 items".
      EmptyState("Nothing selected", symbol: "checklist.unchecked")
    } else {
      totals(rows: rows, items: items)
    }
  }

  private func totals(rows: [(category: StorageCategory, bytes: Int64)], items: [Finding]) -> some View {
    VStack(alignment: .leading, spacing: showsTotal ? Metrics.l : Metrics.m) {
      if showsTotal {
        VStack(alignment: .leading, spacing: Metrics.xs) {
          Text(title)
            .font(.callout)
            .foregroundStyle(.secondary)
          Text(Format.bytes(rows.reduce(0) { $0 + $1.bytes }))
            .font(.figure(26))
            .contentTransition(.numericText())
          Text(items.count == 1 ? "1 item" : "\(items.count) items")
            .foregroundStyle(.secondary)
            .monospacedDigit()
        }
        .accessibilityElement(children: .combine)
      } else {
        Text(title)
          .font(.callout)
          .foregroundStyle(.secondary)
          .accessibilityAddTraits(.isHeader)
      }

      VStack(alignment: .leading, spacing: Metrics.s) {
        ForEach(rows, id: \.category) { row in
          HStack(alignment: .firstTextBaseline, spacing: Metrics.s) {
            CategoryIcon(row.category, size: 20)
              .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + 4 }
            Text(row.category.title)
              .lineLimit(2)
              .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: Metrics.s)
            Text(Format.bytes(row.bytes))
              .monospacedDigit()
              .foregroundStyle(.secondary)
              .fixedSize()
          }
          .accessibilityElement(children: .combine)
        }
      }
    }
  }

  /// Bytes per category, largest first.
  private func byCategory(_ items: [Finding]) -> [(category: StorageCategory, bytes: Int64)] {
    var totals: [StorageCategory: Int64] = [:]
    for finding in items { totals[finding.category, default: 0] += finding.bytes }
    return totals.map { ($0.key, $0.value) }.sorted { $0.bytes > $1.bytes }
  }
}
