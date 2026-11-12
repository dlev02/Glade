import Foundation
import GladeKit

/// What everything on the disk is: measuring it, and what the last scan found in each place.
extension AppModel {
  public var isMeasuringUsage: Bool { usageState != .idle }

  /// Shows the last measurement if there is one, and measures when there isn't.
  public func openUsage() {
    guard !isMeasuringUsage else { return }
    if usage == nil, !isDemo { usage = DiskUsageMeter.loadLast() }
    if usage == nil { measureUsage() }
  }

  public func measureUsage() {
    guard !isMeasuringUsage else { return }
    // Sample data never walks the real disk.
    if isDemo {
      usage = Self.sampleUsage(volume: snapshot?.disk ?? scan?.volume ?? .current())
      return
    }
    let cancel = CancelFlag()
    usageCancel = cancel
    usagePartial = []
    usageState = .measuring(done: 0, total: 1)
    let config = config
    Task {
      let result = await DiskUsageMeter.measure(config: config, cancel: cancel) { [weak self] progress in
        Task { @MainActor in
          guard let self, self.isMeasuringUsage else { return }
          self.usageState = .measuring(done: progress.finished, total: progress.total)
          if let area = progress.area {
            self.usagePartial.append(area)
            self.usagePartial.sort { $0.bytes > $1.bytes }
          }
        }
      }
      if let result {
        DiskUsageMeter.save(result)
        usage = result
      }
      usagePartial = []
      usageState = .idle
    }
  }

  public func cancelUsage() {
    usageCancel?.cancel()
  }

  /// For each folder, how much of it the last scan lists in Storage.
  public var usageListed: [String: Int64] {
    guard let usage, let scan else { return [:] }
    return usage.clearable(in: scan)
  }

  /// A made-up disk for screenshots. Places in the home folder and Applications carry
  /// the paths they’d have, so the sheet offers what it would for them; the sample
  /// findings and apps sit at the same paths.
  static func sampleUsage(volume: VolumeInfo) -> DiskUsage {
    let home = Protection.clean(NSHomeDirectory())
    func node(_ title: String, _ gigabytes: Double, path: String? = nil, _ children: [UsageNode] = []) -> UsageNode {
      UsageNode(id: path ?? "sample:" + title, title: title, path: path, bytes: Int64(gigabytes * 1e9), children: children)
    }
    let support = home + "/Library/Application Support"
    let areas = [
      node("Home Folder", 212, path: home, [
        node("Library", 131, path: home + "/Library", [
          node("Application Support", 58, path: support, [
            node("CleanShot", 22.4, path: support + "/CleanShot"), node("Dreamtime", 14.2, path: support + "/Dreamtime"),
            node("Steam", 9.9, path: support + "/Steam"), node("minecraft", 2.9, path: support + "/minecraft"),
          ]),
          node("Developer", 49, path: home + "/Library/Developer"),
          node("Containers", 14, path: home + "/Library/Containers", [
            node("Docker", 11.5, path: home + "/Library/Containers/com.docker.docker"),
            node("Final Cut Pro", 2.4, path: home + "/Library/Containers/com.apple.FinalCut"),
          ]),
        ]),
        node("Movies", 38, path: home + "/Movies"), node("Developer", 24, path: home + "/Developer"),
        node("Pictures", 11, path: home + "/Pictures"), node("Documents", 6.2, path: home + "/Documents"),
      ]),
      node("Applications", 64, path: "/Applications", [
        node("Final Cut Pro.app", 6, path: "/Applications/Final Cut Pro.app"), node("Xcode.app", 4.2, path: "/Applications/Xcode.app"),
        node("iMovie.app", 4, path: "/Applications/iMovie.app"),
      ]),
      node("macOS Downloads & Assets", 48, [node("iOS Simulator Systems", 25), node("visionOS Simulator Systems", 15)]),
      node("macOS", 37, [node("Preboot", 19), node("System", 14), node("Recovery", 3)]),
      node("System Data", 22), node("Library (Shared by All Accounts)", 18), node("Memory Swap", 8),
    ]
    let measured = areas.reduce(0) { $0 + $1.bytes }
    return DiskUsage(
      measured: Date(), seconds: 41, volume: volume, areas: areas,
      unmeasuredBytes: max(Int64(31e9), volume.usedBytes - measured), protectedSkipped: 212, unreadable: 0
    )
  }
}
