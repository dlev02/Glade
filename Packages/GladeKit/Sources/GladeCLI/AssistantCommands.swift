import ArgumentParser
import Foundation
import GladeKit

struct Advise: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    abstract: "Have your AI refine a clean plan. Changes nothing; shows what it would select and why.",
    discussion: "The AI sees names, sizes and dates of findings, never file contents, and can only choose among them."
  )

  @OptionGroup var output: OutputOptions

  @Option(name: .long, help: "careful, balanced or aggressive.")
  var level: CleanLevel?

  @Option(name: .long, help: "What you want, in your own words, e.g. \"free 30 GB\".")
  var goal: String?

  @Flag(name: .long, help: "Scan again first.")
  var rescan = false

  func run() async throws {
    let config = ConfigStore.load()
    let scan = try await Scans.recent(rescan: rescan, quiet: output.json)
    let base = Planner.plan(scan: scan, level: level ?? config.level, config: config)
    let sampler = SystemSampler()
    let apps = await sampler.apps()
    let context = ActivityContext.current(apps: apps)
    let result = try await Assistant.advise(
      scan: scan, plan: base, goal: goal, activity: MacDescription.activity(context: context, apps: apps),
      config: config, providers: AgentProviders.all
    )
    struct Report: Encodable {
      var provider: String
      var model: String?
      var escalated: Bool
      var summary: String
      var rulesSelected: Int64
      var nowSelected: Int64
      var selectedIDs: [String]
      var added: [StorageAdvice.Note]
      var removed: [StorageAdvice.Note]
      var review: [StorageAdvice.Note]
      var rejected: [StorageAdvice.Note]
    }
    let advice = result.advice
    let report = Report(
      provider: advice.provider, model: advice.model, escalated: advice.escalated, summary: advice.summary,
      rulesSelected: base.selectedBytes, nowSelected: result.plan.selectedBytes, selectedIDs: result.plan.selectedIDs,
      added: advice.select, removed: advice.deselect, review: advice.review, rejected: advice.rejected
    )
    emit(report, json: output.json) {
      func title(_ id: String) -> String { scan.finding(id).map { "\($0.title) (\(Format.bytes($0.bytes)))" } ?? id }
      print("\(advice.provider)\(advice.model.map { " · \($0)" } ?? "")\(advice.escalated ? " (called in for a closer look)" : "")\n")
      print(advice.summary)
      print("\nRules alone: \(Format.bytes(base.selectedBytes)). With advice: \(Format.bytes(result.plan.selectedBytes)).")
      if !advice.select.isEmpty { print("\nAdded:") }
      for note in advice.select { print("  + \(title(note.id)) — \(note.why)") }
      if !advice.deselect.isEmpty { print("\nLeft alone:") }
      for note in advice.deselect { print("  − \(title(note.id)) — \(note.why)") }
      if !advice.review.isEmpty { print("\nWorth a look (yours to decide):") }
      for note in advice.review { print("  ? \(title(note.id)) — \(note.why)") }
      if !advice.rejected.isEmpty { print("\nSuggestions Glade refused:") }
      for note in advice.rejected { print("  ✗ \(note.id) — \(note.why)") }
      print("\nTo do it: \(Brand.cli) clean --ids \(result.plan.selectedIDs.prefix(3).joined(separator: " ")) … --confirm (\(result.plan.selectedIDs.count) ids; use --json for the list)")
    }
  }
}

