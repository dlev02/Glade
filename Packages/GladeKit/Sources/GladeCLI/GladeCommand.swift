import ArgumentParser
import Foundation
import GladeKit

/// The root of the command line. Every action the app can take is reachable from here,
/// so anything a person can do in the window, an agent or a script can do too.
public struct GladeCommand: AsyncParsableCommand {
  public static let configuration = CommandConfiguration(
    commandName: Brand.cli,
    abstract: "See what's using your Mac's storage, memory and processors, and clear it safely.",
    discussion: """
      Every command accepts --json for machine-readable output. Nothing is removed \
      without --confirm, and protected areas (credentials, Photos, Mail, Messages, \
      cloud folders) are never read. Run `\(Brand.cli) guide` for a briefing written for AI agents.
      """,
    version: Brand.version,
    subcommands: [Doctor.self, Scan.self, Plan.self, Clean.self, Undo.self, Receipts.self, Protect.self, Categories.self, Logs.self, MCP.self, Guidance.self,
      Status.self, Processes.self, Apps.self, Context.self, Suggest.self, Quit.self,
    ]
  )

  public init() {}
}

/// The entry point shared by the app's executable and the development tool.
public enum CLI {
  /// Parses and runs a command. Exits the process when it finishes.
  public static func run(_ arguments: [String]? = nil) async {
    Log.echoToStandardError(minimum: .warning)
    // ArgumentParser exits the process itself, so make sure the log is written first.
    atexit { Log.flush() }
    await GladeCommand.main(arguments)
  }

  /// The subcommand names, so the app can tell a command-line launch from a normal one.
  public static var subcommands: Set<String> {
    Set(GladeCommand.configuration.subcommands.map { $0.configuration.commandName ?? String(describing: $0).lowercased() })
      .union(["help", "--help", "-h", "--version"])
  }
}

struct OutputOptions: ParsableArguments {
  @Flag(name: .long, help: "Print JSON instead of text.")
  var json = false
}

extension ParsableCommand {
  /// Prints a value as JSON, or runs the text printer.
  func emit<T: Encodable>(_ value: T, json: Bool, text: () -> Void) {
    if json {
      print(JSONFiles.string(value))
    } else {
      text()
    }
  }
}

struct Doctor: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    abstract: "Check permissions and what Glade can see."
  )

  @OptionGroup var output: OutputOptions

  struct Report: Encodable {
    var version: String
    var fullDiskAccess: Bool
    var home: String
    var volume: VolumeInfo
    var protectedZones: [String]
    var logFile: String
  }

  func run() async throws {
    let report = Report(
      version: Brand.version,
      fullDiskAccess: FullDiskAccess.isGranted,
      home: GladePaths.home,
      volume: VolumeInfo.current(),
      protectedZones: Protection().zones.map(\.title),
      logFile: GladePaths.logs.appendingPathComponent("glade.log").path
    )
    emit(report, json: output.json) {
      print("\(Brand.name) \(report.version)")
      print("Full Disk Access: \(report.fullDiskAccess ? "granted" : "not granted (some folders can't be measured)")")
      print("Disk: \(Format.bytes(report.volume.availableBytes)) available of \(Format.bytes(report.volume.totalBytes))")
      print("Protected: \(report.protectedZones.joined(separator: ", "))")
      print("Log: \(report.logFile)")
    }
  }
}
