import GladeKit
import SwiftUI

/// The inspector when no single finding is highlighted: a set of findings (what's
/// selected, or the highlighted rows) added up, then broken down by category.
struct SelectionTotals: View {
  var title: String
  var findings: [Finding]

  var body: some View {
    let rows = byCategory
    let total = rows.reduce(0) { $0 + $1.bytes }
    if findings.isEmpty {
      // Nothing to add up: say so plainly instead of "0 KB, 0 items".
      EmptyState("Nothing selected", symbol: "checklist.unchecked")
    } else {
      totals(rows: rows, total: total)
    }
  }

  private func totals(rows: [(category: StorageCategory, bytes: Int64)], total: Int64) -> some View {
    VStack(alignment: .leading, spacing: Metrics.l) {
      VStack(alignment: .leading, spacing: Metrics.xs) {
        Text(title)
          .font(.callout)
          .foregroundStyle(.secondary)
        Text(Format.bytes(total))
          .font(.figure(26))
          .contentTransition(.numericText())
        Text(findings.count == 1 ? "1 item" : "\(findings.count) items")
          .foregroundStyle(.secondary)
          .monospacedDigit()
      }
      .accessibilityElement(children: .combine)

      if !rows.isEmpty {
        VStack(spacing: Metrics.s) {
          ForEach(rows, id: \.category) { row in
            HStack(spacing: Metrics.s) {
              CategoryIcon(row.category, size: 20)
              Text(row.category.title)
                .lineLimit(1)
              Spacer(minLength: Metrics.s)
              Text(Format.bytes(row.bytes))
                .monospacedDigit()
                .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
          }
        }
      }
    }
  }

  /// Bytes per category, largest first, with findings inside another listed finding
  /// counted once. The same rule as the clean's own total, so the two always agree.
  private var byCategory: [(category: StorageCategory, bytes: Int64)] {
    let ids = Set(findings.map(\.id))
    let paths = findings.flatMap { finding in finding.paths.map { ($0, finding.id) } }
    var totals: [StorageCategory: Int64] = [:]
    for finding in findings {
      if let container = finding.within, ids.contains(container) { continue }
      let nested = !finding.paths.isEmpty && finding.paths.allSatisfy { path in
        paths.contains { other, owner in owner != finding.id && path.hasPrefix(other + "/") }
      }
      if nested { continue }
      totals[finding.category, default: 0] += finding.bytes
    }
    return totals.map { ($0.key, $0.value) }.sorted { $0.bytes > $1.bytes }
  }
}
