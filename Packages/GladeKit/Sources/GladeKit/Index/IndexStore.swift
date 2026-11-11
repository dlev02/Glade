import Foundation
import SQLite3

/// What the store remembers about a file between runs, to decide whether to read it again.
struct FileStamp: Sendable {
  var id: Int64
  var size: Int64
  var modified: Double
  var embedder: String?
  var textHash: String?
}

/// One file’s row, ready to be written.
struct FileRecord: Sendable {
  var path: String
  var size: Int64
  var modified: Double
  var kind: ContentKind
  var title: String
  var snippet: String
  var labels: [String]
  var embedder: String
  var textHash: String
  var textLength: Int
  var bytesHash: String?
  var minHash: [UInt32]
}

/// Everything search needs, loaded into memory once and dropped whenever the store
/// changes. Tens of thousands of passages fit comfortably.
final class IndexSnapshot: Sendable {
  struct File: Sendable {
    var id: Int64
    var path: String
    var size: Int64
    var modified: Date
    var indexed: Date
    var kind: ContentKind
    var title: String
    var snippet: String
    var labels: [String]
    var textLength: Int
    var bytesHash: String?
    var minHash: [UInt32]
    /// Lower-cased words of the name, title and labels, for the name boost.
    var nameWords: Set<String>
  }

  let files: [File]
  let fileIndex: [Int64: Int]
  let pathIndex: [String: Int]
  let dimension: Int
  /// Passage vectors, row-major, one row per passage.
  let matrix: [Float]
  let chunkFile: [Int]
  let chunkIDs: [Int64]
  let chunkIndex: [Int64: Int]
  /// Image feature prints by position in `files`.
  let images: [(file: Int, vector: [Float])]

  init(files: [File], dimension: Int, matrix: [Float], chunkFile: [Int], chunkIDs: [Int64], images: [(file: Int, vector: [Float])]) {
    self.files = files
    self.dimension = dimension
    self.matrix = matrix
    self.chunkFile = chunkFile
    self.chunkIDs = chunkIDs
    self.images = images
    var fileIndex: [Int64: Int] = [:]
    var pathIndex: [String: Int] = [:]
    for (i, file) in files.enumerated() {
      fileIndex[file.id] = i
      pathIndex[file.path] = i
    }
    self.fileIndex = fileIndex
    self.pathIndex = pathIndex
    var chunkIndex: [Int64: Int] = [:]
    for (i, id) in chunkIDs.enumerated() { chunkIndex[id] = i }
    self.chunkIndex = chunkIndex

  }

  func vector(ofChunk row: Int) -> ArraySlice<Float> {
    matrix[(row * dimension)..<((row + 1) * dimension)]
  }
}

/// The on-disk index: one SQLite database inside Glade’s own folder, readable only by
/// this account. It holds what was learned about each file (kind, title, a short
/// snippet, labels), its passages with their vectors, and image feature prints.
/// Never holds whole documents: passages are capped per file.
public final class IndexStore: @unchecked Sendable {
  public let location: URL
  private let lock = NSRecursiveLock()
  private var db: OpaquePointer?
  private var cached: IndexSnapshot?

  public enum StoreError: Error, CustomStringConvertible {
    case sqlite(code: Int32, message: String)

    public var description: String {
      switch self {
      case .sqlite(let code, let message): "SQLite error \(code): \(message)"
      }
    }
  }

  /// Opens (creating if needed) the index at `location`. Pass a scratch path for
  /// experiments; the app uses `GladePaths.index`.
  public init(location: URL = GladePaths.index) throws {
    self.location = location
    let path = location.path
    try? FileManager.default.createDirectory(at: location.deletingLastPathComponent(), withIntermediateDirectories: true)
    if !FileManager.default.fileExists(atPath: path) {
      // Created up front with owner-only permissions; SQLite gives its side files the same.
      let descriptor = open(path, O_CREAT | O_WRONLY | O_CLOEXEC, 0o600)
      if descriptor >= 0 { close(descriptor) }
    }
    chmod(path, 0o600)
    var handle: OpaquePointer?
    let code = sqlite3_open_v2(path, &handle, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX, nil)
    guard code == SQLITE_OK, let handle else {
      let message = handle.map { String(cString: sqlite3_errmsg($0)) } ?? "open failed"
      sqlite3_close(handle)
      Log.error(.index, "Index database couldn’t be opened (SQLite \(code)): \(message)")
      throw StoreError.sqlite(code: code, message: message)
    }
    db = handle
    sqlite3_busy_timeout(handle, 5000)
    try migrate()
  }

