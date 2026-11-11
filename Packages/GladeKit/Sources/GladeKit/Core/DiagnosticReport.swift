import Foundation

/// A problem report a person can read before sending. It holds versions, permissions,
/// what kinds of things the last scan found, and recent log lines. It leaves out file
/// names and paths unless the person asks for them, and nothing is sent anywhere:
/// the report is saved to a file and the person attaches it to an issue themselves.
public enum DiagnosticReport {
  public struct Options: Sendable {
    /// Include finding titles and locations from the last scan. Off by default,
    /// because folder and project names can be personal.
    public var includeFindings: Bool
    public var logLines: Int

    public init(includeFindings: Bool = false, logLines: Int = 300) {
      self.includeFindings = includeFindings
      self.logLines = logLines
    }
  }

  /// Builds the report text.
  /// - Parameter extra: Sections the caller adds, such as which AIs are connected.
  public static func build(options: Options = Options(), extra: [(title: String, body: String)] = []) -> String {
    var sections: [(String, String)] = []
    let info = ProcessInfo.processInfo
    let config = ConfigStore.load()

    sections.append(("Glade", """
      Version: \(Brand.version) (\(Brand.build))
      macOS: \(info.operatingSystemVersionString)
      Mac: \(hardwareModel()), \(info.activeProcessorCount) cores, \(Format.bytes(Int64(info.physicalMemory))) memory
      Full Disk Access: \(FullDiskAccess.isGranted ? "granted" : "not granted")
      Running as: \(Bundle.main.bundlePath.hasSuffix(".app") ? "app" : "command line")
      """))

    let volume = VolumeInfo.current()
    sections.append(("Disk", "\(Format.bytes(volume.availableBytes)) available of \(Format.bytes(volume.totalBytes)) (\(Format.bytes(volume.purgeableBytes)) of that is purgeable)"))

    sections.append(("Settings", """
      Level: \(config.level.rawValue); send everything to Trash: \(config.trashEverything)
      Protected folders added: \(config.protectedPaths.count); zones unlocked: \(config.unlockedZones.isEmpty ? "none" : config.unlockedZones.joined(separator: ", "))
      Assistant order: \(config.assistant.order.joined(separator: ", ")); effort: \(config.assistant.effort.rawValue); proactive: \(config.assistant.proactive); share excerpts: \(config.assistant.shareExcerpts)
      Alerts: \(config.automation.enabled ? "on" : "off") (storage below \(Int(config.automation.storageFreeGB)) GB, auto-clean \(config.automation.autoCleanOnLowStorage))
      Content index: \(config.index.enabled ? "on" : "off")
      """))

    if let scan = ScanEngine.loadLast() {
      var lines = ["Scanned \(Format.age(scan.finished)) in \(String(format: "%.0f", scan.finished.timeIntervalSince(scan.started)))s: \(scan.findings.count) findings, \(Format.bytes(scan.totalBytes))"]
      var totals: [StorageCategory: (Int64, Int)] = [:]
      for finding in scan.findings where finding.within == nil {
        totals[finding.category, default: (0, 0)].0 += finding.bytes
        totals[finding.category, default: (0, 0)].1 += 1
      }
      for (category, total) in totals.sorted(by: { $0.value.0 > $1.value.0 }) {
        lines.append("  \(category.title): \(Format.bytes(total.0)) in \(total.1)")
      }
      lines.append("Scanner timings: " + scan.timings.sorted { $0.value > $1.value }.map { "\($0.key) \(String(format: "%.1f", $0.value))s" }.joined(separator: ", "))
      if options.includeFindings {
        lines.append("")
        for finding in scan.findings.prefix(80) {
          let place = finding.paths.count == 1 ? Redactor.tilde(finding.paths[0]) : "\(finding.paths.count) locations"
          lines.append("  \(finding.ruleID) | \(Format.bytes(finding.bytes)) | \(finding.title) | \(finding.risk.rawValue)/\(finding.recovery.rawValue) | \(finding.blockers.first?.detail ?? "-") | \(place)")
        }
      }
      sections.append(("Last scan", lines.joined(separator: "\n")))
    } else {
      sections.append(("Last scan", "None yet."))
    }

    let receipts = Cleaner.receipts().prefix(5)
    if !receipts.isEmpty {
      sections.append(("Recent cleans", receipts.map { receipt in
        "\(receipt.date.formatted(.iso8601)) by \(receipt.initiator.title): \(receipt.entries.count) items, \(Format.bytes(receipt.removedBytes)), \(receipt.failures.count) failures"
      }.joined(separator: "\n")))
    }

    for section in extra { sections.append((section.title, section.body)) }

    Log.flush()
    let entries = Log.history(limit: options.logLines)
    let log = entries.map { options.includeFindings ? $0.line : scrubPaths($0.line) }.joined(separator: "\n")
    sections.append(("Log (last \(entries.count) lines)", log.isEmpty ? "Empty." : log))

    return sections.map { "## \($0.0)\n\n\($0.1)" }.joined(separator: "\n\n") + "\n"
  }

  /// Writes the report to the Desktop and returns where it went.
  public static func save(_ text: String) throws -> URL {
    let stamp = Date().formatted(.iso8601.year().month().day().dateSeparator(.dash))
    let folder = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask)[0]
    let file = folder.appendingPathComponent("\(Brand.name) Report \(stamp).txt")
    try text.write(to: file, atomically: true, encoding: .utf8)
    Log.info(.app, "Saved a problem report (\(text.count) characters)")
    return file
  }

  /// A link that opens a new issue with the essentials filled in. The report itself
  /// is attached by hand, so the person sees exactly what they’re sharing.
  public static func issueURL(summary: String = "") -> URL? {
    var components = URLComponents(string: Brand.issuesURL)
    let body = """
      **What happened**


      **What you expected**


      **Details**
      \(Brand.name) \(Brand.version) (\(Brand.build)) on macOS \(ProcessInfo.processInfo.operatingSystemVersionString)

      Attach the report file saved to your Desktop (“\(Brand.name) Report …txt”). It contains versions, settings and recent log lines, and no file names unless you chose to include them.
      """
    components?.queryItems = [URLQueryItem(name: "title", value: summary), URLQueryItem(name: "body", value: body)]
    return components?.url
  }

  /// Replaces anything path-like in a log line, keeping only its first two folders.
  static func scrubPaths(_ line: String) -> String {
    guard let pattern = try? NSRegularExpression(pattern: #"(~|/Users/[^/\s]+|/private/var|/var)(/[^\s:,;)\]"']+)+"#) else { return line }
    var result = line
    let matches = pattern.matches(in: line, range: NSRange(line.startIndex..., in: line)).reversed()
    for match in matches {
      guard let range = Range(match.range, in: result) else { continue }
      let parts = result[range].split(separator: "/", omittingEmptySubsequences: true)
      let kept = parts.prefix(parts.first == "~" ? 3 : 4).joined(separator: "/")
      result.replaceSubrange(range, with: (result[range].hasPrefix("/") ? "/" : "") + kept + "/…")
    }
    return result
  }

  private static func hardwareModel() -> String {
    var size = 0
    sysctlbyname("hw.model", nil, &size, nil, 0)
    guard size > 0 else { return "Mac" }
    var buffer = [CChar](repeating: 0, count: size)
    sysctlbyname("hw.model", &buffer, &size, nil, 0)
    return String(decoding: buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
  }
}
