import Darwin
import Foundation
import Synchronization

/// Reads kernel values by name.
enum Sysctl {
  /// An integer value, whether the kernel stores it in four bytes or eight.
  static func integer(_ name: String) -> Int64? {
    var raw: UInt64 = 0
    var size = MemoryLayout<UInt64>.size
    guard sysctlbyname(name, &raw, &size, nil, 0) == 0 else { return nil }
    switch size {
    case 4: return Int64(Int32(truncatingIfNeeded: raw))
    case 8: return Int64(bitPattern: raw)
    default: return nil
    }
  }

  /// A fixed-size structure such as `xsw_usage` or `timeval`.
  static func read<T: BitwiseCopyable>(_ name: String, into value: inout T) -> Bool {
    var size = MemoryLayout<T>.size
    return withUnsafeMutableBytes(of: &value) { sysctlbyname(name, $0.baseAddress, &size, nil, 0) } == 0
  }
}

/// Logs each kind of system-call failure once per run, so a reader that fails every
/// few seconds doesn’t flood the log.
enum SystemIssues {
  private static let seen = Mutex<Set<String>>([])

  static func warn(_ key: String, _ message: @autoclosure () -> String) {
    let first = seen.withLock { $0.insert(key).inserted }
    if first { Log.warning(.system, message()) }
  }
}

enum MachTime {
  /// Nanoseconds per Mach absolute-time tick: 1 on Intel, 125/3 on Apple silicon.
  static let nanosPerTick: Double = {
    var info = mach_timebase_info_data_t()
    guard mach_timebase_info(&info) == KERN_SUCCESS, info.denom != 0 else { return 1 }
    return Double(info.numer) / Double(info.denom)
  }()

  static func nanos(fromTicks ticks: UInt64) -> UInt64 {
    UInt64(Double(ticks) * nanosPerTick)
  }

  /// A clock that stops while the Mac sleeps, like the CPU counters it’s compared with.
  static func now() -> UInt64 { clock_gettime_nsec_np(CLOCK_UPTIME_RAW) }
}

enum CText {
  /// A string from a fixed-size C character array imported as a tuple.
  static func string<T>(_ tuple: T) -> String {
    withUnsafeBytes(of: tuple) { raw in
      String(decoding: raw.prefix { $0 != 0 }, as: UTF8.self)
    }
  }
}

enum Durations {
  /// "45 minutes", "3 hours", "2 days".
  static func phrase(_ seconds: TimeInterval) -> String {
    let minutes = Int(seconds / 60)
    if minutes < 2 { return "a minute" }
    if minutes < 90 { return "\(minutes) minutes" }
    let hours = Int((Double(minutes) / 60).rounded())
    if hours < 48 { return "\(hours) hours" }
    return "\(Int((Double(hours) / 24).rounded())) days"
  }
}
