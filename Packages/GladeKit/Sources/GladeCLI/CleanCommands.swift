import ArgumentParser
import Foundation
import GladeKit

extension CleanLevel: ExpressibleByArgument {}

struct Plan: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    abstract: "Show what a clean would remove at a given level. Changes nothing.",
    discussion: "Uses the last scan, or scans first if there isn't a recent one."
  )

  @OptionGroup var output: OutputOptions

  @Option(name: .long, help: "careful, balanced or aggressive.")
  var level: CleanLevel?

  @Flag(name: .long, help: "Scan again instead of using the last scan.")
  var rescan = false

  @Flag(name: .long, help: "Also list what was left out, and why.")
  var all = false

  func run() async throws {
    let config = ConfigStore.load()
    let scan = try await Scans.recent(rescan: rescan, quiet: output.json)
    let plan = Planner.plan(scan: scan, level: level ?? config.level, config: config)

    struct Row: Encodable {
      var id: String
      var title: String
      var category: String
      var bytes: Int64
      var selected: Bool
      var reason: String
      var recovery: String
      var risk: String
      var path: String
    }
    struct Report: Encodable {
      var level: String
      var selectedBytes: Int64
      var freedImmediately: Int64
      var movedToTrash: Int64
      var freeNow: Int64
      var items: [Row]
      var review: [String]
    }
    let rows = plan.items.compactMap { item -> Row? in
      guard let finding = scan.finding(item.id), all || item.selected else { return nil }
      return Row(
        id: finding.id, title: finding.title, category: finding.category.rawValue, bytes: finding.bytes,
        selected: item.selected, reason: item.reason, recovery: finding.recovery.rawValue, risk: finding.risk.rawValue,
        path: finding.paths.count == 1 ? Redactor.tilde(finding.paths[0]) : "\(finding.paths.count) locations"
      )
    }
    let report = Report(
      level: plan.level.rawValue, selectedBytes: plan.selectedBytes, freedImmediately: plan.immediateBytes,
      movedToTrash: plan.selectedBytes - plan.immediateBytes, freeNow: scan.volume.availableBytes,
      items: rows, review: plan.review
    )
    emit(report, json: output.json) {
      print("\(plan.level.title) plan: \(Format.bytes(plan.selectedBytes)) across \(plan.selectedIDs.count) items")
      print("  \(Format.bytes(plan.immediateBytes)) freed immediately, \(Format.bytes(plan.selectedBytes - plan.immediateBytes)) moved to the Trash\n")
      for row in rows where row.selected {
        print("  ✓ \(row.id.padding(toLength: 13, withPad: " ", startingAt: 0)) \(Format.bytes(row.bytes).leftPadded(10))  \(row.title)  — \(row.reason)")
      }
      if all {
        print("\nLeft out:")
        for row in rows where !row.selected {
          print("  · \(row.id.padding(toLength: 13, withPad: " ", startingAt: 0)) \(Format.bytes(row.bytes).leftPadded(10))  \(row.title)  — \(row.reason)")
        }
      }
      print("\nRun `\(Brand.cli) clean --level \(plan.level.rawValue) --confirm` to do this.")
    }
  }
}

