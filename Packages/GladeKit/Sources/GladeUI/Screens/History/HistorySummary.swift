import GladeKit
import SwiftUI

/// The top of the history list: everything Glade has freed, and in how many cleans.
struct HistorySummary: View {
  var cleans: [Receipt]

  var body: some View {
    let total = cleans.reduce(Int64(0)) { $0 + $1.removedBytes }
    HStack(alignment: .firstTextBaseline, spacing: Metrics.s) {
      Text(Format.bytes(total))
        .font(.figure(34))
      Text(cleans.count == 1 ? "freed in 1 clean" : "freed in \(cleans.count) cleans")
        .font(.title3)
        .foregroundStyle(.secondary)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(.top, Metrics.s)
    .padding(.bottom, Metrics.m)
    .accessibilityElement(children: .combine)
    .accessibilityAddTraits(.isHeader)
  }
}
