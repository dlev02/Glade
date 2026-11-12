import AppKit
import ArgumentParser
import Foundation
import GladeKit

/// One installed app as the command line and agents see it.
struct InstalledAppRow: Encodable {
  var id: String
  var name: String
  var bundleID: String
  var version: String?
  var path: String
  var bytes: Int64
  var size: String
  var appBytes: Int64
  var dataBytes: Int64
  var lastOpened: Date?
  var lastOpenedText: String
  var source: String
  var hasOwnUninstaller: Bool
  var uninstaller: String?
  /// Whether `uninstall --confirm` would move it to the Trash right now.
  var canUninstall: Bool
  /// Why it can’t, when it can’t.
  var blocked: String?

  init(_ finding: Finding) {
    let app = finding.app
    id = finding.id
    name = finding.title
    bundleID = app?.bundleID ?? ""
    version = app?.version
    path = Redactor.tilde(finding.paths.first ?? "")
    bytes = finding.bytes
    size = Format.bytes(finding.bytes)
    appBytes = app?.bundleBytes ?? finding.bytes
    dataBytes = app?.dataBytes ?? 0
    lastOpened = finding.lastUsed
    lastOpenedText = finding.lastUsed.map { Format.age($0) } ?? "unknown"
    source = app?.source.rawValue ?? AppSource.other.rawValue
    hasOwnUninstaller = finding.blockers.contains { $0.kind == .ownUninstaller }
    uninstaller = app?.uninstaller.map(Redactor.tilde)
    canUninstall = !finding.isBlocked
    blocked = finding.blockers.first?.detail
  }
}

enum AppScans {
  /// The last scan with its apps, or a fresh look at the apps alone when it has none.
  /// A fresh look is merged into a recent full scan, so `clean --ids` can use its
  /// identifiers; on its own it isn’t saved, so it never stands in for a full scan.
  static func current(rescan: Bool, quiet: Bool) async -> ScanResult {
    let last = ScanEngine.loadLast()
    let recent = last.flatMap { Date().timeIntervalSince($0.finished) < Cleaner.maximumScanAge ? $0 : nil }
    if !rescan, let recent, Date().timeIntervalSince(recent.finished) < 3600,
       recent.findings.contains(where: { $0.category == .installedApps }) {
      return recent
    }
    let apps = await ScanEngine.run(scanners: [InstalledAppScanner()]) { progress in
      guard !quiet else { return }
      FileHandle.standardError.write(Data("\r\u{1B}[K  looking at apps… \(progress.finished)/\(progress.total)".utf8))
    }
    if !quiet { FileHandle.standardError.write(Data("\r\u{1B}[K".utf8)) }
    guard var merged = recent else { return apps }
    merged.findings.removeAll { $0.category == .installedApps }
    let taken = Set(merged.findings.flatMap(\.paths))
    merged.findings += apps.findings.filter { !taken.contains($0.paths.first ?? "") }
    merged.findings.sort { $0.bytes > $1.bytes }
    ScanEngine.save(merged)
    return merged
  }

  static func rows(_ scan: ScanResult, unused days: Int?, sort: InstalledSort) -> [InstalledAppRow] {
    var apps = scan.findings.filter { $0.category == .installedApps }
    if let days {
      apps = apps.filter { finding in finding.idleDays().map { $0 >= days } ?? true }
    }
    switch sort {
    case .size: apps.sort { $0.bytes > $1.bytes }
    case .opened: apps.sort { ($0.lastUsed ?? .distantPast) < ($1.lastUsed ?? .distantPast) }
    }
    return apps.map(InstalledAppRow.init)
  }

