import AppKit
import Foundation
import Synchronization

public enum ActivationPolicy: String, Codable, Sendable {
  /// Has a Dock icon and menu bar.
  case regular
  /// A menu bar or agent app: windows, but no Dock icon.
  case accessory
  /// No interface at all, including plain command-line processes.
  case background

  init(_ policy: NSApplication.ActivationPolicy) {
    switch policy {
    case .regular: self = .regular
    case .accessory: self = .accessory
    default: self = .background
    }
  }
}

/// One row as a person thinks of it: an app with all its helpers, or a standalone
/// process such as `node`, `claude` or `swift-frontend`.
public struct AppUsage: Codable, Sendable, Identifiable, Hashable {
  public enum Kind: String, Codable, Sendable {
    /// An `.app` bundle and its helpers.
    case app
    /// A process outside any app, grouped by name.
    case process
  }

  /// The bundle identifier, else `path:<bundle path>`, else `process:<name>`.
  public var id: String
  public var kind: Kind
  public var name: String
  public var bundleIdentifier: String?
  public var bundlePath: String?
  /// The main process: the one NSWorkspace knows, or the lowest pid.
  public var mainPID: Int32?
  public var pids: [Int32]
  /// Summed share of one core across members: 100 means one full core.
  public var cpuPercent: Double
  /// Summed physical footprint of members.
  public var memoryBytes: Int64
  /// Summed share of the GPU, 0–100. `nil` when the GPU doesn’t record it per process.
  public var gpuPercent: Double?
  public var threadCount: Int
  /// The member using the most processor right now, for spotting a runaway helper.
  public var busiestPID: Int32?
  public var busiestCPUPercent: Double
  public var isFrontmost: Bool
  public var isHidden: Bool
  public var activationPolicy: ActivationPolicy
  public var launchDate: Date?
  /// When it was last the frontmost app, from the activity log. The frontmost app is now.
  public var lastActive: Date?
  public var isPlayingAudio: Bool
  public var isCapturingAudio: Bool
  /// What it’s keeping awake for, such as "Playing video" or an export’s name.
  public var preventingSleep: String?
  /// On-screen windows at the normal level.
  public var windowCount: Int
  /// Has a window covering a whole display.
  public var isFullScreen: Bool
  /// The app’s `LSApplicationCategoryType`, such as `public.app-category.games`.
  public var category: String?
  public var isGame: Bool
  /// Part of macOS, or owned by another user: never suggested for quitting.
  public var isSystem: Bool
  /// Glade itself.
  public var isGlade: Bool
  /// Some members belong to another user and couldn’t be measured directly.
  public var hasRestrictedMembers: Bool
}

/// Folds processes into apps.
///
/// 1. A process inside `Something.app/…` belongs to the outermost `.app` in its path
///    (Chrome Helper → Google Chrome). Xcode’s command-line tools under
///    `Xcode.app/Contents/Developer` are the exception and stand alone.
/// 2. An XPC service belongs to the app responsible for it (WebKit → Safari).
/// 3. Anything else follows its parent chain to an app, stopping at a shell, so tools
///    started from a terminal (`node`, `claude`, `xcodebuild`) stay visible as their own rows.
/// 4. What’s left is grouped by name.
public enum AppGrouper {
  static let shells: Set<String> = ["zsh", "bash", "sh", "fish", "dash", "tcsh", "csh", "ksh", "login", "tmux", "screen", "nu", "sshd", "sshd-session"]

  /// Command-line tools that always get their own row, even when an app started them.
  static let standaloneTools: Set<String> = [
    "node", "bun", "deno", "python", "python3", "ruby", "java", "claude", "codex", "ollama", "llama-server",
    "xcodebuild", "swift-frontend", "swift-build", "swift", "clang", "ld", "cargo", "rustc", "go", "docker",
    "qemu-system-aarch64", "gradle", "esbuild", "tsc", "vite",
  ]

  public static func group(
    _ processes: [ProcessSample], activity: ActivityLog = .shared, now: Date = Date()
  ) -> [AppUsage] {
    let (launched, frontmost) = LaunchedApps.current()
    return group(processes, launched: launched, frontmostPID: frontmost, signals: .current(), activity: activity, now: now)
  }

