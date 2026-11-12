import ArgumentParser
import Foundation
import GladeKit

struct Scan: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    abstract: "Find what can be removed. Reads sizes and dates only; changes nothing."
  )

  @OptionGroup var output: OutputOptions

  @Flag(name: .long, help: "Also run the slow scanners (duplicates).")
  var deep = false

  @Option(name: .long, help: "Only show this category (repeatable). See `categories`.")
  var category: [String] = []

  @Option(name: .long, help: "How many findings to list.")
  var limit = 40

  @Flag(name: .long, help: "Include findings that can’t be removed right now.")
  var includeBlocked = false

  func run() async throws {
    let result = await ScanEngine.run(deep: deep) { progress in
      guard !output.json else { return }
      FileHandle.standardError.write(Data("\r\u{1B}[K  scanning… \(progress.finished)/\(progress.total) \(progress.scanner)".utf8))
    }
    if !output.json { FileHandle.standardError.write(Data("\r\u{1B}[K".utf8)) }
    ScanEngine.save(result)

    let wanted = Set(category)
    var shown = result.findings
    if !wanted.isEmpty { shown = shown.filter { wanted.contains($0.category.rawValue) } }
    if !includeBlocked { shown = shown.filter { !$0.isBlocked } }

    if output.json {
      var copy = result
      copy.findings = Array(shown.prefix(limit))
      print(JSONFiles.string(copy))
      return
    }
    printSummary(result, shown: shown)
  }

  private func printSummary(_ result: ScanResult, shown: [Finding]) {
    let volume = result.volume
    print("\(volume.name): \(Format.bytes(volume.availableBytes)) available of \(Format.bytes(volume.totalBytes)) (\(Format.percent(volume.freeFraction)) free)")
    let apps = result.findings.filter { !$0.category.countsAsReclaimable }.count
    print("Found \(Format.bytes(result.totalBytes)) across \(result.findings.count - apps) items\(apps > 0 ? ", and \(apps) installed apps," : "") in \(String(format: "%.1f", result.finished.timeIntervalSince(result.started)))s\n")

    var totals: [StorageCategory: (bytes: Int64, count: Int)] = [:]
    for finding in result.findings {
      totals[finding.category, default: (0, 0)].bytes += finding.bytes
      totals[finding.category, default: (0, 0)].count += 1
    }
    for (category, total) in totals.sorted(by: { $0.value.bytes > $1.value.bytes }) {
      print("  \(Format.bytes(total.bytes).leftPadded(10))  \(category.title) (\(total.count))")
    }
    print("")
    for finding in shown.prefix(limit) {
      print(Table.row(finding))
    }
    if shown.count > limit { print("  … \(shown.count - limit) more (raise --limit)") }
    for skipped in result.skipped {
      print("\nNot scanned: \(skipped.path). \(skipped.reason)")
    }
  }
}

struct Categories: ParsableCommand {
  static let configuration = CommandConfiguration(abstract: "List the storage categories.")

  @OptionGroup var output: OutputOptions

  func run() {
    struct Row: Encodable {
      var id: String
      var title: String
    }
    let rows = StorageCategory.allCases.map { Row(id: $0.rawValue, title: $0.title) }
    emit(rows, json: output.json) {
      for row in rows { print("\(row.id.padding(toLength: 22, withPad: " ", startingAt: 0)) \(row.title)") }
    }
  }
}

enum Table {
  static func row(_ finding: Finding) -> String {
    let flags = [
      finding.risk.title,
      finding.recovery.title,
      finding.autoLevel.map { "auto≥\($0.rawValue)" } ?? "manual",
      finding.blockers.first.map { "BLOCKED: \($0.detail)" },
    ].compactMap { $0 }.joined(separator: " · ")
    let place = finding.paths.isEmpty ? "Managed by its own tool" : finding.paths.count == 1 ? Redactor.tilde(finding.paths[0]) : "\(finding.paths.count) locations"
    return "  \(finding.id.padding(toLength: 13, withPad: " ", startingAt: 0)) \(Format.bytes(finding.bytes).leftPadded(10))  \(finding.title)\n\(String(repeating: " ", count: 28))\(flags)\n\(String(repeating: " ", count: 28))\(place)"
  }
}

extension String {
  func leftPadded(_ width: Int) -> String {
    count >= width ? self : String(repeating: " ", count: width - count) + self
  }
}
