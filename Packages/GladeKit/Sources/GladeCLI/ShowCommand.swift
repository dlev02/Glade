import AppKit
import ArgumentParser
import Foundation
import GladeKit
import GladeUI

/// Opens the app's window on a section, starting the app if it isn't running.
struct Show: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    abstract: "Open Glade's window on overview, storage, performance, assistant or history."
  )

  /// The app's bundle identifier, for finding it when this isn't the app's own executable.
  static let bundleIdentifier = "io.github.dlev02.glade"

  @Argument(help: "overview, storage, performance, assistant or history.")
  var section = "overview"

  func run() async throws {
    print(try await Self.open(section))
  }

  /// Opens the window on a section and says what happened. Shared with the MCP server.
  static func open(_ section: String) async throws -> String {
    let name = section.lowercased()
    let link: URL? = await MainActor.run { AppModel.Section(rawValue: name)?.link }
    guard let link else {
      throw ValidationError("Choose overview, storage, performance, assistant or history.")
    }
    guard let app = appURL() else {
      throw ValidationError("\(Brand.name) isn't installed. Install the app first.")
    }
    let configuration = NSWorkspace.OpenConfiguration()
    configuration.activates = true
    do {
      _ = try await NSWorkspace.shared.open([link], withApplicationAt: app, configuration: configuration)
    } catch {
      // A copy from before links existed: start it on the section instead.
      Log.warning(.cli, "Couldn't open \(link.absoluteString) in \(app.lastPathComponent): \((error as NSError).code); launching with -startSection")
      configuration.arguments = ["-startSection", name]
      _ = try await NSWorkspace.shared.openApplication(at: app, configuration: configuration)
    }
    return "Opened \(Brand.name) on \(name.capitalized)."
  }

  /// This executable's own app when it runs from inside one, else the copy macOS knows.
  static func appURL() -> URL? {
    let own = Brand.appBundle.bundleURL
    if own.pathExtension == "app" { return own }
    return NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier)
  }
}