  static func group(
    _ processes: [ProcessSample], launched: [LaunchedApp], frontmostPID: pid_t?, signals: AppSignals,
    activity: ActivityLog, now: Date
  ) -> [AppUsage] {
    let byPID = Dictionary(processes.map { ($0.pid, $0) }, uniquingKeysWith: { first, _ in first })
    let launchedByPID = Dictionary(launched.map { ($0.pid, $0) }, uniquingKeysWith: { first, _ in first })

    // Running apps registered at one path may execute from another (Safari runs from a
    // cryptex), so map the bundle seen in the executable path back to the registered one.
    var alias: [String: String] = [:]
    for app in launched {
      guard let registered = app.bundlePath, outermost(registered) == registered,
        let path = byPID[app.pid]?.executablePath ?? app.executablePath,
        let seen = appBundle(in: path), seen != registered
      else { continue }
      alias[seen] = registered
    }

    enum Key: Hashable {
      case bundle(String)
      case name(String)
    }

    // Simulated devices run dozens of processes; they read as one row, under Simulator
    // when it’s open.
    let simulatorKey: Key =
      launched.first { $0.bundleID == "com.apple.iphonesimulator" }?.bundlePath.map { .bundle($0) } ?? .name(simulatorRowName)

    var direct: [pid_t: Key?] = [:]
    direct.reserveCapacity(processes.count)
    func directKey(_ process: ProcessSample) -> Key? {
      if let known = direct[process.pid] { return known }
      var found: Key?
      if isSimulator(process.executablePath) {
        found = simulatorKey
      } else if let registered = launchedByPID[process.pid]?.bundlePath, registered.hasSuffix(".app") {
        // Helpers can register too (a browser’s helper app); they still belong to the outer app.
        found = .bundle(outermost(registered))
      } else if let path = process.executablePath, let bundle = appBundle(in: path) {
        found = .bundle(alias[bundle] ?? bundle)
      }
      direct[process.pid] = .some(found)
      return found
    }

    func key(_ process: ProcessSample) -> Key {
      if let key = directKey(process) { return key }
      if isXPCService(process.executablePath),
        let responsible = Responsibility.responsiblePID(for: process.pid), let owner = byPID[responsible],
        let key = directKey(owner)
      {
        return key
      }
      if !standaloneTools.contains(process.name.lowercased()) {
        var cursor = process.parentPID
        var steps = 0
        while cursor > 1, steps < 16, let parent = byPID[cursor] {
          let parentName = parent.name.lowercased()
          if shells.contains(parentName) || standaloneTools.contains(parentName) { break }
          if let key = directKey(parent) {
            if parent.userID == process.userID { return key }
            break
          }
          cursor = parent.parentPID
          steps += 1
        }
      }
      return .name(process.name)
    }

    var members: [Key: [ProcessSample]] = [:]
    for process in processes { members[key(process), default: []].append(process) }

    let gladePID = getpid()
    let gladeBundleID = Bundle.main.bundleIdentifier?.lowercased()
    let currentUser = ProcessTable.currentUser
    var rows: [AppUsage] = []
    rows.reserveCapacity(members.count)

    for (key, group) in members {
      let pids = group.map(\.pid).sorted()
      var bundlePath: String?
      var main: LaunchedApp?
      var kind = AppUsage.Kind.process
      var displayName: String
      switch key {
      case .bundle(let path):
        kind = .app
        bundlePath = path
        let candidates = group.compactMap { launchedByPID[$0.pid] }.filter { $0.bundlePath == path }
        main = candidates.first { $0.policy == .regular } ?? candidates.first
        displayName = main?.name ?? BundleInfo.of(path).name
      case .name(let name):
        displayName = name
      }
      let info = bundlePath.map(BundleInfo.of)
      let bundleID = main?.bundleID ?? info?.bundleID
      let id = bundleID ?? bundlePath.map { "path:\($0)" } ?? "process:\(displayName)"
      let mainPID = main?.pid ?? pids.first

      var cpu = 0.0, memory: Int64 = 0, threads = 0
      var gpu: Double?
      var busiest: ProcessSample?
      var audio = AudioUse()
      var sleepReason: String?
      var windows = 0
      var fullScreen = false
      var restricted = false
      for process in group {
        cpu += process.cpuPercent ?? 0
        memory += process.memoryBytes ?? 0
        threads += process.threadCount ?? 0
        if let value = process.gpuPercent { gpu = (gpu ?? 0) + value }
        if (process.cpuPercent ?? 0) > (busiest?.cpuPercent ?? -1) { busiest = process }
        if let use = signals.audioByPID[process.pid] {
          audio.output = audio.output || use.output
          audio.input = audio.input || use.input
        }
        if sleepReason == nil { sleepReason = signals.sleepReasons[process.pid]?.first }
        windows += signals.windowCounts[process.pid] ?? 0
        fullScreen = fullScreen || signals.fullScreen.contains(process.pid)
        restricted = restricted || process.isRestricted
      }
      if let bundleID, let use = signals.audioByBundleID[bundleID.lowercased()] {
        audio.output = audio.output || use.output
        audio.input = audio.input || use.input
      }

      let isFrontmost = frontmostPID.map(pids.contains) ?? false
      let category = info?.category
      let mainProcess = mainPID.flatMap { byPID[$0] }
      let path = bundlePath ?? mainProcess?.executablePath
      let isSystem =
        SystemApps.isSystem(path: path, bundleID: bundleID, name: displayName)
        || group.allSatisfy { $0.userID != currentUser }
      let isGlade =
        pids.contains(gladePID) || (gladeBundleID != nil && bundleID?.lowercased() == gladeBundleID)
        || displayName.caseInsensitiveCompare(Brand.name) == .orderedSame

      rows.append(AppUsage(
        id: id, kind: kind, name: displayName, bundleIdentifier: bundleID, bundlePath: bundlePath,
        mainPID: mainPID, pids: pids, cpuPercent: cpu, memoryBytes: memory, gpuPercent: gpu, threadCount: threads,
        busiestPID: busiest?.pid, busiestCPUPercent: busiest?.cpuPercent ?? 0,
        isFrontmost: isFrontmost, isHidden: main?.isHidden ?? false,
        activationPolicy: main?.policy ?? .background,
        launchDate: main?.launchDate ?? group.compactMap(\.startTime).min(),
        lastActive: isFrontmost ? now : bundleID.flatMap { activity.lastActive(bundleID: $0) },
        isPlayingAudio: audio.output, isCapturingAudio: audio.input, preventingSleep: sleepReason,
        windowCount: windows, isFullScreen: fullScreen, category: category,
        isGame: GameDetection.isGame(category: category, bundleID: bundleID, bundlePath: bundlePath),
        isSystem: isSystem, isGlade: isGlade, hasRestrictedMembers: restricted
      ))
    }
    rows.sort { $0.memoryBytes > $1.memoryBytes }
    return rows
  }

