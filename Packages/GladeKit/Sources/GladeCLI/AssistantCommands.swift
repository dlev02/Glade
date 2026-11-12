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
    discussion: "Glade gives the AI a snapshot of what’s running and what the last scan found. It answers in words and can’t take actions."
  )

  @OptionGroup var output: OutputOptions

  @Argument(help: "The question.")
  var question: String

  @Flag(name: .long, help: "Print the snapshot the AI would be given, and stop.")
  var showSnapshot = false

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
    if showSnapshot {
      print(description)
      return
    }
    let reply = try await Assistant.ask(question, snapshot: description, providers: AgentProviders.all)
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
