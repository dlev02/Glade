import Foundation
import GladeKit
import UserNotifications

/// Posts notifications. Does nothing when Glade is running as a command-line tool,
/// which has no bundle to post from.
public enum Notifier {
  private static var isAvailable: Bool {
    Bundle.main.bundleIdentifier != nil && Bundle.main.bundlePath.hasSuffix(".app")
  }

  public static func isAllowed() async -> Bool {
    guard isAvailable else { return false }
    let settings = await UNUserNotificationCenter.current().notificationSettings()
    return settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional
  }

  /// Asks for permission. Returns whether notifications are now allowed.
  public static func request() async -> Bool {
    guard isAvailable else { return false }
    do {
      let granted = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
      Log.info(.app, "Notification permission \(granted ? "granted" : "declined")")
      return granted
    } catch {
      Log.warning(.app, "Asking for notification permission failed: \(error.localizedDescription)")
      return false
    }
  }

  /// Kept here because the notification centre holds its delegate weakly.
  private static var clicks: ClickHandler?

  /// Calls `open` with a notification’s kind when the person clicks it.
  public static func handleClicks(_ open: @escaping @MainActor @Sendable (String) -> Void) {
    guard isAvailable else { return }
    let handler = ClickHandler(open: open)
    clicks = handler
    UNUserNotificationCenter.current().delegate = handler
  }

  /// - Parameter kind: Groups repeats of the same alert so a new one replaces the old.
  public static func post(title: String, body: String, kind: String) async {
    guard await isAllowed() else { return }
    let content = UNMutableNotificationContent()
    content.title = title
    content.body = body
    content.threadIdentifier = kind
    let request = UNNotificationRequest(identifier: "glade.\(kind)", content: content, trigger: nil)
    do {
      try await UNUserNotificationCenter.current().add(request)
    } catch {
      Log.warning(.app, "Posting a notification failed: \(error.localizedDescription)")
    }
  }
}

/// Hears clicks on Glade’s notifications. Leaves how they’re shown to the system.
private final class ClickHandler: NSObject, UNUserNotificationCenterDelegate {
  nonisolated let open: @MainActor @Sendable (String) -> Void

  init(open: @escaping @MainActor @Sendable (String) -> Void) {
    self.open = open
  }

  nonisolated func userNotificationCenter(
    _ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
    withCompletionHandler completionHandler: @escaping () -> Void
  ) {
    let kind = response.notification.request.content.threadIdentifier
    let open = open
    Task { @MainActor in open(kind) }
    completionHandler()
  }
}
