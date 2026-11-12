import Foundation
import GladeKit

/// The installed-app tools offered to agents. An agent names an app, never a path:
/// the app is found afresh by the scanner and removed by its finding’s identifier.
extension MCPTools {
  static let apps: [MCPTool] = [
    MCPTool(
      name: "glade_installed",
      description: "List the apps in the Applications folders with their size (including the data they keep in the home folder), when each was last opened, where it came from (appStore, setapp, homebrew, other), and whether it has its own uninstaller. Read-only. Apps are never selected for the person: suggest candidates, let them choose.",
      schema: #"{"type":"object","properties":{"unusedDays":{"type":"integer","description":"Only apps not opened for at least this many days."},"sort":{"type":"string","enum":["size","opened"],"description":"size (largest first, default) or opened (longest unused first)."},"limit":{"type":"integer","description":"How many apps (default 40)."}},"additionalProperties":false}"#,
      readOnly: true
    ) { arguments in
      let scan = await AppScans.current(rescan: false, quiet: true)
      let sort = arguments["sort"]?.string.flatMap(InstalledSort.init(rawValue:)) ?? .size
      let rows = AppScans.rows(scan, unused: arguments["unusedDays"]?.int, sort: sort)
      return JSONFiles.string(Array(rows.prefix(arguments["limit"]?.int ?? 40)))
    },
    MCPTool(
      name: "glade_uninstall",
      description: "Move one app and the data it keeps in the home folder to the Trash. A dry run unless confirm is true: always do a dry run first and tell the person exactly what goes and what stays. Everything goes to the Trash, so glade_undo puts it back. Apps with their own uninstaller (Adobe’s, for example) are never removed by Glade; set openUninstaller to open theirs when the person asks, and scan afterwards for what it left. Apps that belong to the system account can only be removed in Finder, which asks for the person’s password.",
      schema: #"{"type":"object","properties":{"app":{"type":"string","description":"The app’s name or bundle identifier, as glade_installed lists it."},"confirm":{"type":"boolean","description":"Set true to actually move it to the Trash. Defaults to a dry run."},"openUninstaller":{"type":"boolean","description":"For an app with its own uninstaller, open it."}},"required":["app"],"additionalProperties":false}"#,
      readOnly: false
    ) { arguments in
      guard let name = arguments["app"]?.string, !name.isEmpty else { throw MCPFailure(message: "app is required.") }
      let (finding, scan) = try await AppScans.find(name)
      let report = try await UninstallReport.make(
        finding, scan: scan, confirm: arguments["confirm"]?.bool == true,
        openUninstaller: arguments["openUninstaller"]?.bool == true, initiator: .assistant(provider: "MCP client")
      )
      return JSONFiles.string(report)
    },
  ]
}
