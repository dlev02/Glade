import Darwin
import Foundation
import IOKit.ps

/// Cumulative tick counters for one core since boot.
struct CoreTicks: Sendable {
  var user: UInt32
  var system: UInt32
  var idle: UInt32
  var nice: UInt32
}

/// Readers for the Mach host, sysctl and power-source APIs. Each is a handful of
/// system calls with no allocation beyond the result.
enum HostReader {
  private static let host = mach_host_self()
  static let pageSize = Sysctl.integer("hw.pagesize") ?? 16_384
  static let totalMemory = Sysctl.integer("hw.memsize") ?? 0
  static let logicalCores = Int(Sysctl.integer("hw.logicalcpu") ?? Int64(ProcessInfo.processInfo.activeProcessorCount))
  static let performanceCores = Sysctl.integer("hw.perflevel0.logicalcpu").map(Int.init)
  static let efficiencyCores = Sysctl.integer("hw.perflevel1.logicalcpu").map(Int.init)

  // MARK: Processor

  static func coreTicks() -> [CoreTicks]? {
    var count: natural_t = 0
    var info: processor_info_array_t?
    var infoCount: mach_msg_type_number_t = 0
    let result = host_processor_info(host, PROCESSOR_CPU_LOAD_INFO, &count, &info, &infoCount)
    guard result == KERN_SUCCESS, let info else {
      SystemIssues.warn("host_processor_info", "host_processor_info(PROCESSOR_CPU_LOAD_INFO) failed with \(result); processor use reads as 0")
      return nil
    }
    defer {
      vm_deallocate(mach_task_self_, vm_address_t(UInt(bitPattern: info)), vm_size_t(Int(infoCount) * MemoryLayout<integer_t>.stride))
    }
    let states = Int(CPU_STATE_MAX)
    var cores: [CoreTicks] = []
    cores.reserveCapacity(Int(count))
    for core in 0..<Int(count) {
      let base = core * states
      guard base + states <= Int(infoCount) else { break }
      cores.append(CoreTicks(
        user: UInt32(bitPattern: info[base + Int(CPU_STATE_USER)]),
        system: UInt32(bitPattern: info[base + Int(CPU_STATE_SYSTEM)]),
        idle: UInt32(bitPattern: info[base + Int(CPU_STATE_IDLE)]),
        nice: UInt32(bitPattern: info[base + Int(CPU_STATE_NICE)])
      ))
    }
    return cores
  }

  /// Usage between two tick readings. Counters are 32-bit and wrap, so differences use
  /// wrapping subtraction.
  static func cpu(from previous: [CoreTicks]?, to current: [CoreTicks]?) -> CPUStats {
    var perCore: [Double] = []
    var user: UInt64 = 0, system: UInt64 = 0, total: UInt64 = 0
    if let previous, let current, previous.count == current.count {
      perCore.reserveCapacity(current.count)
      for (old, new) in zip(previous, current) {
        let u = UInt64(new.user &- old.user) + UInt64(new.nice &- old.nice)
        let s = UInt64(new.system &- old.system)
        let i = UInt64(new.idle &- old.idle)
        let all = u + s + i
        perCore.append(all > 0 ? Double(u + s) / Double(all) * 100 : 0)
        user += u
        system += s
        total += all
      }
    } else {
      perCore = Array(repeating: 0, count: current?.count ?? logicalCores)
    }
    var loads = [Double](repeating: 0, count: 3)
    if getloadavg(&loads, 3) != 3 { loads = [] }
    let userPercent = total > 0 ? Double(user) / Double(total) * 100 : 0
    let systemPercent = total > 0 ? Double(system) / Double(total) * 100 : 0
    return CPUStats(
      totalPercent: userPercent + systemPercent, userPercent: userPercent, systemPercent: systemPercent,
      perCorePercent: perCore, logicalCores: logicalCores, performanceCores: performanceCores,
      efficiencyCores: efficiencyCores, loadAverage: loads
    )
  }

  // MARK: Memory

