import Foundation

/// A conversation with the Assistant as it’s kept on this Mac, so it can be opened
/// again: what was asked and answered, who answered, and when. Plans and proposals
/// aren’t kept: they describe the Mac at that moment, and an old one must not be acted on.
public struct SavedConversation: Codable, Sendable, Identifiable, Equatable {
  public struct Turn: Codable, Sendable, Equatable {
    public enum Role: String, Codable, Sendable { case person, assistant, problem }
    public var role: Role
    public var text: String
    public var date: Date
    public var provider: String?
    public var model: String?

    public init(role: Role, text: String, date: Date, provider: String? = nil, model: String? = nil) {
      self.role = role
      self.text = text
      self.date = date
      self.provider = provider
      self.model = model
    }
  }

  public var id: UUID
  /// A name the person gave it; otherwise the first question names it.
  public var name: String?
  public var pinned: Bool
  public var turns: [Turn]

  public init(id: UUID = UUID(), name: String? = nil, pinned: Bool = false, turns: [Turn] = []) {
    self.id = id
    self.name = name
    self.pinned = pinned
    self.turns = turns
  }

  public var title: String {
    if let name, !name.isEmpty { return name }
    let first = turns.first { $0.role == .person }?.text ?? "New conversation"
    let line = first.split(whereSeparator: \.isNewline).first.map(String.init) ?? first
    return line.count > 80 ? String(line.prefix(80)) + "…" : line
  }

  public var updated: Date { turns.last?.date ?? .distantPast }
}

/// Saved conversations, one file each in Application Support. Local only; nothing here
/// is sent anywhere, and deleting one deletes its file.
public enum ConversationStore {
  /// The most kept; the oldest unpinned ones go first.
  static let limit = 200

  /// Every saved conversation, pinned first, then the latest first.
  public static func all() -> [SavedConversation] {
    let files = (try? FileManager.default.contentsOfDirectory(at: GladePaths.conversations, includingPropertiesForKeys: nil)) ?? []
    return files.filter { $0.pathExtension == "json" }
      .compactMap { JSONFiles.read(SavedConversation.self, from: $0) }
      .sorted { ($0.pinned ? 1 : 0, $0.updated) > ($1.pinned ? 1 : 0, $1.updated) }
  }

  public static func load(_ id: UUID) -> SavedConversation? {
    JSONFiles.read(SavedConversation.self, from: file(id))
  }

  public static func save(_ conversation: SavedConversation) {
    guard !conversation.turns.isEmpty else { return }
    do {
      try JSONFiles.write(conversation, to: file(conversation.id))
    } catch {
      Log.warning(.agent, "Couldn’t save the conversation: \(error.localizedDescription)")
    }
  }

  public static func delete(_ id: UUID) {
    do {
      try FileManager.default.removeItem(at: file(id))
    } catch {
      Log.warning(.agent, "Couldn’t delete the conversation: \(error.localizedDescription)")
    }
  }

  /// Deletes the oldest unpinned conversations beyond the limit.
  public static func prune() {
    let unpinned = all().filter { !$0.pinned }
    for old in unpinned.dropFirst(limit) { delete(old.id) }
  }

  static func file(_ id: UUID) -> URL {
    GladePaths.conversations.appendingPathComponent("\(id.uuidString).json")
  }
}