  /// One app’s finding, looked at afresh, by name, file name or identifier.
  static func find(_ name: String) async throws -> (Finding, ScanResult) {
    let result = await ScanEngine.run(scanners: [InstalledAppScanner(only: name)])
    let apps = result.findings.filter { $0.category == .installedApps }
    let wanted = name.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ".app", with: "")
    let exact = apps.filter { $0.title.caseInsensitiveCompare(wanted) == .orderedSame }
    if exact.count == 1 { return (exact[0], result) }
    guard !apps.isEmpty, exact.isEmpty ? !isPartOfMacOS(wanted) : true else { throw AppCommandFailure(message: notFound(wanted)) }
    guard apps.count == 1 else {
      throw AppCommandFailure(message: "“\(name)” could be \(Format.listed(apps.map(\.title).sorted())). Give the full name or the bundle identifier.")
    }
    return (apps[0], result)
  }

  /// Why an app isn’t offered: it’s Glade, part of macOS, or not installed.
  private static func notFound(_ name: String) -> String {
    if name.caseInsensitiveCompare(Brand.name) == .orderedSame {
      return "\(Brand.name) doesn’t uninstall itself. Quit it and drag it to the Trash in Finder."
    }
    if isPartOfMacOS(name) { return "\(name) is part of macOS, so \(Brand.name) leaves it alone." }
    return "No installed app called “\(name)”. `\(Brand.cli) installed` lists them."
  }

  private static func isPartOfMacOS(_ name: String) -> Bool {
    let system = ["/System/Applications", "/System/Applications/Utilities", "/System/Cryptexes/App/System/Applications"]
    return system.contains { FileManager.default.fileExists(atPath: "\($0)/\(name).app") }
  }
}

struct AppCommandFailure: Error, CustomStringConvertible, LocalizedError {
  var message: String
  var description: String { message }
  var errorDescription: String? { message }
}

enum InstalledSort: String, ExpressibleByArgument, CaseIterable {
  case size, opened
}

struct Installed: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    abstract: "List the apps in the Applications folders: size, last opened, where each came from. Changes nothing.",
    discussion: """
      Each app’s size includes the data it keeps in your home folder. Apps with their own \
      uninstaller are marked; `\(Brand.cli) uninstall "<name>"` explains what removing one would do.
      """
  )

  @OptionGroup var output: OutputOptions

  @Option(name: .long, help: "Only apps not opened for at least this many days.")
  var unused: Int?

  @Option(name: .long, help: "size (largest first) or opened (longest unused first).")
  var sort: InstalledSort = .size

  @Flag(name: .long, help: "Look at the apps again instead of using the last scan.")
  var rescan = false

  func run() async throws {
    let scan = await AppScans.current(rescan: rescan, quiet: output.json)
    let rows = AppScans.rows(scan, unused: unused, sort: sort)
    emit(rows, json: output.json) {
      if rows.isEmpty { print(unused == nil ? "No apps found." : "No apps unused for \(unused ?? 0) days.") }
      for row in rows {
        var marks: [String] = []
        if row.hasOwnUninstaller { marks.append("has its own uninstaller") } else if let blocked = row.blocked { marks.append(blocked) }
        let opened = row.lastOpened.map { "opened \(Format.age($0))" } ?? "never seen opened"
        print("  \(row.id.padding(toLength: 13, withPad: " ", startingAt: 0)) \(row.size.leftPadded(10))  \(row.name)  — \(opened), \(AppSource(rawValue: row.source)?.title ?? row.source)\(marks.isEmpty ? "" : " · " + marks.joined(separator: " · "))")
      }
      if !rows.isEmpty {
        let total = rows.reduce(Int64(0)) { $0 + $1.bytes }
        print("\n\(rows.count) apps, \(Format.bytes(total)). `\(Brand.cli) uninstall \"<name>\"` shows what removing one would do.")
      }
    }
  }
}

struct Uninstall: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    abstract: "Move an app and its data to the Trash. A dry run unless --confirm is given.",
    discussion: """
      Everything goes to the Trash, so `\(Brand.cli) undo` puts it back. Apps that come with \
      their own uninstaller (Adobe’s, for example) aren’t removed by Glade: --open-uninstaller \
      opens theirs, and the next scan lists anything left behind under App Leftovers.
      """
  )

  @OptionGroup var output: OutputOptions

  @Argument(help: "The app’s name, file name or bundle identifier.")
  var name: String

  @Flag(name: .long, help: "Actually move it to the Trash. Without this, nothing changes.")
  var confirm = false

  @Flag(name: .customLong("open-uninstaller"), help: "For an app with its own uninstaller, open it.")
  var openUninstaller = false

  func run() async throws {
    let (finding, scan) = try await AppScans.find(name)
    let report = try await UninstallReport.make(finding, scan: scan, confirm: confirm, openUninstaller: openUninstaller)
    emit(report, json: output.json) { report.print() }
  }
}

