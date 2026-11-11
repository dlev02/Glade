import Foundation

/// What a file is, in the broad sense search filters by.
public enum ContentKind: String, Codable, Sendable, CaseIterable, Identifiable {
  case document, pdf, text, code, spreadsheet, presentation, image, other

  public var id: String { rawValue }
  public var title: String { rawValue.capitalized }
}

/// One file found by a content search, with the passage that matched best.
public struct SearchHit: Codable, Sendable, Identifiable, Hashable {
  public var path: String
  /// Higher is better. Comparable within one search only.
  public var score: Double
  public var kind: ContentKind
  public var title: String
  /// The passage that matched best, or the start of the file.
  public var snippet: String
  public var labels: [String]
  public var size: Int64
  public var modified: Date

  public var id: String { path }
}

/// A file in a group of near-identical files.
public struct LookalikeMember: Codable, Sendable, Hashable {
  public var path: String
  public var size: Int64
  public var modified: Date
}

/// Files that look almost the same but aren’t byte-for-byte copies. Report only:
/// nothing here is ever selected for removal.
public struct LookalikeGroup: Codable, Sendable, Identifiable, Hashable {
  public var kind: ContentKind
  /// The largest difference between any member and the first one, in the measure
  /// used for this kind (feature-print distance for images, 1 − cosine for documents).
  public var spread: Double
  public var members: [LookalikeMember]

  public var id: String { members.map(\.path).joined(separator: "\n") }
  public var totalBytes: Int64 { members.reduce(0) { $0 + $1.size } }
}

/// What Glade knows about one indexed file, for the assistant.
public struct FileDescription: Codable, Sendable, Hashable {
  public var path: String
  public var kind: ContentKind
  public var title: String
  public var labels: [String]
  public var snippet: String
  public var size: Int64
  public var modified: Date
  public var indexed: Date
}

/// What one indexing run did.
public struct IndexReport: Codable, Sendable {
  public var folders: [String]
  public var started: Date
  public var finished: Date
  public var seen = 0
  public var indexed = 0
  public var skippedUnchanged = 0
  public var skippedProtected = 0
  public var skippedTooLarge = 0
  /// Formats Glade can’t read the contents of (videos, archives, disk images…).
  public var skippedUnsupported = 0
  /// Cloud files whose contents aren’t on this Mac.
  public var skippedCloud = 0
  public var failed = 0
  /// Entries removed because the file is gone or became protected.
  public var removed = 0
  public var cancelled = false
  /// Seconds spent reading contents, embedding text and looking at images.
  public var extractSeconds = 0.0
  public var embedSeconds = 0.0
  public var imageSeconds = 0.0
  public var embedder: String

  public var seconds: Double { finished.timeIntervalSince(started) }
}

/// The state of the index on disk.
public struct IndexStatus: Codable, Sendable {
  public var files: Int
  public var chunks: Int
  public var images: Int
  public var databaseBytes: Int64
  public var lastRun: Date?
  public var lastRunSeconds: Double?
  /// The text embedder the current vectors came from.
  public var embedder: String?
  public var location: String
}

/// Progress reported between files.
public struct IndexProgress: Sendable {
  public var finished: Int
  public var total: Int
  public var path: String
}
