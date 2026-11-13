import ArgumentParser
import Foundation
import GladeKit

/// Little Snitch, read from an export the person makes. Glade never talks to Little
/// Snitch itself: its command line needs root and an opening in its own security.
struct LittleSnitch: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "littlesnitch",
    abstract: "Review your Little Snitch rules from an export: overlaps, leftovers, broad allows and gaps.",
    discussion: """
      In Little Snitch choose File › Create Backup (or export a rule group), then \
      `\(Brand.cli) littlesnitch import <file>`. Suggested rules come back as an .lsrules file \
      you import into Little Snitch yourself, as a group that starts switched off.
      """,
    subcommands: [LittleSnitchSummary.self, LittleSnitchImport.self, LittleSnitchReviewCommand.self, LittleSnitchCleanedBackup.self],
    defaultSubcommand: LittleSnitchSummary.self
  )
}

struct LittleSnitchSummary: ParsableCommand {
  static let configuration = CommandConfiguration(commandName: "summary", abstract: "What the last import holds and what Glade noticed (the default).")
  @OptionGroup var output: OutputOptions

  func run() throws {
    guard let rules = LittleSnitchRules.load() else {
      throw ValidationError("No rules imported yet. In Little Snitch choose File › Create Backup, then: \(Brand.cli) littlesnitch import <file>")
    }
    struct Report: Encodable {
      var imported: Date
      var source: String
      var rules: Int
      var allow: Int
      var deny: Int
      var groups: [LittleSnitchRules.Group]
      var blocklistEntries: Int
      var unreadable: Int
      var findings: [LittleSnitchRules.Finding]
    }
    let findings = rules.findings()
    let report = Report(
      imported: rules.imported, source: rules.source, rules: rules.rules.count, allow: rules.allowCount, deny: rules.denyCount,
      groups: rules.groups, blocklistEntries: rules.blocklistEntries, unreadable: rules.unreadable, findings: findings
    )
    emit(report, json: output.json) {
      print("\(rules.rules.count) rules from a \(rules.source) imported \(Format.age(rules.imported)): \(rules.allowCount) allow, \(rules.denyCount) deny\(rules.blocklistEntries > 0 ? ", plus \(rules.blocklistEntries) blocklist entries" : "").")
      if rules.unreadable > 0 { print("\(rules.unreadable) rules couldn’t be read.") }
      if findings.isEmpty {
        print("Nothing stands out.")
      } else {
        print("")
        for finding in findings.prefix(30) { print("• \(finding.sentence)") }
      }
      print("\nFor a review with suggestions: \(Brand.cli) littlesnitch review")
    }
  }
}

struct LittleSnitchImport: ParsableCommand {
  static let configuration = CommandConfiguration(commandName: "import", abstract: "Read a Little Snitch backup or .lsrules file.")
  @Argument(help: "The exported file.") var file: String

  func run() throws {
    let url = URL(fileURLWithPath: (file as NSString).expandingTildeInPath)
    let data: Data
    do {
      data = try Data(contentsOf: url)
    } catch {
      throw ValidationError(LittleSnitchError.unreadableFile(error.localizedDescription).localizedDescription)
    }
    do {
      var rules = try LittleSnitchRules.parse(data)
      rules.sourcePath = url.path
      try rules.save()
      Log.info(.network, "Imported \(rules.rules.count) Little Snitch rules from a \(rules.source)")
      print("Read \(rules.rules.count) rules (\(rules.allowCount) allow, \(rules.denyCount) deny). See them: \(Brand.cli) littlesnitch")
      print("Glade kept a stripped-down copy; you can delete the export now.")
    } catch {
      throw ValidationError(error.localizedDescription)
    }
  }
}

