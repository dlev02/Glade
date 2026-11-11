import ArgumentParser
import Foundation
import GladeKit
import GladeUI

/// A development aid: draws a screen of the app to an image file.
struct Snapshot: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    abstract: "Draw one of the app's screens to a PNG, for checking layouts.",
    shouldDisplay: false
  )

  @Argument(help: "A screen name, or `list` to print them all.")
  var screen: String

  @Option(name: .long, help: "Where to write the PNG.")
  var out = "/tmp/glade-snapshot.png"

  @Option(name: .long, help: "For `window`: which section to show.")
  var section = "overview"

  @Option(name: .long) var width: Double = 1100
  @Option(name: .long) var height: Double = 740

  @Flag(name: .long, help: "Dark appearance.")
  var dark = false

  @Flag(name: .long, help: "Use this Mac's last scan instead of sample findings.")
  var live = false

  @MainActor
  func run() async throws {
    if screen == "list" {
      print(Snapshotter.screens.joined(separator: "\n"))
      return
    }
    try await Snapshotter.render(
      screen: screen, section: AppModel.Section(rawValue: section) ?? .overview,
      size: CGSize(width: width, height: height), dark: dark, live: live,
      to: URL(fileURLWithPath: (out as NSString).expandingTildeInPath)
    )
    print(out)
  }
}