  deinit {
    sqlite3_close_v2(db)
  }

  /// Removes the database and its side files.
  public static func delete(at location: URL = GladePaths.index) {
    for suffix in ["", "-wal", "-shm"] {
      try? FileManager.default.removeItem(atPath: location.path + suffix)
    }
  }

  private func migrate() throws {
    try execute("""
      PRAGMA journal_mode = WAL;
      PRAGMA synchronous = NORMAL;
      PRAGMA foreign_keys = ON;
      CREATE TABLE IF NOT EXISTS meta (key TEXT PRIMARY KEY, value TEXT NOT NULL);
      CREATE TABLE IF NOT EXISTS files (
        id INTEGER PRIMARY KEY,
        path TEXT NOT NULL UNIQUE,
        size INTEGER NOT NULL,
        mtime REAL NOT NULL,
        kind TEXT NOT NULL,
        title TEXT NOT NULL,
        snippet TEXT NOT NULL,
        labels TEXT NOT NULL,
        indexed_at REAL NOT NULL,
        embedder TEXT,
        text_hash TEXT,
        text_length INTEGER NOT NULL DEFAULT 0,
        bytes_hash TEXT,
        minhash BLOB
      );
      CREATE TABLE IF NOT EXISTS chunks (
        id INTEGER PRIMARY KEY,
        file_id INTEGER NOT NULL REFERENCES files(id) ON DELETE CASCADE,
        seq INTEGER NOT NULL,
        text TEXT NOT NULL,
        vector BLOB NOT NULL
      );
      CREATE INDEX IF NOT EXISTS chunks_file ON chunks(file_id);
      CREATE TABLE IF NOT EXISTS images (
        file_id INTEGER PRIMARY KEY REFERENCES files(id) ON DELETE CASCADE,
        embedder TEXT NOT NULL,
        vector BLOB NOT NULL
      );
      CREATE VIRTUAL TABLE IF NOT EXISTS chunk_words USING fts5(
        text, content='chunks', content_rowid='id', tokenize='porter unicode61 remove_diacritics 2'
      );
      CREATE TRIGGER IF NOT EXISTS chunks_added AFTER INSERT ON chunks BEGIN
        INSERT INTO chunk_words(rowid, text) VALUES (new.id, new.text);
      END;
      CREATE TRIGGER IF NOT EXISTS chunks_removed AFTER DELETE ON chunks BEGIN
        INSERT INTO chunk_words(chunk_words, rowid, text) VALUES ('delete', old.id, old.text);
      END;
      """)
  }

  // MARK: Statements

  /// A prepared statement that is always finalised.
  final class Statement {
    let handle: OpaquePointer

    init(_ handle: OpaquePointer) { self.handle = handle }
    deinit { sqlite3_finalize(handle) }

    private static let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    func bind(_ index: Int32, _ value: String?) {
      if let value { sqlite3_bind_text(handle, index, value, -1, Statement.transient) } else { sqlite3_bind_null(handle, index) }
    }
    func bind(_ index: Int32, _ value: Int64) { sqlite3_bind_int64(handle, index, value) }
    func bind(_ index: Int32, _ value: Double) { sqlite3_bind_double(handle, index, value) }
    func bind(_ index: Int32, _ value: Data?) {
      guard let value else { sqlite3_bind_null(handle, index); return }
      _ = value.withUnsafeBytes { sqlite3_bind_blob(handle, index, $0.baseAddress, Int32($0.count), Statement.transient) }
    }

    func text(_ column: Int32) -> String? {
      sqlite3_column_text(handle, column).map { String(cString: $0) }
    }
    func int(_ column: Int32) -> Int64 { sqlite3_column_int64(handle, column) }
    func double(_ column: Int32) -> Double { sqlite3_column_double(handle, column) }
    func data(_ column: Int32) -> Data? {
      guard let bytes = sqlite3_column_blob(handle, column) else { return nil }
      return Data(bytes: bytes, count: Int(sqlite3_column_bytes(handle, column)))
    }
  }

