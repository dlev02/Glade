import AppKit
import GladeKit
import Observation
@preconcurrency import Sparkle

/// Automatic updates through Sparkle. Glade checks by itself, downloads quietly and
/// applies the update the next time it quits, so nothing interrupts the person. A
/// development build has no feed and never checks.
@Observable
final class UpdateController: NSObject, SPUUpdaterDelegate {
  private(set) var canCheck = false
  /// True once the updater is running, which only happens in an installed release copy.
  private(set) var isAvailable = false

  var checksAutomatically = false {
    didSet {
      guard let updater, updater.automaticallyChecksForUpdates != checksAutomatically else { return }
      updater.automaticallyChecksForUpdates = checksAutomatically
      updater.automaticallyDownloadsUpdates = checksAutomatically
      Log.info(.update, "Automatic update checks turned \(checksAutomatically ? "on" : "off")")
    }
  }

  @ObservationIgnored private var standard: SPUStandardUpdaterController?
  @ObservationIgnored private var canCheckObservation: NSKeyValueObservation?

  private var updater: SPUUpdater? { standard?.updater }

  private var hasFeed: Bool {
    Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") as? String != nil
      && Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String != nil
  }

  /// Installed means sitting in an Applications folder. Copies run from a build
  /// folder or a disk image never touch the real update feed.
  private var isInstalledCopy: Bool {
    let path = Bundle.main.bundlePath
    return path.hasPrefix("/Applications/") || path.hasPrefix(NSHomeDirectory() + "/Applications/")
  }

  func start() {
    guard standard == nil, hasFeed, isInstalledCopy else {
      Log.info(.update, "Updates off: not an installed release copy")
      return
    }
    let standard = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: self, userDriverDelegate: nil)
    self.standard = standard
    canCheckObservation = standard.updater.observe(\.canCheckForUpdates, options: [.initial, .new]) { [weak self] _, change in
      let value = change.newValue ?? false
      DispatchQueue.main.async {
        MainActor.assumeIsolated { self?.canCheck = value }
      }
    }
    standard.startUpdater()
    isAvailable = true
    checksAutomatically = standard.updater.automaticallyChecksForUpdates
    Log.info(.update, "Updater started, automatic checks \(checksAutomatically ? "on" : "off")")
  }

  /// A check the person asked for; Sparkle shows its own result window.
  func checkNow() {
    guard canCheck else { return }
    Log.info(.update, "Manual update check")
    updater?.checkForUpdates()
  }

  // MARK: - SPUUpdaterDelegate

  nonisolated func updater(_ updater: SPUUpdater, didFinishUpdateCycleFor updateCheck: SPUUpdateCheck, error: (any Error)?) {
    let message = error.map { "Update check ended: \($0.localizedDescription)" } ?? "Update check finished"
    Log.info(.update, message)
  }

  nonisolated func updater(_ updater: SPUUpdater, willInstallUpdateOnQuit item: SUAppcastItem, immediateInstallationBlock immediateInstallHandler: @escaping () -> Void) -> Bool {
    Log.info(.update, "Version \(item.displayVersionString) downloaded; it installs at the next quit")
    return true
  }
}