  /// The outermost `.app` in a path, skipping Xcode’s toolchain under `Contents/Developer`
  /// (but not apps inside it, such as Simulator).
  public static func appBundle(in path: String) -> String? {
    // Byte-level search: this runs for every process on every listing.
    let bytes = Array(path.utf8)
    var start = 0
    while let end = find(appMarker, in: bytes, from: start) {
      let rest = end + appMarker.count
      if bytes[rest...].starts(with: developerMarker) {
        start = rest
        continue
      }
      return String(decoding: bytes[..<(end + appMarker.count - 1)], as: UTF8.self)
    }
    return nil
  }

  static let simulatorRowName = "Simulator devices"

  /// The outermost bundle of a registered app path, so a registered helper folds into its app.
  static func outermost(_ bundlePath: String) -> String {
    appBundle(in: bundlePath + "/") ?? bundlePath
  }

  static func isSimulator(_ path: String?) -> Bool {
    guard let path else { return false }
    let bytes = Array(path.utf8)
    return find(coreSimulatorMarker, in: bytes, from: 0) != nil || find(simRuntimeMarker, in: bytes, from: 0) != nil
  }

  static func isXPCService(_ path: String?) -> Bool {
    guard let path else { return false }
    return find(xpcMarker, in: Array(path.utf8), from: 0) != nil
  }