  private func failure(_ code: Int32, _ context: String) -> StoreError {
    let message = db.map { String(cString: sqlite3_errmsg($0)) } ?? "no database"
    Log.error(.index, "Index \(context) failed (SQLite \(code)): \(message)")
    return .sqlite(code: code, message: message)
  }

  private func prepare(_ sql: String) throws -> Statement {
    var handle: OpaquePointer?
    let code = sqlite3_prepare_v2(db, sql, -1, &handle, nil)
    guard code == SQLITE_OK, let handle else { throw failure(code, "query") }
    return Statement(handle)
  }

  private func execute(_ sql: String) throws {
    let code = sqlite3_exec(db, sql, nil, nil, nil)
    guard code == SQLITE_OK else { throw failure(code, "statement") }
  }

  /// Runs a statement to completion, calling `row` for each result row.
  private func run(_ statement: Statement, row: ((Statement) -> Void)? = nil) throws {
    while true {
      let code = sqlite3_step(statement.handle)
      if code == SQLITE_ROW { row?(statement); continue }
      if code == SQLITE_DONE { return }
      throw failure(code, "step")
    }
  }

  private func transaction(_ work: () throws -> Void) throws {
    try execute("BEGIN IMMEDIATE")
    do {
      try work()
      try execute("COMMIT")
    } catch {
      try? execute("ROLLBACK")
      throw error
    }
  }

  private func synchronized<T>(_ work: () throws -> T) rethrows -> T {
    lock.lock()
    defer { lock.unlock() }
    return try work()
  }

  // MARK: Writing

  func stamps() throws -> [String: FileStamp] {
    try synchronized {
      let statement = try prepare("SELECT id, path, size, mtime, embedder, text_hash FROM files")
      var result: [String: FileStamp] = [:]
      try run(statement) { row in
        guard let path = row.text(1) else { return }
        result[path] = FileStamp(id: row.int(0), size: row.int(2), modified: row.double(3), embedder: row.text(4), textHash: row.text(5))
      }
      return result
    }
  }

  /// Replaces everything stored about one file in a single transaction.
  func save(_ record: FileRecord, chunks: [(text: String, vector: [Float])], image: (embedder: String, vector: [Float])?) throws {
    try synchronized {
      try transaction {
        let remove = try prepare("DELETE FROM files WHERE path = ?")
        remove.bind(1, record.path)
        try run(remove)
        let insert = try prepare("""
          INSERT INTO files (path, size, mtime, kind, title, snippet, labels, indexed_at, embedder, text_hash, text_length, bytes_hash, minhash)
          VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
          """)
        insert.bind(1, record.path)
        insert.bind(2, record.size)
        insert.bind(3, record.modified)
        insert.bind(4, record.kind.rawValue)
        insert.bind(5, record.title)
        insert.bind(6, record.snippet)
        insert.bind(7, record.labels.joined(separator: ", "))
        insert.bind(8, Date().timeIntervalSince1970)
        insert.bind(9, record.embedder)
        insert.bind(10, record.textHash)
        insert.bind(11, Int64(record.textLength))
        insert.bind(12, record.bytesHash)
        insert.bind(13, record.minHash.isEmpty ? nil : MinHash.blob(record.minHash))
        try run(insert)
        let fileID = sqlite3_last_insert_rowid(db)
        let chunk = try prepare("INSERT INTO chunks (file_id, seq, text, vector) VALUES (?, ?, ?, ?)")
        for (seq, item) in chunks.enumerated() {
          sqlite3_reset(chunk.handle)
          chunk.bind(1, fileID)
          chunk.bind(2, Int64(seq))
          chunk.bind(3, item.text)
          chunk.bind(4, VectorMath.blob(item.vector))
          try run(chunk)
        }
        if let image {
          let statement = try prepare("INSERT INTO images (file_id, embedder, vector) VALUES (?, ?, ?)")
          statement.bind(1, fileID)
          statement.bind(2, image.embedder)
          statement.bind(3, VectorMath.blob(image.vector))
          try run(statement)
        }
      }
      cached = nil
    }
  }

  /// Records a new size and date for a file whose text didn’t change.
  func touch(path: String, size: Int64, modified: Double) throws {
    try synchronized {
      let statement = try prepare("UPDATE files SET size = ?, mtime = ?, indexed_at = ? WHERE path = ?")
      statement.bind(1, size)
      statement.bind(2, modified)
      statement.bind(3, Date().timeIntervalSince1970)
      statement.bind(4, path)
      try run(statement)
      cached = nil
    }
  }