struct Clean: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    abstract: "Remove findings. A dry run unless --confirm is given.",
    discussion: """
      Only things the last scan found can be removed, by level or by identifier. \
      Things that rebuild or download again are deleted; everything else goes to the \
      Trash and can be put back with `\(Brand.cli) undo`.
      """
  )

  @OptionGroup var output: OutputOptions

  @Option(name: .long, help: "Remove what this level selects: careful, balanced or aggressive.")
  var level: CleanLevel?

  @Option(name: .long, parsing: .upToNextOption, help: "Remove these finding identifiers (from `scan` or `plan`).")
  var ids: [String] = []

  @Flag(name: .long, help: "Actually remove. Without this, nothing changes.")
  var confirm = false

  @Flag(name: .long, help: "Scan again first.")
  var rescan = false

  func run() async throws {
    guard level != nil || !ids.isEmpty else {
      throw ValidationError("Say what to clean: --level careful|balanced|aggressive, or --ids <id> …")
    }
    let config = ConfigStore.load()
    let scan = try await Scans.recent(rescan: rescan, quiet: output.json)
    var targets = ids.flatMap { $0.split(separator: ",").map(String.init) }
    if let level {
      targets += Planner.plan(scan: scan, level: level, config: config).selectedIDs
    }
    let receipt = try await Cleaner.clean(
      ids: targets, from: scan, config: config,
      options: CleanOptions(dryRun: !confirm, initiator: .commandLine)
    ) { done, total, title in
      guard !output.json, !title.isEmpty else { return }
      FileHandle.standardError.write(Data("\r\u{1B}[K  \(done + 1)/\(total) \(title)".utf8))
    }
    if !output.json { FileHandle.standardError.write(Data("\r\u{1B}[K".utf8)) }

    emit(receipt, json: output.json) {
      for entry in receipt.entries {
        let mark: String
        switch entry.outcome {
        case .deleted: mark = "deleted      "
        case .trashed: mark = "to Trash     "
        case .wouldRemove: mark = "would remove "
        case .skipped(let reason): mark = "skipped      (\(reason)) "
        case .failed(let reason): mark = "FAILED       (\(reason)) "
        }
        print("  \(Format.bytes(entry.bytes).leftPadded(10))  \(mark)\(entry.title)")
      }
      if receipt.dryRun {
        print("\nDry run: \(Format.bytes(receipt.removedBytes)) would be removed. Add --confirm to do it.")
      } else {
        print("\nRemoved \(Format.bytes(receipt.removedBytes)) (\(Format.bytes(receipt.trashedBytes)) is in the Trash).")
        print("Free space: \(Format.bytes(receipt.freeBefore)) → \(Format.bytes(receipt.freeAfter)). Receipt \(receipt.id.prefix(8)).")
      }
    }
  }
}

struct Undo: ParsableCommand {
  static let configuration = CommandConfiguration(
    abstract: "Put back what a clean moved to the Trash.",
    discussion: "Without an identifier, uses the most recent clean. Deleted caches can't be put back; they rebuild."
  )

  @OptionGroup var output: OutputOptions

  @Argument(help: "A receipt identifier (or its first characters) from `receipts`.")
  var receipt: String?

  func run() throws {
    let all = Cleaner.receipts()
    guard let chosen = receipt.map({ wanted in all.first { $0.id.hasPrefix(wanted) } }) ?? all.first else {
      throw ValidationError("No matching clean found.")
    }
    let result = Cleaner.restore(chosen)
    emit(result, json: output.json) {
      print("Put back \(result.restored.count) items.")
      if !result.missing.isEmpty { print("\(result.missing.count) are no longer in the Trash.") }
      if !result.blocked.isEmpty { print("\(result.blocked.count) couldn’t be put back because something is already there.") }
    }
  }
}

struct Receipts: ParsableCommand {
  static let configuration = CommandConfiguration(abstract: "List past cleans.")

  @OptionGroup var output: OutputOptions

  @Option(name: .long, help: "How many to show.")
  var limit = 20

  func run() {
    let receipts = Array(Cleaner.receipts().prefix(limit))
    emit(receipts, json: output.json) {
      if receipts.isEmpty { print("Nothing has been cleaned yet.") }
      for receipt in receipts {
        print("\(receipt.id.prefix(8))  \(receipt.date.formatted(date: .abbreviated, time: .shortened))  \(Format.bytes(receipt.removedBytes).leftPadded(10))  \(receipt.entries.count) items  by \(receipt.initiator.title)")
      }
    }
  }
}

