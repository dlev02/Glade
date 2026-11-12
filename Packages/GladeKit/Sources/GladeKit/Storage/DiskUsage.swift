import Foundation

/// One place on the disk and the space it takes, with the biggest things inside it.
public struct UsageNode: Codable, Sendable, Identifiable, Hashable {
  /// The path, or a fixed key for something that has none (macOS's own volumes).
  public var id: String
  public var title: String
  public var path: String?
  public var bytes: Int64
  /// The biggest things inside, largest first. Small ones are left out, so these can
  /// add up to less than `bytes`.
  public var children: [UsageNode]

  public init(id: String, title: String, path: String? = nil, bytes: Int64, children: [UsageNode] = []) {
    self.id = id
    self.title = title
    self.path = path
    self.bytes = bytes
    self.children = children
  }

  /// Space inside that isn't in any of the listed children.
  public var unlistedBytes: Int64 { max(0, bytes - children.reduce(0) { $0 + $1.bytes }) }
}

/// Where the disk's space has gone, folder by folder: the answer to "what is
/// everything else?". Built from names and sizes only; protected folders are stepped
/// around and never measured, so their space is part of `unmeasuredBytes`.
public struct DiskUsage: Codable, Sendable {
  public var measured: Date
  public var seconds: Double
  public var volume: VolumeInfo
  /// The top-level places, largest first.
  public var areas: [UsageNode]
  /// Space in use that no area accounts for: protected folders, folders this account
  /// can't read, and snapshots macOS keeps.
  public var unmeasuredBytes: Int64
  /// How many protected folders and files were stepped around.
  public var protectedSkipped: Int
  /// How many folders couldn't be opened.
  public var unreadable: Int

  public init(
    measured: Date, seconds: Double, volume: VolumeInfo, areas: [UsageNode], unmeasuredBytes: Int64,
    protectedSkipped: Int, unreadable: Int
  ) {
    self.measured = measured
    self.seconds = seconds
    self.volume = volume
    self.areas = areas
    self.unmeasuredBytes = unmeasuredBytes
    self.protectedSkipped = protectedSkipped
    self.unreadable = unreadable
  }

  public var measuredBytes: Int64 { areas.reduce(0) { $0 + $1.bytes } }

  /// For each folder that holds something the scan found, how much of it the scan
  /// lists, with nested findings counted once. Keyed by path.
  public func clearable(in scan: ScanResult) -> [String: Int64] {
    var totals: [String: Int64] = [:]
    for finding in scan.findings where finding.within == nil {
      guard let first = finding.paths.first else { continue }
      var path = Protection.clean(first)
      while path.count > 1 {
        totals[path, default: 0] += finding.bytes
        path = (path as NSString).deletingLastPathComponent
      }
    }
    return totals
  }
}

public struct UsageProgress: Sendable {
  public var finished: Int
  public var total: Int
  /// The area that was just measured.
  public var area: UsageNode?
}

/// Measures the whole disk the home folder is on, a few areas at a time.
public enum DiskUsageMeter {
  /// Where macOS keeps everything that isn't the sealed system: the folders at its
  /// top are what `/Applications`, `/Library`, `/Users` and the rest really are.
  static let dataRoot = "/System/Volumes/Data"

  /// Children smaller than this aren't listed on their own.
  static let minimumChildBytes: Int64 = 50_000_000
  static let maximumChildren = 15
  /// Top-level places smaller than this are gathered into one line.
  static let minimumAreaBytes: Int64 = 100_000_000

  struct Root: Sendable {
    var path: String
    var title: String
    /// How many levels of folders to keep sizes for.
    var depth: Int
  }