struct Ask: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    abstract: "Ask your AI a question about this Mac, e.g. \"why is it slow right now?\"",
    discussion: "Glade gives the AI a snapshot of what’s running and what the last scan found. It answers in words and can’t take actions. Asked to remove something (\"uninstall iMovie\"), it proposes items from the last scan, a second AI adds what you should know, and Glade prints the dry-run commands; nothing is removed."
  )

  @OptionGroup var output: OutputOptions

  @Argument(help: "The question.")
  var question: String

  @Flag(name: .long, help: "Print the snapshot the AI would be given, and stop.")
  var showSnapshot = false

  @Flag(name: .customLong("continue"), help: "Follow on from the last question (asked within six hours), so “and the other one?” makes sense.")
  var continues = false

  func run() async throws {
    let sampler = SystemSampler()
    let snapshot = await sampler.snapshot()
    let apps = await sampler.apps()
    let context = ActivityContext.current(apps: apps, power: snapshot.power)
    let suggestions = PerformanceAdvisor.suggestions(snapshot: snapshot, apps: apps, context: context)
    let scan = ScanEngine.loadLast()
    let history = BatteryHistoryStore.load()
    let status = await BatteryStatus.current(history: history)
    let unplugged = status.reading.state == .onBattery ? history.unpluggedSince() : nil
    let energy = EnergyReport.build(period: unplugged == nil ? .hour : .unplugged, apps: apps, history: history, unpluggedAt: unplugged)
    let description = MacDescription.build(
      snapshot: snapshot, apps: apps, context: context, suggestions: suggestions, scan: scan, plan: nil,
      battery: MacDescription.Battery(
        status: status, energy: energy.apps.isEmpty ? EnergyReport.build(period: .now, apps: apps, history: nil, unpluggedAt: nil) : energy,
        awake: await AwakeReport.current(apps: apps, sampler: sampler), sleeps: await SleepLog.recent()
      )
    )
    // Asked to remove something: a proposal to confirm, never a removal.
    if RemovalRequest.wantsProposal(question, scan: scan) {
      try await propose(description: description, hasScan: scan != nil)
      return
    }
    if showSnapshot {
      print(description)
      return
    }
    var earlier: [ConversationTurn] = []
    if continues {
      guard let previous = Conversation.continuing(from: Assistant.runs(limit: 30)) else {
        throw ValidationError("There’s no question from the last six hours to follow on from. Ask without --continue.")
      }
      earlier = previous
    }
    let reply = try await Assistant.ask(question, snapshot: description, earlier: earlier, providers: AgentProviders.all)
    struct Answer: Encodable {
      var answer: String
      var provider: String
    }
    emit(Answer(answer: reply.answer, provider: reply.provider), json: output.json) {
      print(reply.answer)
      print("\n— \(reply.provider)")
    }
  }
}

extension Ask {
  /// Proposes what to remove for the request, with the second opinion, and prints the
  /// dry-run commands that would act on it. Removes nothing.
  private func propose(description: String, hasScan: Bool) async throws {
    guard hasScan else {
      let text = "Glade hasn’t scanned this Mac yet, so it doesn’t know what’s here to remove. Run `\(Brand.cli) scan` first, then ask again."
      emit(ProposalReport(answer: text, provider: nil, model: nil, proposal: nil, commands: []), json: output.json) { print(text) }
      return
    }
    // The apps as they are now, merged into the last scan so identifiers match.
    let scan = await AppScans.current(rescan: false, quiet: output.json)
    let config = ConfigStore.load()
    if showSnapshot {
      let found = RemovalRequest.candidates(for: question, scan: scan, limit: 40)
      print(MacDescription.removalCandidates(found, characterBudget: 40_000).text + "\n\n" + description)
      return
    }
    let proposal = try await Assistant.propose(question, scan: scan, snapshot: description, config: config, providers: AgentProviders.all)
    let commands = Self.commands(for: proposal, scan: scan)
    let report = ProposalReport(answer: proposal.answer, provider: proposal.provider, model: proposal.model, proposal: proposal, commands: commands)
    emit(report, json: output.json) {
      func name(_ id: String?) -> String { id.flatMap { AgentProviders.provider(id: $0)?.name } ?? id ?? "none" }
      print(proposal.answer)
      if !proposal.items.isEmpty {
        print("\nProposed (nothing is removed until you confirm):")
        for item in proposal.items {
          print("  \(item.startsTicked ? "[x]" : "[ ]") \(item.title) · \(Format.bytes(item.bytes)) · id \(item.id)\(item.named ? "" : " · added by the AI")")
          if !item.why.isEmpty { print("      \(item.why)") }
          switch item.action {
          case .remove: break
          case .openUninstaller: print("      Has its own uninstaller: \(Brand.cli) uninstall \(Self.appArgument(item, scan)) --open-uninstaller")
          case .showInFinder: print("      Needs your password: move it to the Trash in Finder.")
          case .quitFirst: print("      Open now. Quit it first.")
          case .listOnly: print("      Can’t be removed now: \(item.blocked ?? "blocked").")
          }
          if let review = item.review, review.verdict == .caution || !review.note.isEmpty {
            print("      Second opinion: \(review.verdict == .caution ? "caution — " : "")\(review.note)")
          }
        }
      }
      for note in proposal.rejected { print("  ✗ refused \(note.id) — \(note.why)") }
      if !commands.isEmpty {
        print("\nDry runs for what’s ticked (add --confirm to do it):")
        for command in commands { print("  \(command)") }
      }
      let second = proposal.reviewer.map { "second opinion: \(name($0))\(proposal.reviewerModel.map { " · \($0)" } ?? "")" }
        ?? (proposal.items.isEmpty ? nil : "no second opinion was available")
      print("\n— \(name(proposal.provider))\(proposal.model.map { " · \($0)" } ?? "")\(second.map { "; \($0)" } ?? "")")
    }
  }

