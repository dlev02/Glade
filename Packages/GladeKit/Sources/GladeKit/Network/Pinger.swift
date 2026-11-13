import Foundation

/// Measures round trips with macOS’s own `ping`, which needs no special permission.
/// Each echo is 64 bytes, so even a ping a second for an hour is about half a megabyte.
public enum Pinger {
  /// Sends a few pings in quick succession and returns each round trip, `nil` for
  /// those that never came back.
  public static func burst(_ host: String, count: Int = 8, interval: Double = 0.2) async -> [Double?] {
    guard isPlainHost(host) else { return [] }
    // One extra first: Wi-Fi in power saving answers the first ping late, which isn’t
    // what anyone feels once data is flowing.
    let arguments = ["-n", "-c", "\(count + 1)", "-i", String(interval), "-W", "1000", host]
    let deadline = Double(count + 1) * interval + 3
    guard let result = try? await Shell.run("/sbin/ping", arguments, timeout: deadline, quiet: true) else {
      Log.warning(.network, "ping \(host) couldn’t run")
      return []
    }
    return Array(replies(in: result.stdout, count: count + 1).dropFirst())
  }

  /// Reads `icmp_seq=3 ttl=57 time=6.2 ms` lines into round trips by sequence number.
  static func replies(in text: String, count: Int) -> [Double?] {
    var times = [Double?](repeating: nil, count: count)
    for line in text.split(separator: "\n") {
      guard let reply = parse(line) else { continue }
      if reply.sequence < count { times[reply.sequence] = reply.milliseconds }
    }
    return times
  }

  static func parse(_ line: Substring) -> (sequence: Int, milliseconds: Double)? {
    guard let seqRange = line.range(of: "icmp_seq="), let timeRange = line.range(of: "time=") else { return nil }
    let sequence = Int(line[seqRange.upperBound...].prefix { $0.isNumber })
    let time = Double(line[timeRange.upperBound...].prefix { $0.isNumber || $0 == "." })
    guard let sequence, let time else { return nil }
    return (sequence, time)
  }

  /// Only an address or a host name reaches `ping`, never an option.
  static func isPlainHost(_ host: String) -> Bool {
    !host.isEmpty && !host.hasPrefix("-") && host.count < 254
      && host.allSatisfy { $0.isLetter || $0.isNumber || $0 == "." || $0 == "-" || $0 == ":" }
  }

  /// One reply from a running stream: its time, or `nil` when it was lost.
  public struct Reply: Sendable {
    public var date: Date
    public var milliseconds: Double?
  }

  /// Pings once a second until the stream is cancelled. One `ping` process per host,
  /// for as long as someone is watching.
  public static func stream(_ host: String, interval: Double = 1) -> AsyncStream<Reply> {
    AsyncStream { continuation in
      guard isPlainHost(host) else {
        continuation.finish()
        return
      }
      let process = Process()
      process.executableURL = URL(fileURLWithPath: "/sbin/ping")
      process.arguments = ["-n", "-i", String(interval), "-W", "1000", host]
      let pipe = Pipe()
      process.standardOutput = pipe
      process.standardError = FileHandle.nullDevice
      final class Buffer: @unchecked Sendable {
        var text = ""
        var expected = 0
      }
      let buffer = Buffer()
      pipe.fileHandleForReading.readabilityHandler = { handle in
        let data = handle.availableData
        guard !data.isEmpty else {
          handle.readabilityHandler = nil
          continuation.finish()
          return
        }
        buffer.text += String(decoding: data, as: UTF8.self)
        while let newline = buffer.text.firstIndex(of: "\n") {
          let line = buffer.text[..<newline]
          if let reply = parse(line) {
            // Sequence numbers skipped since the last reply were lost.
            while buffer.expected < reply.sequence {
              continuation.yield(Reply(date: Date(), milliseconds: nil))
              buffer.expected += 1
            }
            continuation.yield(Reply(date: Date(), milliseconds: reply.milliseconds))
            buffer.expected = reply.sequence + 1
          } else if line.hasPrefix("Request timeout"), let sequence = Int(line.split(separator: " ").last ?? ""),
            sequence >= buffer.expected
          {
            while buffer.expected <= sequence {
              continuation.yield(Reply(date: Date(), milliseconds: nil))
              buffer.expected += 1
            }
          }
          buffer.text.removeSubrange(...newline)
        }
      }
      continuation.onTermination = { _ in
        pipe.fileHandleForReading.readabilityHandler = nil
        if process.isRunning { process.terminate() }
      }
      do {
        try process.run()
      } catch {
        Log.warning(.network, "ping \(host) couldn’t start: \(error.localizedDescription)")
        continuation.finish()
      }
    }
  }
}
