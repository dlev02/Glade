import Foundation

public struct CleanOptions: Sendable {
  /// Work out what would happen without removing anything.
  public var dryRun: Bool
  public var initiator: Initiator

  public init(dryRun: Bool = true, initiator: Initiator = .user) {
    self.dryRun = dryRun
    self.initiator = initiator
  }
}

public enum CleanError: Error, LocalizedError {
  case noScan
  case staleScan(hours: Int)

  public var errorDescription: String? {
    switch self {
    case .noScan: "There’s no scan to clean from. Run a scan first."
    case .staleScan(let hours): "The last scan is \(hours) hours old. Scan again so nothing has changed underneath."
    }
  }
}

/// Removes findings. This is the only code in Glade that deletes anything, and it
/// trusts nothing it's handed: every path is checked against the safety policy again
/// at the moment of removal, whatever the scan or an assistant said earlier.
public enum Cleaner {
  /// A scan older than this must be redone before cleaning from it.
  public static let maximumScanAge: TimeInterval = 12 * 3600

  /// Removes the findings with the given identifiers.
  ///
  /// Identifiers that aren't in `scan` are skipped: nothing outside what the scanner
  /// itself found can be removed, so no caller can name a path of its own.
  public static func clean(
    ids: [String],
    from scan: ScanResult,
    config: GladeConfig = ConfigStore.load(),
    options: CleanOptions,
    protection: Protection? = nil,
    running: RunningApps? = nil,
    progress: @escaping @Sendable (_ done: Int, _ total: Int, _ title: String) -> Void = { _, _, _ in }
  ) async throws -> Receipt {
    let age = Date().timeIntervalSince(scan.finished)
    guard age < maximumScanAge else { throw CleanError.staleScan(hours: Int(age / 3600)) }

    let protection = protection ?? Protection(config: config)
    let running = running ?? RunningApps.current()
    let freeBefore = VolumeInfo.current().freeBytes
    var entries: [ReceiptEntry] = []
    var seen = Set<String>()
    let unique = ids.filter { seen.insert($0).inserted }
    Log.info(.clean, "\(options.dryRun ? "Dry run" : "Clean") started by \(options.initiator.title): \(unique.count) items")

    for (index, id) in unique.enumerated() {
      guard let finding = scan.finding(id) else {
        Log.warning(.clean, "Skipped \(id): not in the scan")
        entries.append(ReceiptEntry(
          id: id, title: "Unknown item", category: .temporaryFiles, paths: [], bytes: 0,
          outcome: .skipped(reason: "Not something the last scan found.")
        ))
        continue
      }
      progress(index, unique.count, finding.title)
      let outcome = await remove(finding, protection: protection, running: running, config: config, dryRun: options.dryRun)
      entries.append(ReceiptEntry(
        id: finding.id, title: finding.title, category: finding.category, paths: finding.paths,
        bytes: finding.bytes, outcome: outcome
      ))
      Log.info(.clean, "\(finding.title) [\(finding.ruleID)] \(Format.bytes(finding.bytes)): \(describe(outcome))")
    }
    progress(unique.count, unique.count, "")

    let receipt = Receipt(
      id: UUID().uuidString, date: Date(), initiator: options.initiator, dryRun: options.dryRun,
      entries: entries, freeBefore: freeBefore, freeAfter: VolumeInfo.current().freeBytes
    )
    if !options.dryRun {
      do {
        try JSONFiles.write(receipt, to: GladePaths.receipts.appendingPathComponent("\(Int(receipt.date.timeIntervalSince1970))-\(receipt.id.prefix(8)).json"))
      } catch {
        Log.error(.clean, "Couldn’t save the receipt: \(error)")
      }
      Log.info(.clean, "Clean finished: removed \(Format.bytes(receipt.removedBytes)) (\(Format.bytes(receipt.trashedBytes)) to Trash), \(receipt.failures.count) failures, free space \(Format.bytes(receipt.freeBefore)) → \(Format.bytes(receipt.freeAfter))")
    }
    return receipt
  }

  // MARK: One finding

