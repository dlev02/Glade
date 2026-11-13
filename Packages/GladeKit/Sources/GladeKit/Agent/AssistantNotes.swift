import Foundation

/// One thing the Assistant should know next time: “AT&T fibre, BGW320 gateway”,
/// “Simulators have filled memory before; check them first”. Dated, so a stale one
/// reads as such, and shown to the person in Settings, where they can change it.
public struct AssistantNote: Codable, Sendable, Identifiable, Equatable {
  public enum Source: String, Codable, Sendable {
    /// Typed by the person in Settings.
    case person
    /// Suggested by the Assistant and saved by the person.
    case assistant
    /// Added with `glade notes add`.
    case commandLine
  }

  public var id: UUID
  public var text: String
  public var added: Date
  public var source: Source

  public init(id: UUID = UUID(), text: String, added: Date = Date(), source: Source) {
    self.id = id
    self.text = text
    self.added = added
    self.source = source
  }
}

/// What the Assistant remembers between conversations: only notes the person wrote or
/// saved, kept short so they never crowd out what Glade measures now. They go to
/// whichever AI answers, inside the prompt, and the readings beside them always win.
public enum AssistantNotes {
  public static let maximumNotes = 30
  public static let maximumLength = 200

  public enum Problem: Error, LocalizedError, Equatable {
    case empty, tooLong, full, duplicate, looksSecret

    public var errorDescription: String? {
      switch self {
      case .empty: "The note is empty."
      case .tooLong: "Keep a note under \(AssistantNotes.maximumLength) characters."
      case .full: "There are \(AssistantNotes.maximumNotes) notes already. Remove one first."
      case .duplicate: "That note is already there."
      case .looksSecret: "That looks like a password or key. Notes go to the AI, so they can’t hold secrets."
      }
    }
  }

  public static var url: URL { GladePaths.support.appendingPathComponent("assistant-notes.json") }

  public static func load(from url: URL = url) -> [AssistantNote] {
    JSONFiles.read([AssistantNote].self, from: url) ?? []
  }

  public static func save(_ notes: [AssistantNote], to url: URL = url) {
    do {
      try JSONFiles.write(notes, to: url)
    } catch {
      Log.warning(.agent, "Couldn’t save the Assistant’s notes: \(error.localizedDescription)")
    }
  }

  /// Checks a note before it’s kept.
  public static func validate(_ text: String, existing: [AssistantNote]) throws -> String {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "\n", with: " ")
    guard !trimmed.isEmpty else { throw Problem.empty }
    guard trimmed.count <= maximumLength else { throw Problem.tooLong }
    guard Redactor.scrub(trimmed) == trimmed.replacingOccurrences(of: NSHomeDirectory(), with: "~") else { throw Problem.looksSecret }
    guard !existing.contains(where: { $0.text.caseInsensitiveCompare(trimmed) == .orderedSame }) else { throw Problem.duplicate }
    guard existing.count < maximumNotes else { throw Problem.full }
    return trimmed
  }

  @discardableResult
  public static func add(_ text: String, source: AssistantNote.Source, url: URL = url) throws -> AssistantNote {
    var notes = load(from: url)
    let note = AssistantNote(text: try validate(text, existing: notes), source: source)
    notes.append(note)
    save(notes, to: url)
    Log.info(.agent, "Kept a note for the Assistant (\(source.rawValue)); \(notes.count) in all")
    return note
  }

  public static func remove(_ id: UUID, url: URL = url) {
    save(load(from: url).filter { $0.id != id }, to: url)
  }

  /// The notes as a prompt section, oldest first, each with its date.
  /// - Parameter budget: Characters the section may use; the newest notes are kept.
  public static func section(_ notes: [AssistantNote], budget: Int = 7_000) -> String? {
    guard !notes.isEmpty else { return nil }
    var kept: [String] = []
    var used = 0
    for note in notes.sorted(by: { $0.added > $1.added }) {
      let line = "- [\(note.added.formatted(.iso8601.year().month().day()))] \(note.text)"
      guard used + line.count <= budget else { break }
      kept.append(line)
      used += line.count + 1
    }
    guard !kept.isEmpty else { return nil }
    let heading = "WHAT THE OWNER HAS TOLD GLADE TO REMEMBER (dated notes; the readings below are newer, so where they disagree the readings are right)"
    return ([heading] + kept.reversed()).joined(separator: "\n")
  }

  /// Splits a reply’s closing `Remember: …` line from the answer. The suggestion is
  /// only kept if the person saves it.
  public static func suggestion(in reply: String) -> (answer: String, note: String?) {
    var lines = reply.components(separatedBy: "\n")
    while let last = lines.last, last.trimmingCharacters(in: .whitespaces).isEmpty { lines.removeLast() }
    guard let last = lines.last else { return (reply, nil) }
    let trimmed = last.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "**", with: "")
    guard trimmed.lowercased().hasPrefix("remember:") else { return (reply, nil) }
    let note = trimmed.dropFirst("remember:".count).trimmingCharacters(in: .whitespaces)
    lines.removeLast()
    let answer = lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    guard (try? validate(note, existing: [])) != nil else { return (answer, nil) }
    return (answer, note)
  }
}
