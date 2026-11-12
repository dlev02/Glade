import Foundation

/// Finds the throwaway simulators Xcode makes: clones for running tests in parallel and
/// devices for SwiftUI previews. Each one is its own finding, so a clone Xcode used
/// today doesn’t hold back the ones it hasn’t touched in days.
public struct SimulatorCloneScanner: StorageScanner {
  public let id = "simulator-clones"
  public let title = "Test and preview simulators"

  public init() {}

  /// A set of throwaway simulators, as `simctl --set` names it.
  struct CloneSet: Sendable {
    /// `testing` or `previews`, the names `simctl --set` accepts for Xcode’s own sets.
    var name: String
    var ruleID: String
    var title: String
    var detail: String
    /// The set’s folder, relative to the home folder.
    var folder: String
  }

  static let sets: [CloneSet] = [
    CloneSet(
      name: "testing", ruleID: "xcode.testdevices", title: "Test simulator",
      detail: "A copy of a simulator Xcode made to run tests in parallel. Xcode makes a fresh one the next time tests run.",
      folder: "Library/Developer/XCTestDevices"
    ),
    CloneSet(
      name: "previews", ruleID: "xcode.previews", title: "Preview simulator",
      detail: "A simulator Xcode keeps for SwiftUI previews. Xcode makes a fresh one the next time a preview runs.",
      folder: "Library/Developer/Xcode/UserData/Previews/Simulator Devices"
    ),
  ]

  /// The folder a clone lives in, which is the only path its finding may name.
  static func folder(set name: String, udid: String, home: String) -> String? {
    guard let set = sets.first(where: { $0.name == name }), UUID(uuidString: udid) != nil else { return nil }
    return "\(home)/\(set.folder)/\(udid)"
  }

  /// Leave out clones smaller than this; Watch clones that never ran are a few kilobytes.
  static let minimumBytes: Int64 = 5_000_000
  /// As for Xcode’s build data: Careful waits three days, Balanced one, Aggressive none.
  static let idleDays = 3

  struct DeviceList: Decodable {
    var devices: [String: [Device]]
  }

  struct Device: Decodable {
    var udid: String
    var name: String
    var state: String?
    var isAvailable: Bool?
    var dataPath: String?
    var lastBootedAt: String?
  }

  public func scan(_ context: ScanContext) async -> [Finding] {
    guard !context.config.ignoredCategories.contains(.simulators), Shell.which("xcrun") != nil else { return [] }
    var findings: [Finding] = []
    for set in Self.sets {
      if context.cancel.isCancelled { break }
      findings += await scan(set, context)
    }
    return findings
  }

