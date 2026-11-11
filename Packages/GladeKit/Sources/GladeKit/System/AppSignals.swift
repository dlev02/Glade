import AppKit
import CoreAudio
import CoreGraphics
import Foundation
import IOKit.pwr_mgt

/// Audio input and output a process is running right now.
struct AudioUse: Sendable, Hashable {
  var output = false
  var input = false
}

/// Everything about what apps are doing that isn’t CPU or memory: sound, sleep
/// assertions, windows. Each reader needs no permission prompt.
struct AppSignals: Sendable {
  var audioByPID: [pid_t: AudioUse] = [:]
  var audioByBundleID: [String: AudioUse] = [:]
  /// Assertion names per pid, for assertions that keep the Mac or its display awake.
  var sleepReasons: [pid_t: [String]] = [:]
  /// On-screen, normal-level windows per owner pid.
  var windowCounts: [pid_t: Int] = [:]
  /// Pids with a window covering a whole display.
  var fullScreen: Set<pid_t> = []

  static func current() -> AppSignals {
    var signals = AppSignals()
    for process in AudioActivity.processes() {
      if let pid = process.pid { signals.audioByPID[pid] = process.use }
      if let bundleID = process.bundleID { signals.audioByBundleID[bundleID.lowercased()] = process.use }
    }
    signals.sleepReasons = SleepAssertions.byProcess()
    (signals.windowCounts, signals.fullScreen) = Windows.onScreen()
    return signals
  }
}

/// Core Audio process objects (macOS 14.2+): which processes are playing or recording.
enum AudioActivity {
  struct Process: Sendable {
    var pid: pid_t?
    var bundleID: String?
    var use: AudioUse
  }

  static func processes() -> [Process] {
    var address = AudioObjectPropertyAddress(
      mSelector: kAudioHardwarePropertyProcessObjectList,
      mScope: kAudioObjectPropertyScopeGlobal,
      mElement: kAudioObjectPropertyElementMain
    )
    let system = AudioObjectID(kAudioObjectSystemObject)
    var size: UInt32 = 0
    var status = AudioObjectGetPropertyDataSize(system, &address, 0, nil, &size)
    guard status == noErr else {
      SystemIssues.warn("kAudioHardwarePropertyProcessObjectList", "Core Audio process list size failed with \(status); audio activity unavailable")
      return []
    }
    var objects = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
    guard !objects.isEmpty else { return [] }
    status = AudioObjectGetPropertyData(system, &address, 0, nil, &size, &objects)
    guard status == noErr else {
      SystemIssues.warn("kAudioHardwarePropertyProcessObjectList.data", "Core Audio process list failed with \(status); audio activity unavailable")
      return []
    }
    var result: [Process] = []
    // Each property read is a round trip to coreaudiod, so idle processes cost one read.
    for object in objects.prefix(Int(size) / MemoryLayout<AudioObjectID>.size) {
      guard (uint32(object, kAudioProcessPropertyIsRunning) ?? 1) != 0 else { continue }
      let use = AudioUse(
        output: (uint32(object, kAudioProcessPropertyIsRunningOutput) ?? 0) != 0,
        input: (uint32(object, kAudioProcessPropertyIsRunningInput) ?? 0) != 0
      )
      guard use.output || use.input else { continue }
      result.append(Process(pid: pid(object), bundleID: bundleID(object), use: use))
    }
    return result
  }

  private static func address(_ selector: AudioObjectPropertySelector) -> AudioObjectPropertyAddress {
    AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
  }

  private static func uint32(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector) -> UInt32? {
    var address = address(selector)
    var value: UInt32 = 0
    var size = UInt32(MemoryLayout<UInt32>.size)
    return AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value) == noErr ? value : nil
  }

  private static func pid(_ object: AudioObjectID) -> pid_t? {
    var address = address(kAudioProcessPropertyPID)
    var value: pid_t = 0
    var size = UInt32(MemoryLayout<pid_t>.size)
    return AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value) == noErr && value > 0 ? value : nil
  }

  private static func bundleID(_ object: AudioObjectID) -> String? {
    var address = address(kAudioProcessPropertyBundleID)
    var value: Unmanaged<CFString>?
    var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
    let status = withUnsafeMutablePointer(to: &value) { AudioObjectGetPropertyData(object, &address, 0, nil, &size, $0) }
    guard status == noErr, let text = value?.takeRetainedValue() as String?, !text.isEmpty else { return nil }
    return text
  }
}

