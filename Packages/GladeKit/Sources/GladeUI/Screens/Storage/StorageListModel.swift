import GladeKit
import Observation

/// The storage list's rows, grouped, filtered and sorted once per change of scan,
/// scope or search, so scrolling through hundreds of findings does no work.
@Observable
final class StorageListModel {
  private struct Key: Equatable {
    var scanID: String
    var findingCount: Int
    var scope: StorageScope
    var query: String
  }

  private(set) var groups: [FindingGroup] = []
  /// How many findings are showing across every group.
  private(set) var visibleCount = 0
  @ObservationIgnored private var byID: [String: Finding] = [:]
  @ObservationIgnored private var key: Key?

  func finding(_ id: String) -> Finding? { byID[id] }

  func update(scan: ScanResult?, scope: StorageScope, query: String) {
    let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
    let next = scan.map { Key(scanID: $0.id, findingCount: $0.findings.count, scope: scope, query: query) }
    guard next != key else { return }
    key = next
    guard let scan else {
      groups = []
      visibleCount = 0
      byID = [:]
      return
    }
    byID = Dictionary(scan.findings.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

    let visible = scan.findings.filter { scope.includes($0) && Self.matches($0, query) }
    var byCategory: [StorageCategory: [Finding]] = [:]
    for finding in visible { byCategory[finding.category, default: []].append(finding) }

    groups = byCategory.map { category, findings in
      FindingGroup(category: category, entries: Self.ordered(findings))
    }
    .sorted { $0.totalBytes != $1.totalBytes ? $0.totalBytes > $1.totalBytes : $0.category.title < $1.category.title }
    visibleCount = visible.count
  }

  /// Largest first, with anything that sits inside another finding placed straight
  /// after its container and indented.
  private static func ordered(_ findings: [Finding]) -> [FindingEntry] {
    let ids = Set(findings.map(\.id))
    let bySize: (Finding, Finding) -> Bool = { $0.bytes != $1.bytes ? $0.bytes > $1.bytes : $0.title < $1.title }
    var children: [String: [Finding]] = [:]
    var tops: [Finding] = []
    for finding in findings {
      if let container = finding.within, ids.contains(container), container != finding.id {
        children[container, default: []].append(finding)
      } else {
        tops.append(finding)
      }
    }
    var entries: [FindingEntry] = []
    entries.reserveCapacity(findings.count)
    var placed = Set<String>()
    func place(_ finding: Finding, depth: Int) {
      guard placed.insert(finding.id).inserted else { return }
      entries.append(FindingEntry(finding: finding, depth: min(depth, 2)))
      for child in (children[finding.id] ?? []).sorted(by: bySize) { place(child, depth: depth + 1) }
    }
    for top in tops.sorted(by: bySize) { place(top, depth: 0) }
    // Anything caught in a loop of containers still gets listed.
    for finding in findings.sorted(by: bySize) where !placed.contains(finding.id) { place(finding, depth: 0) }
    return entries
  }

  private static func matches(_ finding: Finding, _ query: String) -> Bool {
    guard !query.isEmpty else { return true }
    if finding.title.localizedStandardContains(query) { return true }
    if let project = finding.project, project.localizedStandardContains(query) { return true }
    return finding.paths.contains { Redactor.tilde($0).localizedStandardContains(query) }
  }
}