  /// The stored passages of one file, for re-embedding with a different model.
  func chunkTexts(fileID: Int64) throws -> [(id: Int64, text: String)] {
    try synchronized {
      let statement = try prepare("SELECT id, text FROM chunks WHERE file_id = ? ORDER BY seq")
      statement.bind(1, fileID)
      var result: [(Int64, String)] = []
      try run(statement) { row in result.append((row.int(0), row.text(1) ?? "")) }
      return result
    }
  }

  func replaceVectors(fileID: Int64, embedder: String, vectors: [(id: Int64, vector: [Float])]) throws {
    try synchronized {
      try transaction {
        let update = try prepare("UPDATE chunks SET vector = ? WHERE id = ?")
        for item in vectors {
          sqlite3_reset(update.handle)
          update.bind(1, VectorMath.blob(item.vector))
          update.bind(2, item.id)
          try run(update)
        }
        let file = try prepare("UPDATE files SET embedder = ? WHERE id = ?")
        file.bind(1, embedder)
        file.bind(2, fileID)
        try run(file)
      }
      cached = nil
    }
  }

  func remove(paths: [String]) throws {
    guard !paths.isEmpty else { return }
    try synchronized {
      try transaction {
        let statement = try prepare("DELETE FROM files WHERE path = ?")
        for path in paths {
          sqlite3_reset(statement.handle)
          statement.bind(1, path)
          try run(statement)
        }
      }
      cached = nil
    }
  }

  func setMeta(_ key: String, _ value: String) {
    synchronized {
      do {
        let statement = try prepare("INSERT INTO meta (key, value) VALUES (?, ?) ON CONFLICT(key) DO UPDATE SET value = excluded.value")
        statement.bind(1, key)
        statement.bind(2, value)
        try run(statement)
      } catch {}
    }
  }

  func meta(_ key: String) -> String? {
    synchronized {
      guard let statement = try? prepare("SELECT value FROM meta WHERE key = ?") else { return nil }
      statement.bind(1, key)
      var value: String?
      try? run(statement) { value = $0.text(0) }
      return value
    }
  }

  /// Reclaims space after many removals, and folds the write-ahead log back in.
  func compact() {
    synchronized {
      try? execute("INSERT INTO chunk_words(chunk_words) VALUES ('optimize')")
      try? execute("PRAGMA wal_checkpoint(TRUNCATE)")
    }
  }

  // MARK: Reading

  /// The in-memory copy of the index, loaded on first use after any write.
  func snapshot() throws -> IndexSnapshot {
    try synchronized {
      if let cached { return cached }
      var files: [IndexSnapshot.File] = []
      let fileRows = try prepare("""
        SELECT id, path, size, mtime, indexed_at, kind, title, snippet, labels, text_length, bytes_hash, minhash FROM files ORDER BY id
        """)
      try run(fileRows) { row in
        let labels = (row.text(8) ?? "").split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        let title = row.text(6) ?? ""
        let path = row.text(1) ?? ""
        let name = ((path as NSString).lastPathComponent as NSString).deletingPathExtension
        files.append(IndexSnapshot.File(
          id: row.int(0), path: path, size: row.int(2),
          modified: Date(timeIntervalSince1970: row.double(3)), indexed: Date(timeIntervalSince1970: row.double(4)),
          kind: ContentKind(rawValue: row.text(5) ?? "") ?? .other, title: title, snippet: row.text(7) ?? "",
          labels: labels, textLength: Int(row.int(9)), bytesHash: row.text(10),
          minHash: row.data(11).map(MinHash.signature) ?? [],
          nameWords: Set(Lexicon.words(name + " " + title + " " + labels.joined(separator: " ")))
        ))
      }
      var fileIndex: [Int64: Int] = [:]
      for (i, file) in files.enumerated() { fileIndex[file.id] = i }

      var matrix: [Float] = []
      var chunkFile: [Int] = []
      var chunkIDs: [Int64] = []
      var dimension = 0
      let chunkRows = try prepare("SELECT id, file_id, vector FROM chunks ORDER BY file_id, seq")
      try run(chunkRows) { row in
        guard let blob = row.data(2), let file = fileIndex[row.int(1)] else { return }
        let vector = VectorMath.vector(blob)
        if dimension == 0 { dimension = vector.count }
        guard vector.count == dimension else { return }
        matrix.append(contentsOf: vector)
        chunkFile.append(file)
        chunkIDs.append(row.int(0))
      }
      var images: [(file: Int, vector: [Float])] = []
      let imageRows = try prepare("SELECT file_id, vector FROM images")
      try run(imageRows) { row in
        guard let blob = row.data(1), let file = fileIndex[row.int(0)] else { return }
        images.append((file, VectorMath.vector(blob)))
      }
      let snapshot = IndexSnapshot(files: files, dimension: dimension, matrix: matrix, chunkFile: chunkFile, chunkIDs: chunkIDs, images: images)
      cached = snapshot
      return snapshot
    }
  }