  private func scan(_ set: CloneSet, _ context: ScanContext) async -> [Finding] {
    let root = "\(context.home)/\(set.folder)"
    guard FileManager.default.fileExists(atPath: root), context.protection.canScan(root) else { return [] }
    guard let list = await Self.list(set: set.name) else { return [] }

    let dateParser = ISO8601DateFormatter()
    var findings: [Finding] = []
    var listed = Set<String>()
    for (runtime, devices) in list.devices {
      for device in devices {
        guard UUID(uuidString: device.udid) != nil else { continue }
        listed.insert(device.udid.uppercased())
        let folder = "\(root)/\(device.udid)"
        guard FileManager.default.fileExists(atPath: folder), context.protection.canScan(folder) else { continue }
        if context.cancel.isCancelled { return findings }
        // Simulators hold a photo library of their own, which doesn’t make them a library.
        let measure = await context.measure([folder], checkingLibraries: false)
        guard measure.bytes >= Self.minimumBytes, !measure.cancelled else { continue }

        let running = (device.state ?? "Shutdown") != "Shutdown"
        let lastBoot = device.lastBootedAt.flatMap { dateParser.date(from: $0) }
        let lastUsed = [lastBoot, measure.newestModification].compactMap { $0 }.max()
        var blockers: [Blocker] = []
        if running { blockers.append(Blocker(.inUse, "This simulator is running.")) }
        let verdict = context.protection.verdict(forRemoving: folder)
        if !verdict.isAllowed { blockers.append(Blocker(.inUse, verdict.explanation)) }

        var evidence: [String] = []
        if let days = context.days(since: lastUsed) {
          evidence.append(days == 0 ? "Last used today." : "Last used \(Format.age(lastUsed, now: context.now)).")
        }
        if device.isAvailable == false { evidence.append("Its system version is no longer installed.") }
        if measure.unreadable > 0 {
          evidence.append("\(measure.unreadable) items couldn’t be read, so the real size may be larger.")
        }

        findings.append(Finding(
          id: Finding.makeID(rule: set.ruleID, path: device.udid), ruleID: set.ruleID, category: .simulators,
          title: "\(set.title) · \(Self.deviceName(device.name)) · \(SimulatorScanner.runtimeName(runtime))",
          detail: set.detail, paths: [folder], bytes: measure.bytes, fileCount: measure.files, lastUsed: lastUsed,
          recovery: .automatic, risk: .safe, owner: Catalog.xcode_, blockers: blockers,
          method: .simulatorSet(name: set.name, udid: device.udid), evidence: evidence,
          autoLevel: blockers.isEmpty ? .careful : nil, idleDaysRequired: Self.idleDays
        ))
      }
    }

    // Folders `simctl` doesn’t list aren’t devices it can delete. Xcode leaves empty
    // ones behind; they’re noted in the log rather than offered.
    let strays = DiskWalk.children(of: root).filter { path in
      let name = (path as NSString).lastPathComponent
      return UUID(uuidString: name) != nil && !listed.contains(name.uppercased())
    }
    if !strays.isEmpty {
      let measure = await context.measure(strays, checkingLibraries: false)
      Log.debug(.scan, "\(set.name) simulator set: \(strays.count) folders simctl doesn’t list (\(Format.bytes(measure.bytes))), left alone")
    }
    return findings
  }

  static func list(set: String) async -> DeviceList? {
    do {
      let result = try await Shell.run("xcrun", ["simctl", "--set", set, "list", "devices", "-j"], timeout: 30, quiet: true)
      guard result.succeeded else {
        Log.warning(.scan, "simctl list for the \(set) set failed (exit \(result.status)): \(result.stderr.prefix(200))")
        return nil
      }
      return try JSONDecoder().decode(DeviceList.self, from: Data(result.stdout.utf8))
    } catch {
      Log.warning(.scan, "Couldn’t read the \(set) simulator list: \(error)")
      return nil
    }
  }

  /// "Clone 2 of iPhone 17" → "iPhone 17"
  static func deviceName(_ name: String) -> String {
    guard name.hasPrefix("Clone "), let range = name.range(of: " of ") else { return name }
    let number = name[name.index(name.startIndex, offsetBy: 6)..<range.lowerBound]
    return number.allSatisfy(\.isNumber) && !number.isEmpty ? String(name[range.upperBound...]) : name
  }

  /// Why one clone mustn’t be deleted right now, from the set’s current listing, or
  /// `nil` when it may be. Only a listed, shut-down device whose folder is the one the
  /// scan measured qualifies.
  static func refusal(udid: String, folder: String, listing: DeviceList) -> String? {
    let devices = listing.devices.values.flatMap { $0 }
    guard let device = devices.first(where: { $0.udid.caseInsensitiveCompare(udid) == .orderedSame }) else {
      return "Xcode no longer lists this simulator."
    }
    if let state = device.state, state != "Shutdown" { return "This simulator is running." }
    if device.state == nil { return "Couldn’t tell whether this simulator is running." }
    if let dataPath = device.dataPath, !Protection.clean(dataPath).hasPrefix(Protection.clean(folder) + "/") {
      return "This simulator belongs to a different set."
    }
    return nil
  }
}