  private static let appMarker = Array(".app/".utf8)
  private static let xpcMarker = Array(".xpc/".utf8)
  private static let coreSimulatorMarker = Array("/CoreSimulator".utf8)
  private static let simRuntimeMarker = Array(".simruntime/".utf8)
  private static let developerMarker = Array("Contents/Developer/".utf8)

  private static func find(_ needle: [UInt8], in haystack: [UInt8], from start: Int) -> Int? {
    guard let first = needle.first, haystack.count >= needle.count else { return nil }
    var index = start
    let last = haystack.count - needle.count
    while index <= last {
      if haystack[index] == first && haystack[index..<(index + needle.count)].elementsEqual(needle) { return index }
      index += 1
    }
    return nil
  }
}

/// Apple’s own processes that must never be quit.
public enum SystemApps {
  /// Where Apple’s daemons, agents and core apps live. `/usr/bin` and `/bin` are left out
  /// on purpose: tools a person runs from there (`git`, `ssh`, `python3`) are theirs.
  static let prefixes = ["/System/Library/", "/usr/libexec/", "/usr/sbin/", "/usr/lib/", "/sbin/", "/Library/Apple/", "/System/iOSSupport/"]

  static let bundleIDs: Set<String> = [
    "com.apple.finder", "com.apple.dock", "com.apple.loginwindow", "com.apple.systemuiserver",
    "com.apple.controlcenter", "com.apple.notificationcenterui", "com.apple.windowmanager",
    "com.apple.spotlight", "com.apple.windowserver", "com.apple.coreservices.uiagent",
    "com.apple.textinputmenuagent", "com.apple.universalcontrol", "com.apple.wallpaper.agent",
  ]

  static let names: Set<String> = ["windowserver", "kernel_task", "launchd", "loginwindow", "finder", "dock", "systemuiserver", "controlcenter"]

  public static func isSystem(path: String?, bundleID: String?, name: String) -> Bool {
    if let bundleID, bundleIDs.contains(bundleID.lowercased()) { return true }
    if names.contains(name.lowercased()) { return true }
    guard let path else { return false }
    return prefixes.contains { path.hasPrefix($0) }
  }
}

enum GameDetection {
  /// Launchers whose being frontmost means a game session.
  static let launchers: Set<String> = [
    "com.valvesoftware.steam", "com.epicgames.epicgameslauncher", "net.battle.app", "com.blizzard.bna",
    "com.gog.galaxy", "com.codeweavers.crossover", "com.isaacmarovitz.whisky", "com.mojang.minecraftlauncher",
    "com.heroicgameslauncher.hgl", "com.ea.app", "com.ubisoft.connect",
  ]

  static func isGame(category: String?, bundleID: String?, bundlePath: String?) -> Bool {
    if let category = category?.lowercased(), category == "public.app-category.games" || category.hasSuffix("-games") { return true }
    if let bundleID, launchers.contains(bundleID.lowercased()) { return true }
    if let bundlePath, bundlePath.contains("/steamapps/common/") || bundlePath.contains("/Epic Games/") { return true }
    return false
  }
}

/// Name, identifier and category read once per bundle.
struct BundleInfo: Sendable {
  var name: String
  var bundleID: String?
  var category: String?

  private static let cache = Mutex<[String: BundleInfo]>([:])

  static func of(_ path: String) -> BundleInfo {
    if let cached = cache.withLock({ $0[path] }) { return cached }
    let fallback = ((path as NSString).lastPathComponent as NSString).deletingPathExtension
    var info = BundleInfo(name: fallback, bundleID: nil, category: nil)
    if let bundle = Bundle(path: path) {
      let dictionary = bundle.infoDictionary ?? [:]
      let localized = bundle.localizedInfoDictionary ?? [:]
      let display = (localized["CFBundleDisplayName"] ?? dictionary["CFBundleDisplayName"] ?? localized["CFBundleName"] ?? dictionary["CFBundleName"]) as? String
      if let display, !display.isEmpty { info.name = display }
      info.bundleID = bundle.bundleIdentifier
      info.category = dictionary["LSApplicationCategoryType"] as? String
    }
    cache.withLock { $0[path] = info }
    return info
  }
}