  func chunkText(id: Int64) -> String? {
    synchronized {
      guard let statement = try? prepare("SELECT text FROM chunks WHERE id = ?") else { return nil }
      statement.bind(1, id)
      var text: String?
      try? run(statement) { text = $0.text(0) }
      return text
    }
  }

  /// Passages containing the query’s words, best first, scored by BM25 (higher is better).
  func wordMatches(_ words: [String], limit: Int = 300) -> [(chunk: Int64, score: Double)] {
    guard !words.isEmpty else { return [] }
    // Each word quoted, so nothing in a query is read as FTS syntax.
    let query = words.map { "\"\($0.replacingOccurrences(of: "\"", with: ""))\"" }.joined(separator: " OR ")
    return synchronized {
      guard let statement = try? prepare("SELECT rowid, bm25(chunk_words) FROM chunk_words WHERE chunk_words MATCH ? ORDER BY bm25(chunk_words) LIMIT ?") else { return [] }
      statement.bind(1, query)
      statement.bind(2, Int64(limit))
      var result: [(Int64, Double)] = []
      do {
        try run(statement) { row in result.append((row.int(0), -row.double(1))) }
      } catch {
        return []
      }
      return result
    }
  }

  public func status() -> IndexStatus {
    let counts: (Int, Int, Int) = synchronized {
      func count(_ table: String) -> Int {
        guard let statement = try? prepare("SELECT count(*) FROM \(table)") else { return 0 }
        var value = 0
        try? run(statement) { value = Int($0.int(0)) }
        return value
      }
      return (count("files"), count("chunks"), count("images"))
    }
    var bytes: Int64 = 0
    for suffix in ["", "-wal", "-shm"] {
      if let size = (try? FileManager.default.attributesOfItem(atPath: location.path + suffix))?[.size] as? NSNumber {
        bytes += size.int64Value
      }
    }
    return IndexStatus(
      files: counts.0, chunks: counts.1, images: counts.2, databaseBytes: bytes,
      lastRun: meta("lastRun").flatMap(Double.init).map { Date(timeIntervalSince1970: $0) },
      lastRunSeconds: meta("lastRunSeconds").flatMap(Double.init),
      embedder: meta("embedder"), location: location.path
    )
  }
}

/// Word handling shared by indexing and search.
enum Lexicon {
  static let stopwords: Set<String> = [
    "a", "an", "and", "are", "as", "at", "be", "by", "for", "from", "has", "have", "i", "in", "is", "it", "its",
    "my", "of", "on", "or", "our", "that", "the", "this", "to", "was", "were", "with", "me", "find", "show",
    "file", "files", "about", "some", "any", "all", "what", "where", "which", "who", "when", "how",
  ]

  /// Lower-cased words of two letters or more, without stopwords.
  static func words(_ text: String) -> [String] {
    text.lowercased()
      .folding(options: .diacriticInsensitive, locale: nil)
      .split { !$0.isLetter && !$0.isNumber }
      .map(String.init)
      .filter { $0.count >= 2 && !stopwords.contains($0) }
  }

  /// A crude stem so "leases" meets "lease" and "screenshots" meets "screenshot".
  static func stem(_ word: String) -> String {
    for suffix in ["ing", "es", "s", "ed"] where word.count > suffix.count + 3 && word.hasSuffix(suffix) {
      return String(word.dropLast(suffix.count))
    }
    return word
  }
}
