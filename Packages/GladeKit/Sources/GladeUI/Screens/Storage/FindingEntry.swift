import GladeKit

/// One row of the storage list: a finding and how far it's indented, which is one
/// step when it sits inside another finding shown just above it.
struct FindingEntry: Identifiable, Hashable {
  var finding: Finding
  var depth: Int

  var id: String { finding.id }
}
