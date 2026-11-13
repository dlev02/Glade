import ArgumentParser
import Foundation
import GladeKit

/// What the Assistant remembers between conversations: notes the person keeps.
struct Notes: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    abstract: "The notes the Assistant gets with every question, such as your internet provider or an app you never use.",
    discussion: "Notes go to whichever AI answers, inside the prompt. Keep them short and lasting; never a password or code.",
    subcommands: [NotesList.self, NotesAdd.self, NotesRemove.self],
    defaultSubcommand: NotesList.self
  )
}

struct NotesList: ParsableCommand {
  static let configuration = CommandConfiguration(commandName: "list", abstract: "List the notes (the default).")
  @OptionGroup var output: OutputOptions

  func run() {
    let notes = AssistantNotes.load()
    emit(notes, json: output.json) {
      if notes.isEmpty { print("No notes yet. Add one with: \(Brand.cli) notes add \"<note>\"") }
      for (index, note) in notes.enumerated() {
        print("\(index + 1). \(note.text)  (\(note.added.formatted(date: .abbreviated, time: .omitted)))")
      }
    }
  }
}

struct NotesAdd: ParsableCommand {
  static let configuration = CommandConfiguration(commandName: "add", abstract: "Add a note.")
  @Argument(help: "The note, under 200 characters.") var text: String

  func run() throws {
    do {
      let note = try AssistantNotes.add(text, source: .commandLine)
      print("Kept: \(note.text)")
    } catch {
      throw ValidationError(error.localizedDescription)
    }
  }
}

struct NotesRemove: ParsableCommand {
  static let configuration = CommandConfiguration(commandName: "remove", abstract: "Remove a note by its number in the list.")
  @Argument(help: "The note’s number from `\(Brand.cli) notes`.") var number: Int

  func run() throws {
    let notes = AssistantNotes.load()
    guard notes.indices.contains(number - 1) else { throw ValidationError("There’s no note \(number).") }
    AssistantNotes.remove(notes[number - 1].id)
    print("Removed: \(notes[number - 1].text)")
  }
}

/// Standing rules: apps and tools whose leftovers and caches are always cleared.
struct Rules: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    abstract: "Apps and tools whose leftovers and caches are always ticked, such as one you no longer use.",
    discussion: "A rule ticks matching findings at every level, as you would by hand, and they go to the Trash. It never ticks personal files, anything in use, or an installed app.",
    subcommands: [RulesList.self, RulesAdd.self, RulesRemove.self],
    defaultSubcommand: RulesList.self
  )
}

struct RulesList: ParsableCommand {
  static let configuration = CommandConfiguration(commandName: "list", abstract: "List the rules and what each ticks in the last scan (the default).")
  @OptionGroup var output: OutputOptions

  func run() {
    let rules = ConfigStore.load().alwaysClear
    let scan = ScanEngine.loadLast()
    struct Rule: Encodable {
      var name: String
      var matches: [String]
      var bytes: Int64
    }
    let report = rules.map { rule in
      let found = scan?.findings.filter { AlwaysClear.rule(for: $0, rules: [rule]) != nil } ?? []
      return Rule(name: rule, matches: found.map(\.title), bytes: found.map(\.bytes).reduce(0, +))
    }
    emit(report, json: output.json) {
      if rules.isEmpty { print("No rules. Add one with: \(Brand.cli) rules add \"<app>\"") }
      for rule in report {
        print("Always clear \(rule.name): \(rule.matches.isEmpty ? "nothing in the last scan" : "\(rule.matches.count) findings, \(Format.bytes(rule.bytes))")")
        for title in rule.matches.prefix(8) { print("  \(title)") }
      }
    }
  }
}

struct RulesAdd: ParsableCommand {
  static let configuration = CommandConfiguration(commandName: "add", abstract: "Always clear an app’s or tool’s leftovers and caches.")
  @Argument(help: "The app or tool’s name, such as Cursor.") var name: String

  func run() throws {
    guard let rule = AlwaysClear.normalised(name) else {
      throw ValidationError("Use the app’s name, at least \(AlwaysClear.minimumLength) characters.")
    }
    var config = ConfigStore.load()
    guard !config.alwaysClear.contains(where: { $0.caseInsensitiveCompare(rule) == .orderedSame }) else {
      print("Already a rule: \(rule)")
      return
    }
    config.alwaysClear.append(rule)
    ConfigStore.save(config)
    Log.info(.cli, "Added a rule to always clear \(rule)")
    print("Glade will always tick \(rule)’s leftovers and caches. See what that covers: \(Brand.cli) rules")
  }
}

struct RulesRemove: ParsableCommand {
  static let configuration = CommandConfiguration(commandName: "remove", abstract: "Remove a rule.")
  @Argument(help: "The rule’s name.") var name: String

  func run() throws {
    var config = ConfigStore.load()
    let before = config.alwaysClear.count
    config.alwaysClear.removeAll { $0.caseInsensitiveCompare(name) == .orderedSame }
    guard config.alwaysClear.count < before else { throw ValidationError("There’s no rule for \(name).") }
    ConfigStore.save(config)
    print("Removed the rule for \(name).")
  }
}