  private static func remove(
    _ finding: Finding, protection: Protection, running: RunningApps, config: GladeConfig, dryRun: Bool
  ) async -> RemovalOutcome {
    // Blockers recorded by the scan that still hold.
    for blocker in finding.blockers {
      switch blocker.kind {
      case .reportOnly, .needsAdmin, .needsFullDiskAccess, .uncommittedWork, .inUse:
        return .skipped(reason: blocker.detail)
      case .appRunning:
        // Only still a blocker if the app is open right now.
        if let owner = finding.owner, running.runningName(of: owner) == nil { continue }
        return .skipped(reason: blocker.detail)
      }
    }
    if finding.needsOwnerClosed, let owner = finding.owner, let name = running.runningName(of: owner) {
      return .skipped(reason: "\(name) is open. Quit it first.")
    }

    switch finding.method {
    case .emptyTrash:
      return emptyTrash(finding, protection: protection, dryRun: dryRun)
    case .simulatorDevice(let udid):
      return await simulator(["delete", udid], udid: udid, dryRun: dryRun)
    case .simulatorErase(let udid):
      return await simulator(["erase", udid], udid: udid, dryRun: dryRun)
    case .unavailableSimulators:
      return await simulator(["delete", "unavailable"], udid: nil, dryRun: dryRun)
    case .simulatorSet(let name):
      guard ["previews", "testing"].contains(name) else { return .skipped(reason: "Not a known simulator set.") }
      return await simulator(["--set", name, "delete", "all"], udid: nil, dryRun: dryRun)
    case .simulatorRuntime(let identifier):
      return await simulator(["runtime", "delete", identifier], udid: identifier, dryRun: dryRun)
    case .gitWorktree(let repository):
      return await worktree(finding, repository: repository, protection: protection, dryRun: dryRun)
    case .delete, .trash:
      break
    }

    // Collect what will actually be removed, and check every piece.
    var targets: [String] = []
    for path in finding.paths {
      if finding.contentsOnly {
        guard protection.canScan(path) else { return refuse(finding, path, .protected(zone: "", title: "protected area")) }
        targets += DiskWalk.children(of: path)
      } else {
        targets.append(path)
      }
    }
    var present: [String] = []
    for target in targets {
      var info = stat()
      guard lstat(target, &info) == 0 else { continue }
      let verdict = protection.verdict(forRemoving: target)
      guard verdict.isAllowed else { return refuse(finding, target, verdict) }
      present.append(target)
    }
    guard !present.isEmpty else { return .skipped(reason: "Already gone.") }

    let toTrash = finding.method == .trash || config.trashEverything || finding.risk == .personal
      || present.contains { protection.isPersonalArea($0) && !rebuildable.contains(finding.category) }
    if dryRun { return .wouldRemove }

    if toTrash {
      var locations: [String: String] = [:]
      for path in present {
        do {
          var resulting: NSURL?
          try FileManager.default.trashItem(at: URL(fileURLWithPath: path), resultingItemURL: &resulting)
          locations[path] = resulting?.path ?? ""
        } catch {
          return locations.isEmpty
            ? .failed(reason: reason(error))
            : .failed(reason: "Moved \(locations.count) of \(present.count) to the Trash, then: \(reason(error))")
        }
      }
      return .trashed(locations: locations)
    }

    // One stubborn file (often a temporary file another process owns) shouldn't stop
    // the rest of a group from being cleared.
    var failures: [String] = []
    for path in present {
      do {
        try delete(path)
      } catch {
        failures.append(reason(error))
        Log.warning(.clean, "Couldn’t remove \(path): \(reason(error))")
      }
    }
    if failures.isEmpty { return .deleted }
    if failures.count == present.count { return .failed(reason: failures[0]) }
    return .failed(reason: "\(failures.count) of \(present.count) items couldn’t be removed (\(failures[0])); the rest were.")
  }

  /// Categories whose contents rebuild from a manifest, so they're deleted outright
  /// even inside Documents or Desktop.
  private static let rebuildable: Set<StorageCategory> = [.projectDependencies, .buildOutputs]

  private static func refuse(_ finding: Finding, _ path: String, _ verdict: Verdict) -> RemovalOutcome {
    Log.error(.safety, "Refused to remove \(path) for \(finding.ruleID): \(verdict.explanation)")
    return .skipped(reason: verdict.explanation)
  }

  /// Deletes a file or folder without following links. Folders some tools mark
  /// read-only (Go's module cache) are made writable and tried once more.
  private static func delete(_ path: String) throws {
    do {
      try FileManager.default.removeItem(atPath: path)
    } catch {
      DiskWalk.walk([path]) { entry in
        if entry.isDirectory { chmod(entry.path, 0o700) }
        return .proceed
      }
      try FileManager.default.removeItem(atPath: path)
    }
  }

  // MARK: Special methods

  private static func emptyTrash(_ finding: Finding, protection: Protection, dryRun: Bool) -> RemovalOutcome {
    let trash = protection.home + "/.Trash"
    guard finding.paths == [trash] else { return .skipped(reason: "Not the Trash.") }
    let items = DiskWalk.children(of: trash)
    guard !items.isEmpty else { return .skipped(reason: "Already empty.") }
    if dryRun { return .wouldRemove }
    var failures = 0
    for item in items {
      // The parent must still be the Trash itself, never somewhere a link leads.
      guard (item as NSString).deletingLastPathComponent == trash else { continue }
      do {
        try delete(item)
      } catch {
        failures += 1
        Log.warning(.clean, "Couldn’t remove \(item) from the Trash: \(reason(error))")
      }
    }
    return failures == 0 ? .deleted : .failed(reason: "\(failures) of \(items.count) items couldn’t be removed.")
  }

