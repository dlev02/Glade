import Foundation

/// One run of macOS’s own speed test (`networkQuality`), with what it means for the
/// things people actually do.
public struct SpeedTestResult: Codable, Sendable, Equatable, Identifiable {
  public struct Activity: Codable, Sendable, Equatable {
    public enum Rating: String, Codable, Sendable { case good, okay, poor }
    public var name: String
    public var rating: Rating
    public var sentence: String
  }

  public var id: Date { date }
  public var date: Date
  public var seconds: Double
  public var downloadMbps: Double
  public var uploadMbps: Double
  /// The round trip with nothing else going on, in milliseconds.
  public var idleLatency: Double?
  /// The round trip while the line is full, in milliseconds (from Apple’s
  /// responsiveness score). The gap to idle is what makes calls stutter while
  /// something uploads.
  public var busyLatency: Double?
  /// Apple’s responsiveness score in round trips a minute. Higher is better.
  public var responsiveness: Double?
  public var dataUsedBytes: Int64
  public var interface: String?
  /// Wi-Fi or Ethernet, and whether a VPN carried the test.
  public var medium: String?
  public var throughVPN: String?

  /// How much slower the connection gets when it’s busy.
  public var addedWhenBusy: Double? {
    guard let idleLatency, let busyLatency else { return nil }
    return max(0, busyLatency - idleLatency)
  }

  public var busySentence: String {
    guard let added = addedWhenBusy else { return "Not measured" }
    if added <= 30 { return "Barely slows down when busy" }
    if added <= 100 { return "Slows down a little when busy (+\(Int(added)) ms)" }
    return "Slows down a lot when busy (+\(Int(added)) ms), so calls and games suffer during uploads"
  }

  /// Video calls, 4K streaming, game streaming and large uploads, each rated.
  public var activities: [Activity] {
    let busy = busyLatency ?? 999
    let idle = idleLatency ?? 999
    var list: [Activity] = []
    let calls: Activity.Rating = downloadMbps >= 4 && uploadMbps >= 3 && busy <= 150 ? .good : downloadMbps >= 2 && uploadMbps >= 1.5 && busy <= 300 ? .okay : .poor
    list.append(Activity(name: "Video calls", rating: calls, sentence: calls == .good ? "Smooth" : calls == .okay ? "May stutter while something else uploads" : "Likely to break up"))
    let video: Activity.Rating = downloadMbps >= 25 ? .good : downloadMbps >= 8 ? .okay : .poor
    list.append(Activity(name: "Streaming video", rating: video, sentence: video == .good ? "4K should play" : video == .okay ? "HD plays; 4K may buffer" : "Expect buffering"))
    let games: Activity.Rating = idle <= 40 && busy <= 100 && downloadMbps >= 30 ? .good : idle <= 80 && busy <= 250 && downloadMbps >= 15 ? .okay : .poor
    list.append(Activity(name: "Game streaming", rating: games, sentence: games == .good ? "Responsive" : games == .okay ? "Playable, with some lag" : "Laggy"))
    let uploads: Activity.Rating = uploadMbps >= 50 ? .good : uploadMbps >= 10 ? .okay : .poor
    list.append(Activity(name: "Uploading", rating: uploads, sentence: uploadMbps > 0 ? "About \(Durations.phrase(8_000 / uploadMbps)) a gigabyte" : "Not measured"))
    return list
  }

  /// Reads `networkQuality -c`’s JSON. Throughput is in bits a second; latencies in
  /// milliseconds; responsiveness in round trips a minute.
  static func parse(_ text: String, date: Date, medium: String?, vpn: String?) throws -> SpeedTestResult {
    guard let json = JSONValue.parse(text) else { throw SpeedTestError.unreadable }
    if let error = json["error_code"]?.int {
      throw SpeedTestError.failed("networkQuality reported error \(error)\(json["error_domain"]?.string.map { " (\($0))" } ?? "")")
    }
    guard let download = json["dl_throughput"]?.double, let upload = json["ul_throughput"]?.double else {
      throw SpeedTestError.failed("The test didn’t report a speed. Is this Mac online?")
    }
    let rpm = json["responsiveness"]?.double
    let used = (json["dl_bytes_transferred"]?.double ?? 0) + (json["ul_bytes_transferred"]?.double ?? 0)
    let duration = max(json["dl_phase_duration"]?.double ?? 0, json["ul_phase_duration"]?.double ?? 0)
    return SpeedTestResult(
      date: date, seconds: duration, downloadMbps: download / 1_000_000, uploadMbps: upload / 1_000_000,
      idleLatency: json["base_rtt"]?.double, busyLatency: rpm.flatMap { $0 > 0 ? 60_000 / $0 : nil }, responsiveness: rpm,
      dataUsedBytes: Int64(used), interface: json["interface_name"]?.string, medium: medium, throughVPN: vpn
    )
  }
}

public enum SpeedTestError: Error, LocalizedError {
  case unreadable
  case failed(String)
  case notConnected

  public var errorDescription: String? {
    switch self {
    case .unreadable: "The speed test’s result couldn’t be read."
    case .failed(let reason): reason
    case .notConnected: "This Mac isn’t connected to a network."
    }
  }
}