  /// One `uninstall` per ticked app and one `clean --ids` for the other ticked items,
  /// all dry runs.
  static func commands(for proposal: RemovalProposal, scan: ScanResult) -> [String] {
    let ticked = proposal.items.filter(\.startsTicked)
    var commands = ticked.filter(\.isApp).map { "\(Brand.cli) uninstall \(appArgument($0, scan))" }
    let others = ticked.filter { !$0.isApp }.map(\.id)
    if !others.isEmpty { commands.append("\(Brand.cli) clean --ids \(others.joined(separator: " "))") }
    return commands
  }

  /// The app’s bundle identifier, which `uninstall` matches exactly.
  static func appArgument(_ item: RemovalProposal.Item, _ scan: ScanResult) -> String {
    let id = scan.finding(item.id)?.app?.bundleID ?? item.title
    return id.contains(" ") ? "\"\(id)\"" : id
  }
}

private struct ProposalReport: Encodable {
  var answer: String
  var provider: String?
  var model: String?
  var proposal: RemovalProposal?
  /// Dry-run commands for the ticked items.
  var commands: [String]
}

struct Runs: ParsableCommand {
  static let configuration = CommandConfiguration(
    abstract: "Show what was sent to your AI and what came back, most recent first."
  )

  @OptionGroup var output: OutputOptions

  @Option(name: .long, help: "How many runs.")
  var limit = 5

  @Flag(name: .long, help: "Include the full prompt and reply.")
  var full = false

  func run() {
    let runs = Assistant.runs(limit: limit)
    emit(runs, json: output.json) {
      if runs.isEmpty { print("The assistant hasn’t run yet.") }
      for run in runs {
        let tokens = [run.inputTokens.map { "\($0) in" }, run.outputTokens.map { "\($0) out" }].compactMap { $0 }.joined(separator: ", ")
        print("\(run.date.formatted(date: .abbreviated, time: .standard))  \(run.provider) \(run.model ?? "default")  \(run.purpose)  \(String(format: "%.1f", run.duration))s  \(tokens)\(run.proactive ? "  [started by Glade]" : "")")
        if let error = run.error { print("  error: \(error)") }
        for rejected in run.rejected { print("  refused: \(rejected)") }
        if full {
          print("  --- prompt ---\n\(run.prompt)\n  --- reply ---\n\(run.reply ?? "")\n")
        }
      }
    }
  }
}