  private static func simulator(_ arguments: [String], udid: String?, dryRun: Bool) async -> RemovalOutcome {
    if let udid, UUID(uuidString: udid) == nil { return .skipped(reason: "Not a simulator identifier.") }
    if dryRun { return .wouldRemove }
    do {
      let result = try await Shell.run("xcrun", ["simctl"] + arguments, timeout: 120)
      return result.succeeded ? .deleted : .failed(reason: firstLine(result.stderr))
    } catch {
      return .failed(reason: reason(error))
    }
  }

  private static func worktree(_ finding: Finding, repository: String, protection: Protection, dryRun: Bool) async -> RemovalOutcome {
    guard finding.paths.count == 1, let path = finding.paths.first else { return .skipped(reason: "Not a single worktree.") }
    let verdict = protection.verdict(forRemoving: path, allowRepository: true)
    guard verdict.isAllowed else { return refuse(finding, path, verdict) }
    guard protection.canScan(repository) else { return refuse(finding, repository, .protected(zone: "", title: "protected area")) }
    // A worktree's .git is a file. A folder there means this is a full repository.
    var info = stat()
    guard lstat(path + "/.git", &info) == 0, (info.st_mode & S_IFMT) == S_IFREG else {
      return .skipped(reason: "Not a worktree.")
    }
    do {
      // Check again, right now, that nothing uncommitted would be lost.
      let status = try await Shell.run("git", ["-C", path, "status", "--porcelain", "--untracked-files=normal"], timeout: 30)
      guard status.succeeded else { return .skipped(reason: "Git couldn’t read it: \(firstLine(status.stderr))") }
      guard status.stdout.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
        return .skipped(reason: "It has uncommitted changes.")
      }
      if dryRun { return .wouldRemove }
      let result = try await Shell.run("git", ["-C", repository, "worktree", "remove", path], timeout: 120)
      return result.succeeded ? .deleted : .failed(reason: firstLine(result.stderr))
    } catch {
      return .failed(reason: reason(error))
    }
  }

  // MARK: Putting things back

  public struct RestoreResult: Sendable, Codable {
    public var restored: [String]
    public var missing: [String]
    public var blocked: [String]
  }

  /// Moves everything a clean sent to the Trash back where it was. Things that were
  /// deleted outright can't be put back; they rebuild or download again.
  public static func restore(_ receipt: Receipt) -> RestoreResult {
    var result = RestoreResult(restored: [], missing: [], blocked: [])
    let manager = FileManager.default
    for entry in receipt.entries {
      guard case .trashed(let locations) = entry.outcome else { continue }
      for (original, trashed) in locations {
        guard !trashed.isEmpty, manager.fileExists(atPath: trashed) else {
          result.missing.append(original)
          continue
        }
        guard !manager.fileExists(atPath: original) else {
          result.blocked.append(original)
          continue
        }
        do {
          try manager.createDirectory(atPath: (original as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
          try manager.moveItem(atPath: trashed, toPath: original)
          result.restored.append(original)
        } catch {
          result.blocked.append(original)
          Log.warning(.clean, "Couldn’t put back \(original): \(reason(error))")
        }
      }
    }
    Log.info(.clean, "Put back \(result.restored.count) items from receipt \(receipt.id.prefix(8)); \(result.missing.count) no longer in the Trash, \(result.blocked.count) blocked")
    return result
  }

  public static func receipts() -> [Receipt] {
    let files = (try? FileManager.default.contentsOfDirectory(at: GladePaths.receipts, includingPropertiesForKeys: nil)) ?? []
    return files.filter { $0.pathExtension == "json" }
      .compactMap { JSONFiles.read(Receipt.self, from: $0) }
      .sorted { $0.date > $1.date }
  }

  // MARK: Helpers

  private static func reason(_ error: Error) -> String {
    let nsError = error as NSError
    return "\(nsError.localizedDescription) (\(nsError.domain) \(nsError.code))"
  }

  private static func firstLine(_ text: String) -> String {
    text.split(separator: "\n").first.map(String.init) ?? "Unknown error"
  }

  private static func describe(_ outcome: RemovalOutcome) -> String {
    switch outcome {
    case .deleted: "deleted"
    case .trashed(let locations): "moved \(locations.count) to Trash"
    case .skipped(let reason): "skipped (\(reason))"
    case .failed(let reason): "FAILED (\(reason))"
    case .wouldRemove: "would remove"
    }
  }
}
