/// One SF Symbol per idea, used everywhere that idea appears, so the same thing never
/// has two pictures. Every name here is checked against the catalog.
public enum Symbols {
  public static let scan = "arrow.clockwise"
  public static let review = "checklist"
  public static let freeUp = "sparkles.rectangle.stack"
  public static let putBack = "arrow.uturn.backward"
  public static let assistant = "sparkles"
  public static let whatWasSent = "text.page.badge.magnifyingglass"
  public static let newConversation = "square.and.pencil"
  public static let inspector = "sidebar.trailing"
  public static let settings = "gearshape"
  /// Anything Glade leaves alone: protected areas, and what cloud AIs never see.
  public static let protected = "lock"
  /// Folders Glade can’t measure until Full Disk Access is on.
  public static let fullDiskAccess = "lock"
  public static let showInFinder = "folder"
  public static let more = "ellipsis"

  /// Who started a clean.
  public static let byPerson = "person.fill"
  public static let byAssistant = "sparkles"
  public static let byAutomation = "clock.arrow.circlepath"
  public static let byCommandLine = "terminal"
}