/// What uninstalling an app would do, or did.
struct UninstallReport: Encodable {
  struct Item: Encodable {
    var path: String
    var what: String
    var bytes: Int64
    var size: String
  }

  struct Kept: Encodable {
    var path: String
    var reason: String
  }

  var app: InstalledAppRow
  var dryRun: Bool
  /// moved, wouldMove, skipped, failed, ownUninstaller, openedUninstaller
  var result: String
  var message: String
  var goes: [Item]
  var stays: [Kept]
  var receipt: String?

  static func make(
    _ finding: Finding, scan: ScanResult, confirm: Bool, openUninstaller: Bool, initiator: Initiator = .commandLine
  ) async throws -> UninstallReport {
    let row = InstalledAppRow(finding)
    let details = finding.app
    var goes = [Item(path: row.path, what: "The app", bytes: row.appBytes, size: Format.bytes(row.appBytes))]
    goes += (details?.parts ?? []).map { Item(path: Redactor.tilde($0.path), what: $0.label, bytes: $0.bytes, size: Format.bytes($0.bytes)) }
    var stays = (details?.kept ?? []).map { Kept(path: Redactor.tilde($0.path), reason: $0.reason) }

    if let blocker = finding.blockers.first(where: { $0.kind == .ownUninstaller }) {
      var message = blocker.detail
      var result = "ownUninstaller"
      if openUninstaller, let path = details?.uninstaller {
        NSWorkspace.shared.open(URL(fileURLWithPath: path))
        Log.info(.clean, "Opened the uninstaller for \(finding.title)")
        message = "Opened \(((path as NSString).lastPathComponent as NSString).deletingPathExtension). When it’s done, `\(Brand.cli) scan` lists anything it left behind under App Leftovers."
        result = "openedUninstaller"
      } else if details?.uninstaller != nil {
        message += " Run again with --open-uninstaller to open it."
      }
      return UninstallReport(app: row, dryRun: true, result: result, message: message, goes: [], stays: [], receipt: nil)
    }

    let receipt = try await Cleaner.clean(
      ids: [finding.id], from: scan, options: CleanOptions(dryRun: !confirm, initiator: initiator)
    )
    let entry = receipt.entries.first
    for (path, reason) in (entry?.leftInPlace ?? [:]).sorted(by: { $0.key < $1.key }) {
      stays.append(Kept(path: Redactor.tilde(path), reason: reason))
      goes.removeAll { $0.path == Redactor.tilde(path) }
    }
    let result: String, message: String
    switch entry?.outcome {
    case .wouldRemove?:
      result = "wouldMove"
      message = "Dry run: \(Format.bytes(goes.reduce(0) { $0 + $1.bytes })) would go to the Trash. Add --confirm to do it."
    case .trashed?:
      result = "moved"
      message = "Moved \(finding.title) to the Trash. `\(Brand.cli) undo` puts it back; the space is freed when the Trash is emptied."
      if let last = ScanEngine.loadLast() { ScanEngine.save(last.removing(receipt)) }
    case .skipped(let reason)?:
      result = "skipped"
      message = reason
      goes = []
    case .failed(let reason)?:
      result = "failed"
      message = reason
      goes = []
    default:
      result = "skipped"
      message = "Nothing happened."
      goes = []
    }
    return UninstallReport(
      app: row, dryRun: receipt.dryRun, result: result, message: message, goes: goes, stays: stays,
      receipt: receipt.dryRun ? nil : String(receipt.id.prefix(8))
    )
  }

  func print() {
    Swift.print("\(app.name) \(app.version ?? "") — \(app.size), last opened \(app.lastOpenedText)")
    if !goes.isEmpty {
      Swift.print(dryRun ? "\nWould go to the Trash:" : "\nMoved to the Trash:")
      for item in goes { Swift.print("  \(item.size.leftPadded(10))  \(item.what): \(item.path)") }
    }
    if !stays.isEmpty {
      Swift.print("\nStays:")
      for item in stays { Swift.print("  \(item.path) — \(item.reason)") }
    }
    Swift.print("\n\(message)")
    if result == "failed" || result == "skipped", app.blocked?.contains("Finder") == true || message.contains("Finder") {
      Swift.print("Show it in Finder: open -R \"\((app.path as NSString).expandingTildeInPath)\"")
    }
    if let receipt { Swift.print("Receipt \(receipt).") }
  }
}
