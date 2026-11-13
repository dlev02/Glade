import Foundation

/// One app’s use of the network: how fast it’s receiving and sending right now, or
/// how much it moved over a period.
public struct AppTraffic: Codable, Sendable, Identifiable, Equatable {
  /// The same identifier as the app’s row elsewhere in Glade.
  public var id: String
  public var name: String
  public var bundlePath: String?
  public var isSystem: Bool
  /// Bytes a second, or bytes in total for a period.
  public var received: Double
  public var sent: Double

  public var total: Double { received + sent }
}