  static func memory() -> MemoryStats {
    var stats = vm_statistics64_data_t()
    var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
    let result = withUnsafeMutablePointer(to: &stats) { pointer in
      pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
        host_statistics64(host, HOST_VM_INFO64, $0, &count)
      }
    }
    var swap = xsw_usage()
    let haveSwap = Sysctl.read("vm.swapusage", into: &swap)
    if !haveSwap { SystemIssues.warn("vm.swapusage", "sysctl vm.swapusage failed (errno \(errno)); swap reads as 0") }
    let pressure: MemoryPressure =
      switch Sysctl.integer("kern.memorystatus_vm_pressure_level") {
      case 4: .critical
      case 2: .warning
      default: .normal
      }
    let freePercent = Sysctl.integer("kern.memorystatus_level").map(Int.init)

    guard result == KERN_SUCCESS else {
      SystemIssues.warn("host_statistics64", "host_statistics64(HOST_VM_INFO64) failed with \(result); memory breakdown unavailable")
      return MemoryStats(
        totalBytes: totalMemory, usedBytes: 0, appBytes: 0, wiredBytes: 0, compressedBytes: 0,
        cachedFilesBytes: 0, freeBytes: 0, swapUsedBytes: Int64(swap.xsu_used), swapTotalBytes: Int64(swap.xsu_total),
        pressure: pressure, freePercent: freePercent
      )
    }
    let page = pageSize
    let internalPages = Int64(stats.internal_page_count)
    let purgeable = Int64(stats.purgeable_count)
    let app = max(0, internalPages - purgeable) * page
    let wired = Int64(stats.wire_count) * page
    let compressed = Int64(stats.compressor_page_count) * page
    let cached = (Int64(stats.external_page_count) + purgeable) * page
    let free = max(0, Int64(stats.free_count) - Int64(stats.speculative_count)) * page
    return MemoryStats(
      totalBytes: totalMemory, usedBytes: app + wired + compressed, appBytes: app, wiredBytes: wired,
      compressedBytes: compressed, cachedFilesBytes: cached, freeBytes: free,
      swapUsedBytes: Int64(swap.xsu_used), swapTotalBytes: Int64(swap.xsu_total),
      pressure: pressure, freePercent: freePercent
    )
  }

  // MARK: Power and uptime

  static func power() -> PowerStats {
    let lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
    guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue() else {
      SystemIssues.warn("IOPSCopyPowerSourcesInfo", "IOPSCopyPowerSourcesInfo returned nothing; assuming mains power")
      return PowerStats(onBattery: false, hasBattery: false, batteryPercent: nil, isCharging: nil, lowPowerMode: lowPower)
    }
    let providing = IOPSGetProvidingPowerSourceType(info)?.takeUnretainedValue() as String?
    var hasBattery = false
    var percent: Int?
    var charging: Bool?
    let sources = (IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as [AnyObject]?) ?? []
    for source in sources {
      guard
        let description = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any],
        description[kIOPSTypeKey] as? String == kIOPSInternalBatteryType
      else { continue }
      hasBattery = true
      if let current = description[kIOPSCurrentCapacityKey] as? Int,
        let maximum = description[kIOPSMaxCapacityKey] as? Int, maximum > 0
      {
        percent = Int((Double(current) / Double(maximum) * 100).rounded())
      }
      charging = description[kIOPSIsChargingKey] as? Bool
    }
    return PowerStats(
      onBattery: providing == kIOPSBatteryPowerValue, hasBattery: hasBattery,
      batteryPercent: percent, isCharging: charging, lowPowerMode: lowPower
    )
  }

  static let bootDate: Date? = {
    var boot = timeval()
    guard Sysctl.read("kern.boottime", into: &boot), boot.tv_sec > 0 else {
      SystemIssues.warn("kern.boottime", "sysctl kern.boottime failed (errno \(errno)); uptime uses the process clock")
      return nil
    }
    return Date(timeIntervalSince1970: Double(boot.tv_sec) + Double(boot.tv_usec) / 1_000_000)
  }()
}
