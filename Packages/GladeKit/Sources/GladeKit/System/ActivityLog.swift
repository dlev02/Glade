import Foundation
import Synchronization

/// When each app was last in front, so Glade can tell an app left open for days from one
/// used a minute ago.
///
/// The long-running app calls `noteActivation(bundleID:)` from an
/// `NSWorkspace.didActivateApplicationNotification` observer and `flush()` when it quits.
/// The table is a small `[bundleID: Date]` JSON file, written at most once a minute.
public final class ActivityLog: Sendable {
  public static let shared = ActivityLog()

  /// Shortest gap between writes to disk.
  public static let writeInterval: TimeInterval = 60

  private struct State {
    var table: [String: Date] = [:]
    var loaded = false
    /// The app in front right now; it stays "active" until another app takes over.
    var current: String?
    var lastWrite = Date.distantPast
    var dirty = false
  }

  private let url: URL
  private let state = Mutex(State())

  public init(url: URL = GladePaths.activity) {
    self.url = url
  }

  /// Records that an app came to the front, and that the one it replaced was in use
  /// until now.
  public static func noteActivation(bundleID: String?, at date: Date = Date()) {
    shared.noteActivation(bundleID: bundleID, at: date)
  }

  public func noteActivation(bundleID: String?, at date: Date = Date()) {
    let pending: [String: Date]? = state.withLock { state in
      loadIfNeeded(&state)
      if let previous = state.current { state.table[previous] = date }
      if let bundleID {
        state.table[bundleID] = date
        state.current = bundleID
      } else {
        state.current = nil
      }
      state.dirty = true
      guard date.timeIntervalSince(state.lastWrite) >= Self.writeInterval else { return nil }
      state.lastWrite = date
      state.dirty = false
      return state.table
    }
    if let pending { write(pending) }
  }

  /// When the app was last in front, or `nil` if Glade has never seen it there.
  public func lastActive(bundleID: String) -> Date? {
    state.withLock { state in
      loadIfNeeded(&state)
      return state.table[bundleID]
    }
  }

  public var entries: [String: Date] {
    state.withLock { state in
      loadIfNeeded(&state)
      return state.table
    }
  }

  /// Writes any unsaved activations now. Call when the app quits.
  public func flush(at date: Date = Date()) {
    let pending: [String: Date]? = state.withLock { state in
      if let current = state.current { state.table[current] = date }
      guard state.dirty || state.current != nil else { return nil }
      state.dirty = false
      state.lastWrite = date
      return state.table
    }
    if let pending { write(pending) }
  }

  private func loadIfNeeded(_ state: inout State) {
    guard !state.loaded else { return }
    state.loaded = true
    guard FileManager.default.fileExists(atPath: url.path) else { return }
    if let table = JSONFiles.read([String: Date].self, from: url) {
      state.table.merge(table) { mine, _ in mine }
    } else {
      SystemIssues.warn("activity.read", "Activity log at \(url.path) couldn’t be read; starting fresh")
    }
  }

  private func write(_ table: [String: Date]) {
    // Keep the file small: forget apps not seen for 90 days.
    let cutoff = Date().addingTimeInterval(-90 * 86_400)
    let trimmed = table.filter { $0.value > cutoff }
    do {
      try JSONFiles.write(trimmed, to: url)
    } catch {
      SystemIssues.warn("activity.write", "Activity log couldn’t be saved to \(url.path): \(error)")
    }
  }
}