  public static func measure(
    config: GladeConfig = ConfigStore.load(),
    home: String = NSHomeDirectory(),
    cancel: CancelFlag = CancelFlag(),
    progress: @escaping @Sendable (UsageProgress) -> Void = { _ in }
  ) async -> DiskUsage? {
    let started = Date()
    let protection = Protection(config: config, home: home)
    let roots = roots(home: Protection.clean(home))
    Log.info(.scan, "Disk usage started: \(roots.count) areas")

    let limiter = Limiter(4)
    var areas: [UsageNode] = []
    var skipped = 0, unreadable = 0
    await withTaskGroup(of: Walked?.self) { group in
      for root in roots {
        group.addTask {
          await limiter.acquire()
          let walked = await Task.detached(priority: .utility) {
            walk(root, protection: protection) { cancel.isCancelled }
          }.value
          await limiter.release()
          return walked
        }
      }
      var finished = 0
      for await walked in group {
        finished += 1
        guard let walked else {
          progress(UsageProgress(finished: finished, total: roots.count + 1, area: nil))
          continue
        }
        skipped += walked.skipped
        unreadable += walked.unreadable
        if walked.node.bytes > 0 { areas.append(walked.node) }
        progress(UsageProgress(finished: finished, total: roots.count + 1, area: walked.node.bytes > 0 ? walked.node : nil))
      }
    }
    guard !cancel.isCancelled else {
      Log.info(.scan, "Disk usage stopped before it finished")
      return nil
    }
    for node in await systemVolumes(home: home) {
      areas.append(node)
      progress(UsageProgress(finished: roots.count, total: roots.count + 1, area: node))
    }
    // Folders too small to matter on their own are shown as one line.
    let small = areas.filter { $0.bytes < minimumAreaBytes }
    if small.count > 1 {
      areas.removeAll { $0.bytes < minimumAreaBytes }
      areas.append(UsageNode(id: "small", title: "Smaller System Folders", bytes: small.reduce(0) { $0 + $1.bytes }))
    }
    areas.sort { $0.bytes > $1.bytes }

    let volume = VolumeInfo.current(path: home)
    let measured = areas.reduce(0) { $0 + $1.bytes }
    let usage = DiskUsage(
      measured: Date(), seconds: Date().timeIntervalSince(started), volume: volume, areas: areas,
      unmeasuredBytes: max(0, volume.usedBytes - measured), protectedSkipped: skipped, unreadable: unreadable
    )
    Log.info(.scan, "Disk usage finished: \(areas.count) areas, \(Format.bytes(measured)) measured, \(Format.bytes(usage.unmeasuredBytes)) not, \(skipped) protected and \(unreadable) unreadable places left out, \(String(format: "%.1f", usage.seconds))s")
    progress(UsageProgress(finished: roots.count + 1, total: roots.count + 1, area: nil))
    return usage
  }

  public static func save(_ usage: DiskUsage) {
    do {
      try JSONFiles.write(usage, to: GladePaths.diskUsage)
    } catch {
      Log.error(.scan, "Couldn’t save disk usage: \(error)")
    }
  }

  public static func loadLast() -> DiskUsage? {
    JSONFiles.read(DiskUsage.self, from: GladePaths.diskUsage)
  }

  // MARK: Areas

  /// The places to measure: the home folder, then everything else at the top of the
  /// disk, each by the path the rest of Glade (and the safety policy) knows it by.
  static func roots(home: String) -> [Root] {
    var roots = [Root(path: home, title: "Home Folder", depth: 3)]
    let names = (try? FileManager.default.contentsOfDirectory(atPath: dataRoot)) ?? []
    guard !names.isEmpty else {
      // No separate data volume to list: the usual places.
      return roots + ["/Applications", "/Library", "/private", "/opt", "/usr/local", "/Users/Shared"]
        .filter(FileFacts.isDirectory).map { Root(path: $0, title: title(for: $0), depth: depth(for: $0)) }
    }
    for name in names.sorted() {
      switch name {
      case "Volumes", "home", ".vol":
        // Other disks and network homes.
        continue
      case "Users":
        // Other accounts, each by its usual path so the safety rules apply as written.
        for user in ((try? FileManager.default.contentsOfDirectory(atPath: "/Users")) ?? []).sorted() {
          let path = "/Users/" + user
          guard path != home, !user.hasPrefix("."), FileFacts.isDirectory(path) else { continue }
          roots.append(Root(path: path, title: user == "Shared" ? "Shared" : "Account: \(user)", depth: 1))
        }
      default:
        let path = canonical(name)
        // Never the home folder by its other name, which the safety rules don't cover.
        guard !path.hasPrefix(dataRoot + "/Users") else { continue }
        roots.append(Root(path: path, title: title(for: path), depth: depth(for: path)))
      }
    }
    return roots
  }

