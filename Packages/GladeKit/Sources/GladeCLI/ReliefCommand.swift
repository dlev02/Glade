import ArgumentParser
import Foundation
import GladeKit

/// `glade relieve`: Free Up Memory from the command line. A dry run unless `--confirm`.
struct Relieve: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    abstract: "Free up memory: quit idle apps and shut down idle simulators in one go. A dry run unless --confirm.",
    discussion: """
      Prints what Glade would do and which actions it would tick for you. With --confirm it asks the ticked apps \
      to quit (they can ask about unsaved work; nothing is force quit) and shuts the ticked simulators down \
      (their apps and data are kept), then measures memory again. The app in front, anything playing or \
      recording sound, keeping the Mac awake or on the keep-running list is never touched.
      """
  )

  @OptionGroup var output: OutputOptions

  @Flag(name: .long, help: "Carry out the ticked actions. Without it nothing changes.")
  var confirm = false

  @Option(name: .long, help: "Tick an action by name, app id or simulator UDID. An app the rules didn’t offer is added if it may be quit. Repeatable.")
  var include: [String] = []

  @Option(name: .long, help: "Untick an action by name, app id or simulator UDID. Repeatable.")
  var exclude: [String] = []

  @Flag(name: .long, help: "Tick only what --include names, nothing the rules would tick.")
  var only = false

  struct Report: Encodable {
    var dryRun: Bool
    var plan: ReliefPlan
    var selected: [String]
    /// The memory the ticked actions hold now; quitting gives back about this much.
    var expectedBytes: Int64
    var leftAlone: String?
    var refused: [String]
    var result: ReliefResult?
  }

  func validate() throws {
    if only && include.isEmpty { throw ValidationError("--only needs at least one --include.") }
  }

  func run() async throws {
    defer { _ = Log.recent(limit: 1) }
    let config = ConfigStore.load()
    var (plan, apps, _) = await ReliefPlan.current(config: config)
    let (chosen, refused) = plan.choose(include: include, exclude: exclude, only: only, apps: apps, config: config)

    let selected = plan.actions(chosen)
    var report = Report(
      dryRun: !confirm, plan: plan, selected: selected.map(\.id), expectedBytes: plan.memoryBytes(of: chosen),
      leftAlone: plan.leftAloneSummary, refused: refused, result: nil
    )
    if confirm, !selected.isEmpty {
      report.result = await ReliefResult.perform(selected, config: config) { done, total, name in
        guard !output.json, !name.isEmpty else { return }
        FileHandle.standardError.write(Data("\(done + 1)/\(total) \(name)…\n".utf8))
      }
    }

    emit(report, json: output.json) { printText(report, chosen: chosen) }
    if let result = report.result, !result.problems.isEmpty { throw ExitCode(1) }
  }

  private func printText(_ report: Report, chosen: Set<String>) {
    for line in report.refused { FileHandle.standardError.write(Data("Left out: \(line).\n".utf8)) }
    if let result = report.result {
      for entry in result.entries {
        let mark = entry.outcome.succeeded ? "✓" : "!"
        print("\(mark) \(entry.name): \(Self.outcomeText(entry))")
      }
      print("\nMemory in use \(Format.bytes(result.memoryBefore)) → \(Format.bytes(result.memoryAfter))")
      return
    }
    let plan = report.plan
    if plan.actions.isEmpty {
      print("Nothing to free up right now.")
    } else {
      let count = chosen.count
      print(count == 0
        ? "Nothing is ticked. Tick actions with --include."
        : "About \(Format.bytes(report.expectedBytes)) of memory from \(count) action\(count == 1 ? "" : "s")\(confirm ? "" : " (dry run; add --confirm to do it)")\n")
      for action in plan.actions {
        let tick = chosen.contains(action.id) ? "[x]" : "[ ]"
        let verb = switch action.kind {
        case .quit: "quit"
        case .relaunch: "relaunch"
        case .shutDown: "shut down"
        }
        print("\(tick) \(action.name)  \(action.facts)  (\(verb))\(action.caveat.map { "  ⚠ \($0)" } ?? "")")
        print("    \(action.why)")
      }
    }
    if let left = report.leftAlone { print("\n\(left)") }
  }

  static func outcomeText(_ entry: ReliefResult.Entry) -> String {
    switch entry.outcome {
    case .quit: "quit"
    case .relaunched: "relaunched"
    case .shutDown: "shut down; its apps and data are kept"
    case .alreadyGone: "already closed"
    case .stillOpen, .leftAlone, .failed: entry.detail ?? entry.outcome.rawValue
    }
  }
}
