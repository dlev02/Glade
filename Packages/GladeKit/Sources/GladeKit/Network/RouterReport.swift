import Foundation

/// What the router says about itself, for routers Glade knows how to read: its line to
/// the internet provider and the devices on the network. Device names and connections
/// stay on this Mac; an AI is shown only counts.
public struct RouterReport: Codable, Sendable, Equatable {
  public struct Line: Codable, Sendable, Equatable {
    public var connected: Bool?
    /// “Fibre”, “DSL” and so on.
    public var source: String?
    /// The speed the router’s port to the provider runs at, in megabits a second.
    public var portMbps: Int?
    /// What the router has carried since it last started.
    public var received: UInt64?
    public var sent: UInt64?
    public var errors: Int?
    public var drops: Int?
  }

  public struct Device: Codable, Sendable, Equatable, Identifiable {
    public var id: String { name ?? connection + (lastActive ?? "") }
    /// The name the device gave the router, when it gave one.
    public var name: String?
    public var online: Bool
    /// “Wi-Fi 2.4 GHz”, “Wi-Fi 5 GHz” or “Ethernet”.
    public var connection: String
    /// The router’s own signal bars, 1 to 5, for Wi-Fi devices.
    public var signalBars: Int?
    /// Joined through a mesh point rather than the router itself.
    public var throughMesh: Bool?
    public var lastActive: String?
  }

  /// Such as “AT&T gateway”.
  public var kind: String
  public var maker: String?
  public var model: String?
  public var firmware: String?
  public var line: Line?
  public var devices: [Device]?
  public var read: Date

  public var online: [Device] { (devices ?? []).filter(\.online) }

  /// Online devices by how they connect, largest group first.
  public var onlineByConnection: [(connection: String, count: Int)] {
    Dictionary(grouping: online, by: \.connection).map { ($0.key, $0.value.count) }.sorted { $0.count > $1.count }
  }

  /// Online Wi-Fi devices on one or two bars.
  public var weakDevices: Int { online.filter { ($0.signalBars ?? 5) <= 2 }.count }

  public var title: String { [maker, model].compactMap { $0 }.joined(separator: " ").nonEmpty ?? kind }
}

extension String {
  var nonEmpty: String? { isEmpty ? nil : self }
}