  /// `/Applications` for the data volume's `Applications` when they are the same
  /// folder, otherwise its path on the data volume.
  static func canonical(_ name: String) -> String {
    let direct = "/" + name, onData = dataRoot + "/" + name
    var a = stat(), b = stat()
    if lstat(direct, &a) == 0, lstat(onData, &b) == 0, a.st_dev == b.st_dev, a.st_ino == b.st_ino { return direct }
    return onData
  }

  static func title(for path: String) -> String {
    switch path {
    case "/Applications": "Applications"
    case "/Library": "Library (Shared by All Accounts)"
    case "/private": "System Data"
    case "/opt", "/usr", dataRoot + "/opt", dataRoot + "/usr": "Command-Line Tools (\((path as NSString).lastPathComponent))"
    case dataRoot + "/System": "macOS Downloads & Assets"
    default: (path as NSString).lastPathComponent
    }
  }

  static func depth(for path: String) -> Int {
    switch path {
    case "/Applications": 1
    case "/Library", "/private", dataRoot + "/System": 3
    default: 2
    }
  }

  // MARK: Walking

  struct Walked: Sendable {
    var node: UsageNode
    var skipped: Int
    var unreadable: Int
  }

  private final class Node {
    var name: String
    var path: String
    var own: Int64 = 0
    var children: [Node] = []

    init(name: String, path: String) {
      self.name = name
      self.path = path
    }
  }

  /// Adds up one area, keeping sizes for its folders down to the root's depth.
  /// Protected folders are never entered: by path while a rule could still apply
  /// beneath, and by name everywhere.
  static func walk(_ root: Root, protection: Protection, isCancelled: () -> Bool) -> Walked? {
    guard protection.canScan(root.path) else { return nil }
    var stack = [Node?](repeating: nil, count: root.depth + 1)
    var top: Node?
    var skipped = 0, unreadable = 0, counter = 0
    var cancelled = false
    /// The level of a folder with no protected path anywhere beneath it. Everything
    /// deeper needs only the name check until the walk comes back up to that level.
    var clearLevel: Int?
    var links = Set<FileIdentity>()

    DiskWalk.walk([root.path], unreadable: { _ in unreadable += 1 }) { entry in
      counter += 1
      if counter & 0xFFF == 0, isCancelled() {
        cancelled = true
        return .stop
      }
      let level = entry.depth
      if let clear = clearLevel, level <= clear { clearLevel = nil }

      if entry.isDirectory {
        if level > 0 {
          // Listing a cloud folder that isn't on this Mac would fetch it.
          if entry.isDataless { return .skip }
          if protection.isProtectedName(entry.name) {
            skipped += 1
            return .skip
          }
        }
        if clearLevel == nil {
          let path = entry.path
          if !protection.canScan(path) {
            skipped += 1
            return .skip
          }
          if protection.zoneBeneath(path) == nil { clearLevel = level }
        }
        if level <= root.depth {
          let node = Node(name: entry.name, path: entry.path)
          if level == 0 { top = node } else { stack[level - 1]?.children.append(node) }
          stack[level] = node
        }
        stack[min(level, root.depth)]?.own += entry.allocated
        return .proceed
      }

      if entry.linkCount > 1, !links.insert(FileIdentity(device: entry.device, inode: entry.inode)).inserted {
        return .proceed
      }
      let size = entry.allocated
      // Most files are small; only ones big enough to matter are checked by name.
      if size > 1_000_000, protection.isProtectedName(entry.name) {
        skipped += 1
        return .proceed
      }
      stack[min(max(level - 1, 0), root.depth)]?.own += size
      return .proceed
    }
    guard !cancelled, let top else { return nil }
    var node = usageNode(top)
    node.title = root.title
    return Walked(node: node, skipped: skipped, unreadable: unreadable)
  }

