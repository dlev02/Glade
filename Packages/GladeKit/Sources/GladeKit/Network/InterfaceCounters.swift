import Darwin
import Foundation

/// How many bytes each network interface has carried since it came up, from the
/// kernel’s 64-bit counters. The ordinary 32-bit ones wrap every 4 GB, which at a
/// gigabit is about half a minute, so they can’t be used to total a week.
public enum InterfaceCounters {
  public struct Totals: Sendable, Equatable {
    public var received: UInt64
    public var sent: UInt64
  }

  /// Physical interfaces only: Ethernet and Wi-Fi (`en…`). Tunnels, AirDrop’s own link
  /// and loopback are left out, so VPN traffic isn’t counted twice.
  public static func physical() -> [String: Totals] {
    all().filter { $0.key.hasPrefix("en") }
  }

  public static func all() -> [String: Totals] {
    var mib: [Int32] = [CTL_NET, PF_ROUTE, 0, 0, NET_RT_IFLIST2, 0]
    var length = 0
    guard sysctl(&mib, 6, nil, &length, nil, 0) == 0, length > 0 else {
      Log.warning(.network, "Interface counters couldn’t be sized: errno \(errno)")
      return [:]
    }
    var buffer = [UInt8](repeating: 0, count: length)
    guard sysctl(&mib, 6, &buffer, &length, nil, 0) == 0 else {
      Log.warning(.network, "Interface counters couldn’t be read: errno \(errno)")
      return [:]
    }
    var totals: [String: Totals] = [:]
    buffer.withUnsafeBytes { raw in
      var offset = 0
      while offset + MemoryLayout<if_msghdr>.size <= length {
        let header = raw.loadUnaligned(fromByteOffset: offset, as: if_msghdr.self)
        let size = Int(header.ifm_msglen)
        guard size > 0 else { break }
        if Int32(header.ifm_type) == RTM_IFINFO2, offset + MemoryLayout<if_msghdr2>.size <= length {
          let message = raw.loadUnaligned(fromByteOffset: offset, as: if_msghdr2.self)
          var name = [CChar](repeating: 0, count: Int(IF_NAMESIZE))
          if if_indextoname(UInt32(message.ifm_index), &name) != nil {
            let interface = String(decoding: name.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
            totals[interface] = Totals(received: message.ifm_data.ifi_ibytes, sent: message.ifm_data.ifi_obytes)
          }
        }
        offset += size
      }
    }
    return totals
  }
}