struct LittleSnitchReviewCommand: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "review",
    abstract: "Ask your AI to review the imported rules. Changes nothing in Little Snitch.",
    discussion: "The AI is shown each rule's app path, destination, direction and action, never your traffic. New rules are written to an .lsrules file for you to import."
  )
  @OptionGroup var output: OutputOptions
  @Option(name: .long, help: "What you want, such as \"simplify\" or \"block trackers for Chrome\".") var goal: String?
  @Option(name: .long, help: "Where to write suggested rules (default: the Desktop).") var out: String?

  func run() async throws {
    guard var rules = LittleSnitchRules.load() else { throw ValidationError("No rules imported yet: \(Brand.cli) littlesnitch import <file>") }
    let review = try await Assistant.reviewLittleSnitch(rules, request: goal, providers: AgentProviders.all)
    // Remembered so `cleaned-backup` can leave exactly these out.
    rules.reviewRemovals = review.remove.map(\.id)
    try? rules.save()
    var written: String?
    if let data = review.rulesFile() {
      let path = out.map { ($0 as NSString).expandingTildeInPath } ?? NSHomeDirectory() + "/Desktop/Glade suggested rules.lsrules"
      try data.write(to: URL(fileURLWithPath: path), options: .atomic)
      written = path
    }
    struct Report: Encodable {
      var review: LittleSnitchReview
      var rulesFile: String?
    }
    emit(Report(review: review, rulesFile: written), json: output.json) {
      print(review.summary)
      for point in review.points { print("\n• \(point.title)\n  \(point.detail)") }
      if !review.remove.isEmpty {
        print("\nWorth deleting in Little Snitch (\(review.remove.count) rules, by app; --json lists each):")
        for line in review.removalsByApp { print("  – \(line)") }
        print("\nTo do it:")
        for step in review.howToApply() { print("  \(step.replacingOccurrences(of: "**", with: ""))") }
        print("  The cleaned backup: \(Brand.cli) littlesnitch cleaned-backup")
      }
      if let written {
        print("\n\(review.add.count) suggested rules written to \(Redactor.tilde(written)).")
        print("Open it to import into Little Snitch as a new group; it starts switched off.")
      }
      if !review.rejected.isEmpty { print("\nGlade refused \(review.rejected.count) suggestions.") }
      print("\n— \(review.provider)")
    }
  }
}

struct LittleSnitchCleanedBackup: ParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "cleaned-backup",
    abstract: "Write a copy of your backup without the rules the last review suggested deleting, to restore in Little Snitch.",
    discussion: """
      The copy is your backup with only those rules taken out; Glade refuses to drop a block \
      that isn’t a duplicate or a rule a group manages. In Little Snitch choose File › Restore \
      from Backup… and pick it; Little Snitch backs up your current rules first. Rules you \
      made since the backup are not in it, so make a fresh backup and review it just before.
      """
  )
  @Option(name: .long, help: "Where to write it (default: next to the original).") var out: String?
  @Flag(name: .long, help: "Instead of the review’s list, leave out only rules for apps no longer on this Mac.") var goneApps = false

  func run() throws {
    guard let rules = LittleSnitchRules.load(), let source = rules.sourcePath else {
      throw ValidationError("Import a Little Snitch backup first: \(Brand.cli) littlesnitch import <file>")
    }
    let ids: [String]
    if goneApps {
      ids = rules.rules.filter { $0.gone == true && !$0.managed && !$0.builtIn && $0.action != "deny" }.map(\.id)
    } else {
      guard let removals = rules.reviewRemovals, !removals.isEmpty else {
        throw ValidationError("Run \(Brand.cli) littlesnitch review first, or add --gone-apps.")
      }
      ids = removals
    }
    let original: Data
    do {
      original = try Data(contentsOf: URL(fileURLWithPath: source))
    } catch {
      throw ValidationError("The backup at \(Redactor.tilde(source)) can’t be read any more. Import it again.")
    }
    do {
      let cleaned = try LittleSnitchBackup.cleaned(original, removing: Set(ids), expected: rules)
      let base = (source as NSString).deletingPathExtension
      let path = out.map { ($0 as NSString).expandingTildeInPath } ?? base + " (cleaned by Glade).lsbackup"
      guard path != source else { throw ValidationError("Choose a different file; the original stays as it is.") }
      try cleaned.data.write(to: URL(fileURLWithPath: path), options: .atomic)
      print("Wrote \(Redactor.tilde(path)) without \(cleaned.removed) rules.")
      print("In Little Snitch choose File › Restore from Backup… and pick it. Little Snitch backs up your current rules first.")
    } catch let problem as LittleSnitchBackup.Problem {
      throw ValidationError(problem.localizedDescription)
    }
  }
}
