import Foundation
import GladeKit

/// Removing something the person picked in the whole-disk sheet. The picked folder
/// becomes a finding in the scan held in memory, and the clean sheet removes it like any
/// other: by identifier, checked again, with a receipt and Put Back. It is never saved
/// with the scan, and there is no command for it, so only the person’s own hand in the
/// window can pick a path.
extension AppModel {
  /// Turns a picked path into a finding and focuses the next clean on it. Returns why it
  /// can’t be removed, or `nil` when the clean sheet can open.
  public func pick(forRemoval path: String, bytes: Int64) async -> String? {
    guard !isCleaning else { return "A clean is already running." }
    let result: Result<Finding, PickedFolder.PickError>
    if isDemo {
      // Sample paths aren’t on this Mac; nothing is measured or removed.
      if case .refused(let reason) = PickedFolder.assess(path, protection: Protection(config: config)) { return reason }
      result = .success(Self.samplePick(path, bytes: bytes))
    } else {
      let config = config
      result = await Task.detached(priority: .userInitiated) {
        PickedFolder.finding(for: path, protection: Protection(config: config))
      }.value
    }
    switch result {
    case .failure(let error):
      return error.reason
    case .success(let finding):
      if let blocker = finding.blockers.first { return blocker.detail }
      var base = scan ?? ScanResult(
        id: PickedFolder.scanPrefix + UUID().uuidString, started: Date(), finished: Date(), volume: .current(),
        findings: [], skipped: [], timings: [:], hasFullDiskAccess: hasFullDiskAccess
      )
      base.findings.removeAll { $0.id == finding.id }
      base.findings.append(finding)
      scan = base
      if plan == nil { rebuildPlan() }
      focusClean(on: [finding.id])
      return nil
    }
  }

  /// Drops picked findings that weren’t removed, once the clean sheet closes.
  public func discardPicked() {
    guard var current = scan, current.findings.contains(where: { $0.ruleID == PickedFolder.ruleID }) else { return }
    current.findings.removeAll { $0.ruleID == PickedFolder.ruleID }
    if current.id.hasPrefix(PickedFolder.scanPrefix), current.findings.isEmpty {
      scan = nil
      rebuildPlan()
    } else {
      scan = current
    }
  }

  private static func samplePick(_ path: String, bytes: Int64) -> Finding {
    Finding(
      id: Finding.makeID(rule: PickedFolder.ruleID, path: path), ruleID: PickedFolder.ruleID, category: .largeFiles,
      title: (path as NSString).lastPathComponent, detail: "A folder you chose. It goes to the Trash, so you can put it back.",
      paths: [path], bytes: bytes, recovery: .permanent, risk: .personal, method: .trash, autoLevel: nil
    )
  }
}
