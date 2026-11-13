import Foundation

/// One plain answer about the connection, with the readings behind it and what to try.
public struct NetworkVerdict: Codable, Sendable, Equatable, Identifiable {
  public enum Severity: String, Codable, Sendable, Comparable {
    case good, notice, problem

    private var rank: Int {
      switch self {
      case .good: 0
      case .notice: 1
      case .problem: 2
      }
    }

    public static func < (a: Severity, b: Severity) -> Bool { a.rank < b.rank }

    /// The order verdicts are listed in: problems, then the all-clear, then notices,
    /// so a healthy connection with a heavy upload still leads with “healthy”.
    public var listOrder: Int {
      switch self {
      case .problem: 0
      case .good: 1
      case .notice: 2
      }
    }
  }

  /// Stable, so a screen or an agent can refer to it: `wifi-weak`, `upload-saturating`…
  public var id: String
  public var severity: Severity
  public var title: String
  public var detail: String
  /// The readings that led here, such as “Router: 3.1 ms, spikes to 48 ms”.
  public var evidence: [String]
  public var nextStep: String?
}