  private static func usageNode(_ node: Node) -> UsageNode {
    let children = node.children.map(usageNode)
    let total = node.own + children.reduce(0) { $0 + $1.bytes }
    let listed = children.filter { $0.bytes >= minimumChildBytes }.sorted { $0.bytes > $1.bytes }.prefix(maximumChildren)
    return UsageNode(id: node.path, title: displayName(node), path: node.path, bytes: total, children: Array(listed))
  }

  /// A folder's name as a person knows it: an app's name for its container, and
  /// plain words for the downloads macOS files under its own long names.
  private static func displayName(_ node: Node) -> String {
    let parent = ((node.path as NSString).deletingLastPathComponent as NSString).lastPathComponent
    if parent == "Containers" || parent == "Application Scripts", let app = AppNames.name(forBundleID: node.name) {
      return app
    }
    let assetPrefix = "com_apple_MobileAsset_"
    if node.name.hasPrefix(assetPrefix) {
      let name = String(node.name.dropFirst(assetPrefix.count))
      if let known = assetNames[name] { return known }
      if name.hasSuffix("SimulatorRuntime") { return "\(name.dropLast("SimulatorRuntime".count)) Simulator Systems" }
      return name.replacingOccurrences(of: "UAF_", with: "").replacingOccurrences(of: "_", with: " ")
    }
    return node.name
  }

  private static let assetNames = [
    "iOSSimulatorRuntime": "iOS Simulator Systems",
    "xrOSSimulatorRuntime": "visionOS Simulator Systems",
    "appleTVOSSimulatorRuntime": "tvOS Simulator Systems",
    "watchOSSimulatorRuntime": "watchOS Simulator Systems",
    "MetalToolchain": "Metal Toolchain",
    "AppleDeveloperDocumentation": "Developer Documentation",
    "MacSoftwareUpdate": "macOS Update",
  ]

  // MARK: macOS's own volumes

  /// The sealed system, its start-up and recovery volumes, and the swap files, which
  /// share the disk but aren't folders anyone can walk. Sizes come from `diskutil`.
  static func systemVolumes(home: String) async -> [UsageNode] {
    var info = statfs()
    guard statfs(home, &info) == 0 else { return [] }
    let device = withUnsafePointer(to: &info.f_mntfromname) {
      String(cString: UnsafeRawPointer($0).assumingMemoryBound(to: CChar.self))
    }.replacingOccurrences(of: "/dev/", with: "")
    guard let result = try? await Shell.run("diskutil", ["apfs", "list", "-plist"], timeout: 20), result.succeeded,
          let plist = try? PropertyListSerialization.propertyList(from: Data(result.stdout.utf8), format: nil) as? [String: Any],
          let containers = plist["Containers"] as? [[String: Any]] else {
      Log.warning(.scan, "Disk usage: couldn’t list the disk’s volumes, so macOS itself isn’t sized")
      return []
    }
    for container in containers {
      guard let volumes = container["Volumes"] as? [[String: Any]],
            volumes.contains(where: { $0["DeviceIdentifier"] as? String == device }) else { continue }
      var system: [UsageNode] = []
      var swap: Int64 = 0
      for volume in volumes {
        let roles = volume["Roles"] as? [String] ?? []
        let used = (volume["CapacityInUse"] as? NSNumber)?.int64Value ?? 0
        let identifier = volume["DeviceIdentifier"] as? String ?? UUID().uuidString
        if roles.contains("VM") {
          swap += used
        } else if !roles.contains("Data"), identifier != device, used > 0 {
          let title = roles.contains("System") ? "System" : (volume["Name"] as? String ?? identifier)
          system.append(UsageNode(id: "volume:" + identifier, title: title, bytes: used))
        }
      }
      var nodes: [UsageNode] = []
      if !system.isEmpty {
        system.sort { $0.bytes > $1.bytes }
        nodes.append(UsageNode(id: "volume:macos", title: "macOS", bytes: system.reduce(0) { $0 + $1.bytes }, children: system))
      }
      if swap > 0 {
        nodes.append(UsageNode(id: "volume:swap", title: "Memory Swap", bytes: swap))
      }
      return nodes
    }
    return []
  }
}
