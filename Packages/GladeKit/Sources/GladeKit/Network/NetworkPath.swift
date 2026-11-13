import Foundation
import Network

/// How this Mac reaches the internet right now: over Wi-Fi or Ethernet, whether the
/// connection is metered, the router it goes through, and any VPN or proxy in the way.
/// Everything here is read on the Mac; nothing is sent.
public struct NetworkPath: Codable, Sendable, Equatable {
  public enum Medium: String, Codable, Sendable {
    case wifi, ethernet, cellular, other, none

    public var title: String {
      switch self {
      case .wifi: "Wi-Fi"
      case .ethernet: "Ethernet"
      case .cellular: "Phone hotspot"
      case .other: "Other connection"
      case .none: "Not connected"
      }
    }
  }

  public struct VPN: Codable, Sendable, Equatable {
    public var name: String
    public var connected: Bool
  }

  public var connected: Bool
  public var medium: Medium
  /// The physical interface, such as `en0`.
  public var interface: String?
  /// A hotspot or similar that macOS treats as costly.
  public var isExpensive: Bool
  /// Low Data Mode is on for this network.
  public var isConstrained: Bool
  /// The router on the physical interface, even when a VPN carries the traffic.
  public var router: String?
  /// The interface the default route uses. A `utun` here means a VPN carries everything.
  public var defaultInterface: String?
  public var vpns: [VPN]
  /// A system-wide web proxy is set.
  public var proxy: Bool

  /// Traffic leaves through a VPN tunnel rather than the network directly.
  public var vpnCarriesEverything: Bool { defaultInterface?.hasPrefix("utun") == true || defaultInterface?.hasPrefix("ipsec") == true }

  /// A hotspot or Low Data Mode: be sparing with data.
  public var isLimited: Bool { isExpensive || isConstrained || medium == .cellular }

  public static func current() async -> NetworkPath {
    async let path = currentPath()
    async let vpns = vpnServices()
    async let proxy = proxyEnabled()
    let (nwPath, services, usesProxy) = await (path, vpns, proxy)

    var medium = Medium.none
    var physical: String?
    if let nwPath, nwPath.status == .satisfied {
      // The first physical interface in macOS’s order of preference; a VPN’s tunnel
      // (type “other”) is skipped so the network underneath is what’s described.
      if let first = nwPath.availableInterfaces.first(where: { [.wifi, .wiredEthernet, .cellular].contains($0.type) }) {
        medium = first.type == .wifi ? .wifi : first.type == .wiredEthernet ? .ethernet : .cellular
        physical = first.name
      } else {
        medium = .other
        physical = nwPath.availableInterfaces.first?.name
      }
    }
    let route = await defaultRoute()
    var router: String?
    if let physical { router = await gateway(on: physical) }
    if router == nil, let route, !(route.interface.hasPrefix("utun")) { router = route.gateway }
    return NetworkPath(
      connected: nwPath?.status == .satisfied,
      medium: medium,
      interface: physical,
      isExpensive: nwPath?.isExpensive ?? false,
      isConstrained: nwPath?.isConstrained ?? false,
      router: router,
      defaultInterface: route?.interface,
      vpns: services,
      proxy: usesProxy
    )
  }

  /// The first answer from a path monitor, or `nil` if none comes within two seconds.
  static func currentPath() async -> NWPath? {
    /// Resumes once, whichever comes first: the monitor’s answer or the deadline.
    final class Once: @unchecked Sendable {
      private let lock = NSLock()
      private var continuation: CheckedContinuation<NWPath?, Never>?

      init(_ continuation: CheckedContinuation<NWPath?, Never>) { self.continuation = continuation }

      func finish(_ value: NWPath?) {
        lock.lock()
        let pending = continuation
        continuation = nil
        lock.unlock()
        pending?.resume(returning: value)
      }
    }
    let monitor = NWPathMonitor()
    let queue = DispatchQueue(label: "glade.network.path")
    let path: NWPath? = await withCheckedContinuation { continuation in
      let once = Once(continuation)
      monitor.pathUpdateHandler = { once.finish($0) }
      monitor.start(queue: queue)
      queue.asyncAfter(deadline: .now() + 2) { once.finish(nil) }
    }
    monitor.cancel()
    return path
  }

  /// The default route’s gateway and interface, from `route`.
  static func defaultRoute() async -> (gateway: String?, interface: String)? {
    guard let result = try? await Shell.run("/sbin/route", ["-n", "get", "default"], timeout: 5, quiet: true), result.status == 0 else { return nil }
    let fields = routeFields(result.stdout)
    guard let interface = fields["interface"] else { return nil }
    return (fields["gateway"], interface)
  }

  /// The router on one interface, skipping any VPN that holds the default route.
  static func gateway(on interface: String) async -> String? {
    guard let result = try? await Shell.run("/sbin/route", ["-n", "get", "-ifscope", interface, "default"], timeout: 5, quiet: true),
      result.status == 0
    else { return nil }
    return routeFields(result.stdout)["gateway"]
  }

  static func routeFields(_ text: String) -> [String: String] {
    var fields: [String: String] = [:]
    for line in text.split(separator: "\n") {
      let parts = line.split(separator: ":", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
      if parts.count == 2 { fields[parts[0]] = parts[1] }
    }
    return fields
  }

  /// VPNs set up in System Settings, from `scutil --nc list`.
  static func vpnServices() async -> [VPN] {
    guard let result = try? await Shell.run("/usr/sbin/scutil", ["--nc", "list"], timeout: 5, quiet: true), result.status == 0 else { return [] }
    return parseVPNs(result.stdout)
  }

  /// Lines look like `* (Connected)  ID VPN (io.tailscale.ipn.macsys) "Tailscale" [VPN/…]`.
  static func parseVPNs(_ text: String) -> [VPN] {
    text.split(separator: "\n").compactMap { line -> VPN? in
      guard let open = line.firstIndex(of: "("), let close = line[open...].firstIndex(of: ")") else { return nil }
      let state = line[line.index(after: open)..<close]
      let quoted = line.split(separator: "\"")
      guard quoted.count >= 2 else { return nil }
      return VPN(name: String(quoted[1]), connected: state == "Connected")
    }
  }

  /// Whether a web proxy is switched on for the whole Mac, from `scutil --proxy`.
  static func proxyEnabled() async -> Bool {
    guard let result = try? await Shell.run("/usr/sbin/scutil", ["--proxy"], timeout: 5, quiet: true), result.status == 0 else { return false }
    let keys = ["HTTPEnable", "HTTPSEnable", "SOCKSEnable", "ProxyAutoConfigEnable"]
    return result.stdout.split(separator: "\n").contains { line in
      let parts = line.split(separator: ":").map { $0.trimmingCharacters(in: .whitespaces) }
      return parts.count == 2 && keys.contains(parts[0]) && parts[1] == "1"
    }
  }
}
