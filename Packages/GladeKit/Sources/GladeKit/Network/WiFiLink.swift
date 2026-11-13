import CoreWLAN
import Foundation

/// The Wi-Fi connection this Mac has right now: how strong and clean the signal is, the
/// band and channel, and the rate the Mac and the access point agreed on. Read from
/// CoreWLAN, which needs no permission for these. The network’s name and the access
/// point’s identifier come only with Location access; they stay on this Mac.
public struct WiFiLink: Codable, Sendable, Equatable {
  public enum Quality: String, Codable, Sendable, Comparable {
    case excellent, good, fair, weak

    public var title: String {
      switch self {
      case .excellent: "Excellent"
      case .good: "Good"
      case .fair: "Fair"
      case .weak: "Weak"
      }
    }

    private var rank: Int {
      switch self {
      case .excellent: 3
      case .good: 2
      case .fair: 1
      case .weak: 0
      }
    }

    public static func < (a: Quality, b: Quality) -> Bool { a.rank < b.rank }
  }

  public var interface: String
  /// Signal strength in dBm, such as −55. Nearer zero is stronger.
  public var rssi: Int
  /// Background noise in dBm, such as −94.
  public var noise: Int?
  /// “2.4 GHz”, “5 GHz” or “6 GHz”.
  public var band: String?
  public var channel: Int?
  public var widthMHz: Int?
  /// The Wi-Fi generation in everyday terms, such as “Wi-Fi 6”.
  public var generation: String?
  /// The rate the Mac and the access point agreed on, in megabits a second. The
  /// most the link could carry, not what the internet delivers.
  public var linkRateMbps: Double?
  public var security: String?
  /// Only with Location access. Never sent to an AI.
  public var networkName: String?
  /// The access point’s radio, only with Location access. Never sent to an AI.
  public var accessPoint: String?

  /// Signal above the noise, in dB. 25 or more is comfortable; under 15 drops data.
  public var signalToNoise: Int? { noise.map { rssi - $0 } }

  public var quality: Quality {
    var quality: Quality = rssi >= -60 ? .excellent : rssi >= -67 ? .good : rssi >= -75 ? .fair : .weak
    if let snr = signalToNoise {
      if snr < 15 { quality = min(quality, .weak) } else if snr < 22 { quality = min(quality, .fair) }
    }
    return quality
  }

  /// One line a person understands, such as “Good signal on 5 GHz (Wi-Fi 6)”.
  public var sentence: String {
    var text = "\(quality.title) signal"
    if let band { text += " on \(band)" }
    if let generation { text += " (\(generation))" }
    return text
  }

  /// The current connection, or `nil` when Wi-Fi is off or not joined.
  public static func current() -> WiFiLink? {
    guard let interface = CWWiFiClient.shared().interface(), interface.powerOn() else { return nil }
    let rssi = interface.rssiValue()
    // An interface that isn't joined reports zero signal and no channel.
    guard rssi != 0, let channel = interface.wlanChannel() else { return nil }
    let noise = interface.noiseMeasurement()
    let rate = interface.transmitRate()
    return WiFiLink(
      interface: interface.interfaceName ?? "en0",
      rssi: rssi,
      noise: noise == 0 ? nil : noise,
      band: band(channel.channelBand),
      channel: channel.channelNumber,
      widthMHz: width(channel.channelWidth),
      generation: generation(interface.activePHYMode(), band: channel.channelBand),
      linkRateMbps: rate > 0 ? rate : nil,
      security: security(interface.security()),
      networkName: interface.ssid(),
      accessPoint: interface.bssid()
    )
  }

  static func band(_ band: CWChannelBand) -> String? {
    switch band {
    case .band2GHz: "2.4 GHz"
    case .band5GHz: "5 GHz"
    case .band6GHz: "6 GHz"
    default: nil
    }
  }

  static func width(_ width: CWChannelWidth) -> Int? {
    switch width {
    case .width20MHz: 20
    case .width40MHz: 40
    case .width80MHz: 80
    case .width160MHz: 160
    default: width.rawValue == 5 ? 320 : nil
    }
  }

  static func generation(_ mode: CWPHYMode, band: CWChannelBand) -> String? {
    // Raw values, so a newer mode on a newer macOS still reads.
    switch mode.rawValue {
    case 1, 2, 3: "older Wi-Fi"
    case 4: "Wi-Fi 4"
    case 5: "Wi-Fi 5"
    case 6: band == .band6GHz ? "Wi-Fi 6E" : "Wi-Fi 6"
    case 7: "Wi-Fi 7"
    default: nil
    }
  }

  static func security(_ security: CWSecurity) -> String? {
    switch security {
    case .none: "Open"
    case .WEP, .dynamicWEP: "WEP (outdated)"
    case .wpaPersonal, .wpaPersonalMixed, .wpaEnterprise, .wpaEnterpriseMixed: "WPA (outdated)"
    case .wpa2Personal, .personal: "WPA2"
    case .wpa2Enterprise, .enterprise: "WPA2 Enterprise"
    case .wpa3Personal, .wpa3Transition: "WPA3"
    case .wpa3Enterprise: "WPA3 Enterprise"
    case .OWE, .oweTransition: "Enhanced Open"
    default: nil
    }
  }
}