/// Power-management assertions that hold off sleep: an export, a download, a call.
enum SleepAssertions {
  static let types: Set<String> = [
    "PreventUserIdleSystemSleep", "PreventUserIdleDisplaySleep", "NoIdleSleepAssertion",
    "NoDisplaySleepAssertion", "PreventSystemSleep",
  ]

  static func byProcess() -> [pid_t: [String]] {
    var assertions: Unmanaged<CFDictionary>?
    let result = IOPMCopyAssertionsByProcess(&assertions)
    guard result == kIOReturnSuccess, let dictionary = assertions?.takeRetainedValue() as NSDictionary? else {
      SystemIssues.warn("IOPMCopyAssertionsByProcess", "IOPMCopyAssertionsByProcess failed with \(result); sleep assertions unavailable")
      return [:]
    }
    var reasons: [pid_t: [String]] = [:]
    for (key, value) in dictionary {
      guard let pid = (key as? NSNumber)?.int32Value, let list = value as? [[String: Any]] else { continue }
      for assertion in list {
        guard let type = assertion["AssertType"] as? String, types.contains(type) else { continue }
        let name = (assertion["AssertName"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? type
        if !(reasons[pid]?.contains(name) ?? false) { reasons[pid, default: []].append(name) }
      }
    }
    return reasons
  }
}

/// On-screen windows by owner. Reads owner pid, layer and bounds only, which need no
/// Screen Recording permission; titles are never read.
enum Windows {
  static func onScreen() -> (counts: [pid_t: Int], fullScreen: Set<pid_t>) {
    guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
      SystemIssues.warn("CGWindowListCopyWindowInfo", "CGWindowListCopyWindowInfo returned nothing; window counts unavailable")
      return ([:], [])
    }
    let displays = displayBounds()
    var counts: [pid_t: Int] = [:]
    var fullScreen: Set<pid_t> = []
    for window in list {
      guard (window[kCGWindowLayer as String] as? Int) == 0,
        let pid = (window[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value
      else { continue }
      counts[pid, default: 0] += 1
      if let boundsInfo = window[kCGWindowBounds as String] as? NSDictionary,
        let bounds = CGRect(dictionaryRepresentation: boundsInfo),
        displays.contains(where: { bounds.width >= $0.width && bounds.height >= $0.height && bounds.contains(CGPoint(x: $0.midX, y: $0.midY)) })
      {
        fullScreen.insert(pid)
      }
    }
    return (counts, fullScreen)
  }

  private static func displayBounds() -> [CGRect] {
    var count: UInt32 = 0
    guard CGGetActiveDisplayList(0, nil, &count) == .success, count > 0 else { return [] }
    var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
    guard CGGetActiveDisplayList(count, &ids, &count) == .success else { return [] }
    return ids.prefix(Int(count)).map { CGDisplayBounds($0) }
  }
}

/// What NSWorkspace knows about one running app, copied into a plain value.
struct LaunchedApp: Sendable {
  var pid: pid_t
  var name: String?
  var bundleID: String?
  var bundlePath: String?
  var executablePath: String?
  var isHidden: Bool
  var policy: ActivationPolicy
  var launchDate: Date?
}

enum LaunchedApps {
  static func current() -> (apps: [LaunchedApp], frontmostPID: pid_t?) {
    let workspace = NSWorkspace.shared
    let apps = workspace.runningApplications.compactMap { app -> LaunchedApp? in
      guard app.processIdentifier > 0, !app.isTerminated else { return nil }
      return LaunchedApp(
        pid: app.processIdentifier, name: app.localizedName, bundleID: app.bundleIdentifier,
        bundlePath: app.bundleURL?.path, executablePath: app.executableURL?.path,
        isHidden: app.isHidden, policy: ActivationPolicy(app.activationPolicy), launchDate: app.launchDate
      )
    }
    return (apps, workspace.frontmostApplication?.processIdentifier)
  }
}

/// Finds the app responsible for an XPC service (WebKit content and GPU processes belong
/// to Safari, Mail and so on). Uses a libsystem function looked up at run time; when it
/// isn’t there, XPC services stand alone.
enum Responsibility {
  private typealias Function = @convention(c) (pid_t) -> pid_t

  private static let function: Function? = {
    guard let symbol = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "responsibility_get_pid_responsible_for_pid") else {
      SystemIssues.warn("responsibility", "responsibility_get_pid_responsible_for_pid isn’t available; XPC services aren’t grouped under their app")
      return nil
    }
    return unsafeBitCast(symbol, to: Function.self)
  }()

  static func responsiblePID(for pid: pid_t) -> pid_t? {
    guard let function else { return nil }
    let responsible = function(pid)
    return responsible > 0 && responsible != pid ? responsible : nil
  }
}