struct Protect: ParsableCommand {
  static let configuration = CommandConfiguration(
    abstract: "Show or change what Glade stays out of.",
    subcommands: [List.self, Add.self, Remove.self, Check.self],
    defaultSubcommand: List.self
  )

  struct List: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "List protected areas.")
    @OptionGroup var output: OutputOptions

    func run() {
      struct Row: Encodable {
        var id: String
        var title: String
        var reason: String
        var locked: Bool
        var paths: [String]
        var names: [String]
      }
      let rows = Protection(config: ConfigStore.load()).zones.map {
        Row(id: $0.id, title: $0.title, reason: $0.reason, locked: $0.locked, paths: $0.paths, names: $0.names)
      }
      emit(rows, json: output.json) {
        for row in rows {
          print("\(row.locked ? "🔒" : "  ") \(row.title) — \(row.reason)")
          if row.id == "custom" { for path in row.paths { print("       \(Redactor.tilde(path))") } }
        }
      }
    }
  }

  struct Add: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Protect a folder.")
    @Argument(help: "The folder to put off limits.") var path: String

    func run() {
      var config = ConfigStore.load()
      let full = URL(fileURLWithPath: (path as NSString).expandingTildeInPath).standardizedFileURL.path
      if !config.protectedPaths.contains(full) { config.protectedPaths.append(full) }
      ConfigStore.save(config)
      print("Protected \(Redactor.tilde(full)).")
    }
  }

  struct Remove: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Stop protecting a folder you added.")
    @Argument(help: "The folder.") var path: String

    func run() {
      var config = ConfigStore.load()
      let full = URL(fileURLWithPath: (path as NSString).expandingTildeInPath).standardizedFileURL.path
      config.protectedPaths.removeAll { $0 == full }
      ConfigStore.save(config)
      print("No longer protecting \(Redactor.tilde(full)).")
    }
  }

  struct Check: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Ask whether Glade could ever remove a path, and why not.")
    @OptionGroup var output: OutputOptions
    @Argument(help: "Any file or folder.") var path: String

    func run() {
      struct Answer: Encodable {
        var path: String
        var removable: Bool
        var explanation: String
        var visibleToScans: Bool
      }
      let protection = Protection(config: ConfigStore.load())
      let full = URL(fileURLWithPath: (path as NSString).expandingTildeInPath).standardizedFileURL.path
      let verdict = protection.verdict(forRemoving: full)
      let answer = Answer(path: full, removable: verdict.isAllowed, explanation: verdict.explanation, visibleToScans: protection.canScan(full))
      emit(answer, json: output.json) {
        print("\(Redactor.tilde(full)): \(verdict.explanation)\(answer.visibleToScans ? "" : " (never scanned)")")
      }
    }
  }
}

struct Logs: ParsableCommand {
  static let configuration = CommandConfiguration(abstract: "Show Glade's recent log lines.")

  @OptionGroup var output: OutputOptions

  @Option(name: .long, help: "How many lines.")
  var limit = 80

  @Flag(name: .long, help: "Only warnings and errors.")
  var problems = false

  func run() {
    let entries = Log.history(limit: 5000).filter { !problems || $0.level >= .warning }.suffix(limit)
    emit(Array(entries), json: output.json) {
      for entry in entries { print(entry.line) }
    }
  }
}

enum Scans {
  /// The last scan if it's fresh enough, otherwise a new one.
  static func recent(rescan: Bool, quiet: Bool) async throws -> ScanResult {
    if !rescan, let last = ScanEngine.loadLast(), Date().timeIntervalSince(last.finished) < 3600 {
      return last
    }
    let result = await ScanEngine.run { progress in
      guard !quiet else { return }
      FileHandle.standardError.write(Data("\r\u{1B}[K  scanning… \(progress.finished)/\(progress.total) \(progress.scanner)".utf8))
    }
    if !quiet { FileHandle.standardError.write(Data("\r\u{1B}[K".utf8)) }
    ScanEngine.save(result)
    return result
  }
}
