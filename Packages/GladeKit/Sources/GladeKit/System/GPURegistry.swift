import Foundation
import IOKit

/// The GPU, read from the IORegistry without privileges.
///
/// Every `IOAccelerator` publishes a `PerformanceStatistics` dictionary. On Apple silicon
/// each accelerator also has one user-client child per open Metal device, recording the
/// creating process (`IOUserClientCreator = "pid 540, WindowServer"`) and the GPU time it
/// has used (`AppUsage[].accumulatedGPUTime`, nanoseconds). Other GPUs lack `AppUsage`,
/// so per-process figures degrade to `nil` there.
final class GPURegistry: Sendable {
  /// Retained for the registry’s lifetime and released in `deinit`.
  private let accelerators: [io_service_t]
  let name: String?
  let coreCount: Int?

  init() {
    var iterator: io_iterator_t = 0
    var found: [io_service_t] = []
    let result = IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOAccelerator"), &iterator)
    if result == KERN_SUCCESS {
      var service = IOIteratorNext(iterator)
      while service != 0 {
        found.append(service)
        service = IOIteratorNext(iterator)
      }
      IOObjectRelease(iterator)
    } else {
      SystemIssues.warn("IOAccelerator", "IOServiceGetMatchingServices(IOAccelerator) failed with \(result); GPU figures unavailable")
    }
    accelerators = found
    var names: [String] = []
    for model in found.compactMap(Self.modelName) where !names.contains(model) { names.append(model) }
    name = names.isEmpty ? nil : names.joined(separator: " + ")
    let cores = found.compactMap { Self.property($0, "gpu-core-count") as? Int }
    coreCount = cores.isEmpty ? nil : cores.reduce(0, +)
  }

  deinit {
    for service in accelerators { IOObjectRelease(service) }
  }

  /// Whole-GPU utilization and memory. One registry read per accelerator.
  func stats() -> GPUStats? {
    guard !accelerators.isEmpty else { return nil }
    var utilization: Double?
    var inUse: Int64?
    var allocated: Int64?
    for service in accelerators {
      guard let stats = Self.property(service, "PerformanceStatistics") as? [String: Any] else { continue }
      if let value = (stats["Device Utilization %"] as? NSNumber)?.doubleValue {
        utilization = max(utilization ?? 0, value)
      }
      if let value = (stats["In use system memory"] as? NSNumber)?.int64Value { inUse = (inUse ?? 0) + value }
      if let value = (stats["Alloc system memory"] as? NSNumber)?.int64Value { allocated = (allocated ?? 0) + value }
    }
    if utilization == nil && inUse == nil {
      SystemIssues.warn("PerformanceStatistics", "IOAccelerator has no readable PerformanceStatistics; GPU use unavailable")
    }
    return GPUStats(name: name, coreCount: coreCount, utilizationPercent: utilization, inUseMemoryBytes: inUse, allocatedMemoryBytes: allocated)
  }

  /// Total GPU nanoseconds used so far by each process, or `nil` when this GPU doesn’t
  /// record per-process time. Costs about 1 ms for ~100 Metal clients.
  func processGPUTimes() -> [pid_t: UInt64]? {
    var totals: [pid_t: UInt64] = [:]
    var sawUsage = false
    for accelerator in accelerators {
      var iterator: io_iterator_t = 0
      let result = IORegistryEntryGetChildIterator(accelerator, kIOServicePlane, &iterator)
      guard result == KERN_SUCCESS else {
        SystemIssues.warn("IORegistryEntryGetChildIterator", "IORegistryEntryGetChildIterator on the accelerator failed with \(result); per-process GPU unavailable")
        continue
      }
      var child = IOIteratorNext(iterator)
      while child != 0 {
        if let usage = Self.property(child, "AppUsage") as? [[String: Any]] {
          sawUsage = true
          if !usage.isEmpty, let creator = Self.property(child, "IOUserClientCreator") as? String, let pid = Self.pid(fromCreator: creator) {
            let nanos = usage.reduce(UInt64(0)) { $0 + ((($1["accumulatedGPUTime"] as? NSNumber)?.uint64Value) ?? 0) }
            totals[pid, default: 0] += nanos
          }
        }
        IOObjectRelease(child)
        child = IOIteratorNext(iterator)
      }
      IOObjectRelease(iterator)
    }
    return sawUsage ? totals : nil
  }

  /// "pid 540, WindowServer" → 540.
  static func pid(fromCreator creator: String) -> pid_t? {
    guard creator.hasPrefix("pid ") else { return nil }
    let digits = creator.dropFirst(4).prefix { $0.isNumber }
    return pid_t(digits)
  }

  private static func property(_ entry: io_registry_entry_t, _ key: String) -> Any? {
    IORegistryEntryCreateCFProperty(entry, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue()
  }

  private static func modelName(_ service: io_service_t) -> String? {
    let options = IOOptionBits(kIORegistryIterateRecursively | kIORegistryIterateParents)
    let value = IORegistryEntrySearchCFProperty(service, kIOServicePlane, "model" as CFString, kCFAllocatorDefault, options)
    if let text = value as? String { return text }
    if let data = value as? Data { return String(decoding: data.prefix { $0 != 0 }, as: UTF8.self) }
    return nil
  }
}
