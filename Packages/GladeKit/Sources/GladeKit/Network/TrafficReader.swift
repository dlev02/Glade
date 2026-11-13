import Foundation

/// Reads traffic per process from macOS’s `nettop`, which needs no special permission
/// and costs a few hundredths of a second. Only traffic that leaves the Mac is counted;
/// loopback (a local server talking to a browser) is not.
public enum TrafficReader {
  /// What one process moved, with the name `nettop` gives it (shortened to fit).
  public struct Bytes: Sendable, Equatable {
    public var name: String
    public var received: UInt64
    public var sent: UInt64
  }

  /// Bytes each process moved over the next `seconds`.
  public static func perProcess(seconds: Int = 1) async -> [Int32: Bytes] {
    let arguments = ["-P", "-n", "-x", "-t", "external", "-J", "bytes_in,bytes_out", "-L", "2", "-d", "-s", "\(max(1, seconds))"]
    guard let result = try? await Shell.run("/usr/bin/nettop", arguments, timeout: Double(seconds) + 8, quiet: true), result.status == 0 else {
      if !Task.isCancelled { Log.warning(.network, "nettop couldn’t be read") }
      return [:]
    }
    let blocks = parse(result.stdout)
    return blocks.count >= 2 ? blocks[1] : [:]
  }

  /// Bytes each running process has moved since it started.
  public static func totals() async -> [Int32: Bytes] {
    let arguments = ["-P", "-n", "-x", "-t", "external", "-J", "bytes_in,bytes_out", "-L", "1"]
    guard let result = try? await Shell.run("/usr/bin/nettop", arguments, timeout: 8, quiet: true), result.status == 0 else {
      Log.warning(.network, "nettop couldn’t be read")
      return [:]
    }
    return parse(result.stdout).first ?? [:]
  }

  /// Each sample starts with a header naming the columns (`time,,bytes_in,bytes_out,`
  /// when sampling more than once, `,bytes_in,bytes_out,` otherwise); rows put the
  /// process as `name.pid` just before the byte counts.
  static func parse(_ text: String) -> [[Int32: Bytes]] {
    var blocks: [[Int32: Bytes]] = []
    var inColumn = 1
    for line in text.split(separator: "\n") {
      let fields = line.split(separator: ",", omittingEmptySubsequences: false)
      if let index = fields.firstIndex(of: "bytes_in"), index >= 1 {
        inColumn = index
        blocks.append([:])
        continue
      }
      guard !blocks.isEmpty, fields.count > inColumn + 1 else { continue }
      let process = fields[inColumn - 1]
      guard let dot = process.lastIndex(of: "."), let pid = Int32(process[process.index(after: dot)...]),
        let received = UInt64(fields[inColumn]), let sent = UInt64(fields[inColumn + 1])
      else { continue }
      blocks[blocks.count - 1][pid] = Bytes(name: String(process[..<dot]).trimmingCharacters(in: .whitespaces), received: received, sent: sent)
    }
    return blocks
  }

  /// Folds processes into the apps people recognise, the same rows as Performance,
  /// busiest first. Processes Glade can’t place keep their own names.
  public static func attribute(_ perProcess: [Int32: Bytes], apps: [AppUsage], names: [Int32: String] = [:], scale: Double = 1) -> [AppTraffic] {
    var owner: [Int32: AppUsage] = [:]
    for app in apps { for pid in app.pids { owner[pid] = app } }
    var rows: [String: AppTraffic] = [:]
    for (pid, bytes) in perProcess where bytes.received + bytes.sent > 0 {
      if let app = owner[pid] {
        rows[app.id, default: AppTraffic(id: app.id, name: app.name, bundlePath: app.bundlePath, isSystem: app.isSystem, received: 0, sent: 0)]
          .received += Double(bytes.received) * scale
        rows[app.id]?.sent += Double(bytes.sent) * scale
      } else {
        let name = names[pid] ?? (bytes.name.isEmpty ? "Process \(pid)" : bytes.name)
        let id = "process:\(name)"
        rows[id, default: AppTraffic(id: id, name: name, bundlePath: nil, isSystem: true, received: 0, sent: 0)].received += Double(bytes.received) * scale
        rows[id]?.sent += Double(bytes.sent) * scale
      }
    }
    return rows.values.sorted { $0.total > $1.total }
  }

  /// Traffic by app over the next `seconds`, as bytes a second.
  public static func now(seconds: Int = 1, sampler: SystemSampler = SystemSampler()) async -> [AppTraffic] {
    async let traffic = perProcess(seconds: seconds)
    async let processes = sampler.processes()
    let (bytes, listed) = await (traffic, processes)
    let apps = AppGrouper.group(listed)
    let names = Dictionary(listed.map { ($0.pid, $0.name) }, uniquingKeysWith: { first, _ in first })
    return attribute(bytes, apps: apps, names: names, scale: 1 / Double(max(1, seconds)))
  }
}
