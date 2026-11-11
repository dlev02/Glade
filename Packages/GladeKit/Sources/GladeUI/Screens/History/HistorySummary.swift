import GladeKit
import SwiftUI

/// The top of the history list: everything Glade has freed, and in how many cleans.
struct HistorySummary: View {
  var cleans: [Receipt]

  var body: some View {
    // Freed is what was deleted; what went to the Trash is counted on its own, since
    // it frees nothing until the Trash is emptied.
    let freed = cleans.reduce(Int64(0)) { $0 + $1.freedBytes }
    let trashed = cleans.reduce(Int64(0)) { $0 + $1.trashedBytes }
    let count = cleans.count == 1 ? "1 clean" : "\(cleans.count) cleans"
    VStack(alignment: .leading, spacing: 2) {
      HStack(alignment: .firstTextBaseline, spacing: Metrics.s) {
        Text(Format.bytes(freed > 0 || trashed == 0 ? freed : trashed))
          .font(.figure(34))
        Text(freed > 0 || trashed == 0 ? "freed in \(count)" : "moved to the Trash in \(count)")
          .font(.title3)
          .foregroundStyle(.secondary)
      }
      if freed > 0, trashed > 0 {
        Text("\(Format.bytes(trashed)) moved to the Trash")
          .foregroundStyle(.secondary)
          .monospacedDigit()
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(.top, Metrics.s)
    .padding(.bottom, Metrics.m)
    .accessibilityElement(children: .combine)
    .accessibilityAddTraits(.isHeader)
  }
}
