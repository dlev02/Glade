import Foundation

/// The three places latency is measured, so a slowdown can be placed: the router (your
/// Wi-Fi or cable), the internet provider’s first hop (your line), and a host on the
/// wider internet (everything beyond).
public struct NetworkTargets: Codable, Sendable, Equatable {
  public enum Kind: String, Codable, Sendable, CaseIterable {
    case router, provider, internet

    public var title: String {
      switch self {
      case .router: "Router"
      case .provider: "Provider"
      case .internet: "Internet"
      }
    }

    /// What a slow reading here points at.
    public var meaning: String {
      switch self {
      case .router: "your Wi-Fi or cable to the router"
      case .provider: "your line to the internet provider"
      case .internet: "the wider internet"
      }
    }
  }

  public var router: String?
  /// The first public address past the router, from `traceroute`.
  public var provider: String?
  public var internet: String
  /// The router these were found through, so they’re found again on another network.
  public var foundVia: String?
  public var found: Date

  public func host(_ kind: Kind) -> String? {
    switch kind {
    case .router: router
    case .provider: provider
    case .internet: internet
    }
  }

  static var url: URL { GladePaths.support.appendingPathComponent("network-targets.json") }

  /// The targets for the network the Mac is on, worked out again when the router or
  /// the internet host changes, or after a day.
  public static func current(path: NetworkPath, internetHost: String, now: Date = Date()) async -> NetworkTargets {
    if let saved = JSONFiles.read(NetworkTargets.self, from: url), saved.foundVia == path.router, saved.internet == internetHost,
      now.timeIntervalSince(saved.found) < 86_400
    {
      return saved
    }
    var targets = NetworkTargets(router: path.router, provider: nil, internet: internetHost, foundVia: path.router, found: now)
    if path.connected, path.router != nil {
      targets.provider = await firstPublicHop(toward: internetHost, router: path.router)
    }
    do {
      try JSONFiles.write(targets, to: url)
    } catch {
      Log.warning(.network, "Couldn’t save the latency targets: \(error.localizedDescription)")
    }
    Log.info(.network, "Latency targets: router \(targets.router ?? "none"), provider \(targets.provider == nil ? "not found" : "found"), internet \(internetHost)")
    return targets
  }

  /// Follows the route a few hops and takes the first address that isn’t private.
  static func firstPublicHop(toward host: String, router: String?) async -> String? {
    guard Pinger.isPlainHost(host),
      let result = try? await Shell.run("/usr/sbin/traceroute", ["-n", "-m", "5", "-q", "1", "-w", "1", host], timeout: 12, quiet: true)
    else { return nil }
    for line in result.stdout.split(separator: "\n") {
      let fields = line.split(separator: " ", omittingEmptySubsequences: true)
      guard fields.count >= 2, Int(fields[0]) != nil else { continue }
      let address = String(fields[1])
      guard address != "*", address != router, address != host, !isPrivate(address) else { continue }
      return address
    }
    return nil
  }

  /// Home, office and carrier-grade private ranges, and link-local.
  static func isPrivate(_ address: String) -> Bool {
    let parts = address.split(separator: ".").compactMap { Int($0) }
    guard parts.count == 4 else {
      // IPv6 link-local and unique local addresses; a host name is never private here.
      guard address.contains(":") else { return false }
      let lowered = address.lowercased()
      return lowered.hasPrefix("fe80:") || lowered.hasPrefix("fd") || lowered.hasPrefix("fc")
    }
    switch (parts[0], parts[1]) {
    case (10, _), (127, _), (169, 254), (192, 168): return true
    case (172, 16...31): return true
    case (100, 64...127): return true
    default: return false
    }
  }
}
