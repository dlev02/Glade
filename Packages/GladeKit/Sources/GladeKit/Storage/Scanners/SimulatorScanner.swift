import Foundation

/// Finds iOS, watchOS, tvOS and visionOS simulators: ones that no longer work because
/// their system version is gone, and ones holding a lot of app data.
public struct SimulatorScanner: StorageScanner {
  public let id = "simulators"
  public let title = "Simulators"

  public init() {}

  private struct DeviceList: Decodable {
    var devices: [String: [Device]]
  }

  private struct Device: Decodable {
    var udid: String
    var name: String
    var state: String?
    var isAvailable: Bool?
    var dataPath: String?
    var lastBootedAt: String?
  }

  public func scan(_ context: ScanContext) async -> [Finding] {
    guard !context.config.ignoredCategories.contains(.simulators) else { return [] }
    let root = context.home + "/Library/Developer/CoreSimulator/Devices"
    guard FileManager.default.fileExists(atPath: root), Shell.which("xcrun") != nil else { return [] }

    let list: DeviceList
    do {
      let result = try await Shell.run("xcrun", ["simctl", "list", "devices", "-j"], timeout: 30, quiet: true)
      guard result.succeeded else {
        Log.warning(.scan, "simctl list failed (exit \(result.status)): \(result.stderr.prefix(200))")
        return []
      }
      list = try JSONDecoder().decode(DeviceList.self, from: Data(result.stdout.utf8))
    } catch {
      Log.warning(.scan, "Couldn’t read the simulator list: \(error)")
      return []
    }

    var findings: [Finding] = await runtimes(devices: list.devices, context: context)
    var unavailable: [(Device, String)] = []
    let dateParser = ISO8601DateFormatter()

    for (runtime, devices) in list.devices {
      for device in devices {
        let folder = "\(root)/\(device.udid)"
        guard FileManager.default.fileExists(atPath: folder), context.protection.canScan(folder) else { continue }
        if device.isAvailable == false {
          unavailable.append((device, folder))
          continue
        }
        if context.cancel.isCancelled { return findings }
        let measure = await context.measure([folder])
        guard measure.bytes >= 200_000_000 else { continue }
        let booted = device.state == "Booted"
        let lastBoot = device.lastBootedAt.flatMap { dateParser.date(from: $0) }
        let lastUsed = [lastBoot, measure.newestModification].compactMap { $0 }.max()
        var evidence = ["Holds \(Format.bytes(measure.bytes)) of installed apps and their data."]
        if let lastBoot { evidence.append("Last started \(Format.age(lastBoot, now: context.now)).") }
        findings.append(Finding(
          id: Finding.makeID(rule: "sim.device", path: device.udid), ruleID: "sim.device", category: .simulators,
          title: "\(device.name) · \(Self.runtimeName(runtime))",
          detail: "Apps and data inside this simulator. Erasing it keeps the simulator and returns it to a fresh state; apps reinstall when you next run them from Xcode.",
          paths: [folder], bytes: measure.bytes, fileCount: measure.files, lastUsed: lastUsed,
          recovery: .reinstall, risk: .caution, owner: Catalog.simulator,
          blockers: booted ? [Blocker(.inUse, "This simulator is running.")] : [],
          method: .simulatorErase(udid: device.udid), evidence: evidence,
          autoLevel: booted ? nil : .balanced, idleDaysRequired: 14
        ))
      }
    }

    if !unavailable.isEmpty {
      let folders = unavailable.map(\.1)
      let measure = await context.measure(folders)
      if measure.bytes >= 1_000_000 {
        let names = unavailable.prefix(4).map { $0.0.name }.joined(separator: ", ")
        findings.append(Finding(
          id: Finding.makeID(rule: "sim.unavailable", path: root), ruleID: "sim.unavailable", category: .simulators,
          title: "Unavailable simulators (\(unavailable.count))",
          detail: "Simulators whose system version is no longer installed. They can't be started, so nothing is lost by removing them.",
          paths: folders, bytes: measure.bytes, fileCount: measure.files, lastUsed: measure.newestModification,
          recovery: .automatic, risk: .safe, owner: Catalog.simulator, method: .unavailableSimulators,
          evidence: ["Includes \(names)\(unavailable.count > 4 ? " and \(unavailable.count - 4) more" : "")."],
          autoLevel: .careful, idleDaysRequired: 0
        ))
      }
    }
    return findings
  }

  private struct Runtime: Decodable {
    var identifier: String
    var runtimeIdentifier: String?
    var version: String?
    var build: String?
    var state: String?
    var deletable: Bool?
    var sizeBytes: Int64?
    var lastUsedAt: String?
  }

  /// Downloaded simulator system versions. One that no simulator uses is dead weight;
  /// the rest are listed for a person to choose.
  private func runtimes(devices: [String: [Device]], context: ScanContext) async -> [Finding] {
    let list: [String: Runtime]
    do {
      let result = try await Shell.run("xcrun", ["simctl", "runtime", "list", "-j"], timeout: 30, quiet: true)
      guard result.succeeded else { return [] }
      list = try JSONDecoder().decode([String: Runtime].self, from: Data(result.stdout.utf8))
    } catch {
      Log.warning(.scan, "Couldn’t read the simulator runtime list: \(error)")
      return []
    }
    let dateParser = ISO8601DateFormatter()
    var findings: [Finding] = []
    for runtime in list.values {
      guard runtime.state == "Ready", runtime.deletable == true, let bytes = runtime.sizeBytes, bytes > 100_000_000,
            UUID(uuidString: runtime.identifier) != nil, let runtimeID = runtime.runtimeIdentifier else { continue }
      let users = devices[runtimeID]?.filter { $0.isAvailable != false } ?? []
      let lastUsed = runtime.lastUsedAt.flatMap { dateParser.date(from: $0) }
      let name = "\(Self.runtimeName(runtimeID)) (\(runtime.build ?? "?"))"
      var evidence: [String] = []
      evidence.append(users.isEmpty ? "No simulator uses this version." : "\(users.count) simulators use this version.")
      evidence.append(lastUsed.map { "Last used \(Format.age($0, now: context.now))." } ?? "Never used since it was installed.")
      let unused = users.isEmpty
      findings.append(Finding(
        id: Finding.makeID(rule: "sim.runtime", path: runtime.identifier), ruleID: "sim.runtime", category: .simulators,
        title: "Simulator system · \(name)",
        detail: unused
          ? "A downloaded simulator system version that none of your simulators use. Xcode offers to download it again if you ever add one."
          : "A downloaded simulator system version. Removing it makes the simulators that use it unavailable until Xcode downloads it again.",
        paths: [], bytes: bytes, lastUsed: lastUsed, recovery: .redownload, risk: .caution, owner: Catalog.simulator,
        method: .simulatorRuntime(identifier: runtime.identifier), evidence: evidence,
        autoLevel: unused ? .balanced : nil, idleDaysRequired: unused ? 0 : 30
      ))
    }
    return findings
  }

  /// "com.apple.CoreSimulator.SimRuntime.iOS-27-0" → "iOS 27.0"
  static func runtimeName(_ identifier: String) -> String {
    guard let last = identifier.split(separator: ".").last else { return identifier }
    let parts = last.split(separator: "-")
    guard let platform = parts.first else { return identifier }
    return "\(platform) \(parts.dropFirst().joined(separator: "."))"
  }
}
