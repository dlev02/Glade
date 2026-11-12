import ArgumentParser
import Foundation
import GladeKit

struct Usage: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    abstract: "Show what is taking up the whole disk, folder by folder. Reads names and sizes only; changes nothing.",
    discussion: "Protected folders are stepped around and never measured, so their space is in “Not measured”."
  )

  @OptionGroup var output: OutputOptions

  @Flag(name: .long, help: "Show the last measurement instead of measuring again.")
  var cached = false

  @Option(name: .long, help: "How many levels of folders to print.")
  var depth = 2

  func run() async throws {
    var usage = cached ? DiskUsageMeter.loadLast() : nil
    if usage == nil {
      usage = await DiskUsageMeter.measure { progress in
        guard !output.json else { return }
        FileHandle.standardError.write(Data("\r\u{1B}[K  measuring… \(progress.finished)/\(progress.total) \(progress.area?.title ?? "")".utf8))
      }
      if !output.json { FileHandle.standardError.write(Data("\r\u{1B}[K".utf8)) }
      if let usage { DiskUsageMeter.save(usage) }
    }
    guard let usage else { throw ExitCode.failure }
    if output.json {
      print(JSONFiles.string(usage))
      return
    }

    let volume = usage.volume
    print("\(volume.name): \(Format.bytes(volume.usedBytes)) used of \(Format.bytes(volume.totalBytes)), measured in \(String(format: "%.1f", usage.seconds))s\n")
    let clearable = ScanEngine.loadLast().map(usage.clearable) ?? [:]
    for area in usage.areas { printNode(area, level: 0, clearable: clearable) }
    if usage.unmeasuredBytes > 0 {
      print("\(Format.bytes(usage.unmeasuredBytes).leftPadded(10))  Not measured: protected folders, folders this account can’t read, and snapshots macOS keeps")
    }
    if usage.protectedSkipped > 0 || usage.unreadable > 0 {
      print("\nLeft out: \(usage.protectedSkipped) protected and \(usage.unreadable) unreadable places.")
    }
  }

  private func printNode(_ node: UsageNode, level: Int, clearable: [String: Int64]) {
    let indent = String(repeating: "  ", count: level)
    var line = "\(Format.bytes(node.bytes).leftPadded(10))  \(indent)\(node.title)"
    if level == 0, let path = node.path { line += "  (\(Redactor.tilde(path)))" }
    if let path = node.path, let bytes = clearable[path], bytes > 0 { line += "  · \(Format.bytes(min(bytes, node.bytes))) found by the last scan" }
    print(line)
    guard level < depth else { return }
    for child in node.children { printNode(child, level: level + 1, clearable: clearable) }
    if !node.children.isEmpty, node.unlistedBytes >= 50_000_000 {
      print("\(Format.bytes(node.unlistedBytes).leftPadded(10))  \(indent)  Smaller items")
    }
  }
}
