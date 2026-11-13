import Foundation

/// Runs macOS’s built-in speed test against Apple’s servers and keeps the last results.
/// A test fills the connection for its whole length, so at a gigabit 15 seconds uses
/// about 2 GB; it only ever runs when someone asks for it.
public enum SpeedTest {
  /// Roughly how much data a test of this length would use at the speed last measured.
  public static func estimatedBytes(seconds: Int, last: SpeedTestResult?) -> Int64? {
    guard let last else { return nil }
    let bitsPerSecond = (last.downloadMbps + last.uploadMbps) * 1_000_000
    return Int64(bitsPerSecond / 8 * Double(seconds))
  }

  public static func run(seconds: Int, path: NetworkPath) async throws -> SpeedTestResult {
    guard path.connected else { throw SpeedTestError.notConnected }
    let length = min(60, max(5, seconds))
    var arguments = ["-c", "-M", "\(length)"]
    // Measure the network itself, not a tunnel, unless a VPN carries everything anyway.
    if let interface = path.interface, !path.vpnCarriesEverything { arguments += ["-I", interface] }
    Log.info(.network, "Speed test started for up to \(length) seconds on \(path.medium.title)")
    let started = Date()
    let result: ShellResult
    do {
      result = try await Shell.run("/usr/bin/networkQuality", arguments, timeout: Double(length) + 45)
    } catch {
      Log.error(.network, "Speed test couldn’t run: \(error.localizedDescription)")
      throw SpeedTestError.failed("The speed test couldn’t run: \(error.localizedDescription)")
    }
    let vpn = path.vpnCarriesEverything ? path.vpns.first(where: \.connected)?.name ?? "a VPN" : nil
    do {
      let test = try SpeedTestResult.parse(result.stdout, date: started, medium: path.medium.title, vpn: vpn)
      Log.info(.network, "Speed test: \(Int(test.downloadMbps)) down, \(Int(test.uploadMbps)) up, idle \(test.idleLatency.map { Int($0) } ?? -1) ms, busy \(test.busyLatency.map { Int($0) } ?? -1) ms, used \(Format.bytes(test.dataUsedBytes))")
      save(test)
      return test
    } catch {
      Log.error(.network, "Speed test failed: \(error.localizedDescription); exit \(result.status)")
      throw error
    }
  }

  static var url: URL { GladePaths.support.appendingPathComponent("speed-tests.json") }

  /// Newest first, up to 50.
  public static func history() -> [SpeedTestResult] {
    (JSONFiles.read([SpeedTestResult].self, from: url) ?? []).sorted { $0.date > $1.date }
  }

  public static var last: SpeedTestResult? { history().first }

  static func save(_ result: SpeedTestResult) {
    let kept = Array(([result] + history()).prefix(50))
    do {
      try JSONFiles.write(kept, to: url)
    } catch {
      Log.warning(.network, "Couldn’t keep the speed test result: \(error.localizedDescription)")
    }
  }
}
