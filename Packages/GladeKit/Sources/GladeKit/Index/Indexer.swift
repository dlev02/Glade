import Foundation

/// Builds and updates the content index. It only runs when explicitly started, reads one
/// file at a time at utility priority, checks for cancellation between files, and never
/// writes to, moves or changes any file it reads.
public struct Indexer: Sendable {
  public let store: IndexStore
  public let embedder: any TextEmbedder
  public let images: ImageEmbedder
  /// Seconds one file may take before it's given up on.
  public var perFileTimeout: Double = 30
  /// Characters of each file kept as its snippet.
  static let snippetLength = 300

  public init(store: IndexStore, embedder: any TextEmbedder, images: ImageEmbedder = ImageEmbedder()) {
    self.store = store
    self.embedder = embedder
    self.images = images
  }

  /// A file the walk found worth reading.
  struct Candidate: Sendable {
    var path: String
    var size: Int64
    var modified: Double
    var kind: ContentKind
    var isPackage: Bool
  }

  /// Indexes `config.index.folders`. Entries under those folders that weren't seen are
  /// removed, as are entries anywhere that are gone or have become protected.
  public func run(
    config: GladeConfig,
    protection: Protection? = nil,
    cancel: CancelFlag = CancelFlag(),
    progress: @escaping @Sendable (IndexProgress) -> Void = { _ in }
  ) async -> IndexReport {
    let protection = protection ?? Protection(config: config)
    let worker = self
    return await Task.detached(priority: .utility) {
      await worker.perform(config: config, protection: protection, cancel: cancel, progress: progress)
    }.value
  }

  public func status() -> IndexStatus { store.status() }

  /// The configured folders with `~` expanded and duplicates and nested folders removed.
  static func roots(_ folders: [String], protection: Protection) -> [String] {
    let expanded = folders.map { Protection.clean(Protection.expand($0, home: protection.home)) }
    var roots: [String] = []
    for folder in expanded.sorted() where !roots.contains(where: { folder == $0 || folder.hasPrefix($0 + "/") }) {
      var info = stat()
      guard lstat(folder, &info) == 0, (info.st_mode & S_IFMT) == S_IFDIR else {
        Log.info(.index, "Not indexing \(folder): not a folder")
        continue
      }
      guard protection.canScan(folder) else {
        Log.info(.index, "Not indexing \(folder): protected")
        continue
      }
      roots.append(folder)
    }
    return roots
  }

  private func perform(config: GladeConfig, protection: Protection, cancel: CancelFlag, progress: @escaping @Sendable (IndexProgress) -> Void) async -> IndexReport {
    let roots = Indexer.roots(config.index.folders, protection: protection)
    var report = IndexReport(folders: roots, started: Date(), finished: Date(), embedder: embedder.id)
    let extractor = TextExtractor(readTextInImages: config.index.readTextInImages, images: images)

    let (candidates, walkCounts) = Indexer.collect(roots, protection: protection, cancel: cancel)
    report.skippedProtected = walkCounts.protected
    report.skippedCloud = walkCounts.cloud
    report.skippedUnsupported = walkCounts.unsupported
    report.seen = candidates.count + walkCounts.protected + walkCounts.cloud + walkCounts.unsupported

    let stamps: [String: FileStamp]
    do { stamps = try store.stamps() } catch {
      report.failed = candidates.count
      report.finished = Date()
      return report
    }
    var seen = Set<String>()
    var warmedUp = false

    for (number, candidate) in candidates.enumerated() {
      if cancel.isCancelled || Task.isCancelled { report.cancelled = true; break }
      seen.insert(candidate.path)
      progress(IndexProgress(finished: number, total: candidates.count, path: candidate.path))
      let stamp = stamps[candidate.path]

      if let stamp, stamp.size == candidate.size, stamp.modified == candidate.modified {
        if stamp.embedder == embedder.id {
          report.skippedUnchanged += 1
        } else if await reembed(stamp, report: &report) {
          report.indexed += 1
        } else {
          report.failed += 1
        }
        continue
      }
      if candidate.size > TextExtractor.maxFileBytes {
        report.skippedTooLarge += 1
        if stamp != nil { seen.remove(candidate.path) }
        continue
      }

      // Images always need Vision, so load its models first; loading can take longer
      // than one file is allowed. Most PDFs have a text layer and never need it.
      if !warmedUp, candidate.kind == .image {
        report.imageSeconds += await Indexer.timed { await extractor.warmUp() }
        warmedUp = true
      }
      var began = Date()
      var extraction: Extraction
      do {
        do {
          extraction = try await extract(candidate, extractor: extractor, began: began)
        } catch ExtractionError.timedOut where !warmedUp && candidate.kind == .pdf {
          // A scan that needed text recognition before Vision was ready: load it, try again.
          report.imageSeconds += await Indexer.timed { await extractor.warmUp() }
          warmedUp = true
          began = Date()
          extraction = try await extract(candidate, extractor: extractor, began: began)
        }
      } catch {
        report.failed += 1
        Log.warning(.index, "Couldn’t index \(candidate.path): \(error)")
        rememberFailure(candidate)
        continue
      }
      let read = Date().timeIntervalSince(began)
      if candidate.kind == .image { report.imageSeconds += read } else { report.extractSeconds += read }

      do {
        let textHash = SafeRead.fingerprint(extraction.title + "\u{0}" + extraction.labels.joined(separator: ",") + "\u{0}" + extraction.text)
        if let stamp, stamp.textHash == textHash, stamp.embedder == embedder.id {
          // Saved again with the same words: nothing to re-embed.
          try store.touch(path: candidate.path, size: candidate.size, modified: candidate.modified)
          report.skippedUnchanged += 1
          continue
        }
        let embedStart = Date()
        let saved = try await save(candidate, extraction, textHash: textHash)
        report.embedSeconds += Date().timeIntervalSince(embedStart)
        if saved { report.indexed += 1 } else { report.failed += 1 }
      } catch {
        report.failed += 1
        Log.warning(.index, "Couldn’t index \(candidate.path): \(error)")
      }
    }

    if !report.cancelled {
      var stale: [String] = []
      for path in stamps.keys where !seen.contains(path) {
        let underRoot = roots.contains { path.hasPrefix($0 + "/") }
        if underRoot || !protection.canScan(path) || !PersonalWalk.exists(path) { stale.append(path) }
      }
      do {
        try store.remove(paths: stale)
        report.removed = stale.count
      } catch {
        Log.warning(.index, "Couldn’t remove \(stale.count) old index entries: \(error)")
      }
      if report.removed > 0 || report.indexed > 0 { store.compact() }
    }

    report.finished = Date()
    store.setMeta("lastRun", String(report.finished.timeIntervalSince1970))
    store.setMeta("lastRunSeconds", String(report.seconds))
    store.setMeta("embedder", embedder.id)
    Log.info(.index, String(
      format: "Index run%@: %d seen, %d indexed, %d unchanged, %d protected, %d too large, %d unsupported, %d in the cloud, %d failed, %d removed in %.1fs (reading %.1fs, images %.1fs, embedding %.1fs)",
      report.cancelled ? " cancelled" : "", report.seen, report.indexed, report.skippedUnchanged, report.skippedProtected,
      report.skippedTooLarge, report.skippedUnsupported, report.skippedCloud, report.failed, report.removed,
      report.seconds, report.extractSeconds, report.imageSeconds, report.embedSeconds
    ))
    return report
  }

  /// Chunks, embeds and stores one file.
  private func save(_ candidate: Candidate, _ extraction: Extraction, textHash: String) async throws -> Bool {
    let text = TextChunker.normalize(extraction.text)
    var passages = TextChunker.chunks(text)
    let labels = extraction.labels.joined(separator: ", ")
    if passages.isEmpty {
      // Nothing readable inside: the name (and an image's labels) is still searchable.
      passages = [labels.isEmpty ? extraction.title : "\(extraction.title). \(labels)"]
    }
    let inputs = passages.map { Indexer.embeddingInput(title: extraction.title, labels: labels, passage: $0) }
    let vectors = try await embedder.embed(inputs)
    guard vectors.count == passages.count else { return false }
    let snippetSource = text.isEmpty ? labels : text
    let record = FileRecord(
      path: candidate.path, size: candidate.size, modified: candidate.modified, kind: extraction.kind,
      title: extraction.title, snippet: String(snippetSource.prefix(Indexer.snippetLength)),
      labels: extraction.labels, embedder: embedder.id, textHash: textHash, textLength: text.count,
      bytesHash: extraction.bytesHash, minHash: MinHash.signature(text)
    )
    try store.save(
      record, chunks: zip(passages, vectors).map { ($0, $1) },
      image: extraction.imageVector.map { (images.id, $0) }
    )
    return true
  }

  private func extract(_ candidate: Candidate, extractor: TextExtractor, began: Date) async throws -> Extraction {
    try await Indexer.withTimeout(perFileTimeout) { [extractor, perFileTimeout] in
      try await extractor.extract(candidate.path, kind: candidate.kind, isPackage: candidate.isPackage, deadline: began.addingTimeInterval(perFileTimeout))
    }
  }

  static func timed(_ work: () async -> Void) async -> Double {
    let started = Date()
    await work()
    return Date().timeIntervalSince(started)
  }

  /// Records a file that couldn't be read, by name only, so later runs skip it until it
  /// changes instead of failing on it every time.
  private func rememberFailure(_ candidate: Candidate) {
    let name = (candidate.path as NSString).lastPathComponent
    let record = FileRecord(
      path: candidate.path, size: candidate.size, modified: candidate.modified, kind: candidate.kind,
      title: TextExtractor.title(fromName: name), snippet: "", labels: [], embedder: embedder.id,
      textHash: "unreadable", textLength: 0, bytesHash: nil, minHash: []
    )
    try? store.save(record, chunks: [], image: nil)
  }

  /// Embeds stored passages again after the text model changed, without reading the file.
  private func reembed(_ stamp: FileStamp, report: inout IndexReport) async -> Bool {
    do {
      let snapshot = try store.snapshot()
      guard let index = snapshot.fileIndex[stamp.id] else { return false }
      let file = snapshot.files[index]
      let chunks = try store.chunkTexts(fileID: stamp.id)
      let labels = file.labels.joined(separator: ", ")
      let started = Date()
      let vectors = try await embedder.embed(chunks.map { Indexer.embeddingInput(title: file.title, labels: labels, passage: $0.text) })
      report.embedSeconds += Date().timeIntervalSince(started)
      guard vectors.count == chunks.count else { return false }
      try store.replaceVectors(fileID: stamp.id, embedder: embedder.id, vectors: zip(chunks, vectors).map { ($0.id, $1) })
      return true
    } catch {
      Log.warning(.index, "Couldn’t re-embed index entry \(stamp.id): \(error)")
      return false
    }
  }

  /// Each passage is embedded with the file's title in front, so a passage from "Chicago
  /// lease.pdf" still knows it belongs to a lease.
  static func embeddingInput(title: String, labels: String, passage: String) -> String {
    if passage.hasPrefix(title) { return passage }
    return labels.isEmpty ? "\(title)\n\(passage)" : "\(title) (\(labels))\n\(passage)"
  }

  struct WalkCounts: Sendable {
    var protected = 0
    var cloud = 0
    var unsupported = 0
  }

  /// One pass over the folders, with the same pruning as the large-file scan: no
  /// hidden, protected, dependency or build folders, no app bundles, no cloud
  /// placeholders. Readable packages (Pages, Keynote, Numbers, RTFD) are taken whole.
  static func collect(_ roots: [String], protection: Protection, cancel: CancelFlag) -> ([Candidate], WalkCounts) {
    let rules = PersonalWalk(home: protection.home, protection: protection)
    var found: [Candidate] = []
    var counts = WalkCounts()
    var links = Set<FileIdentity>()
    var counter = 0
    FileHashing.withoutAccessTimeUpdates {
      DiskWalk.walk(roots) { entry in
        counter += 1
        if counter & 0x3FF == 0, cancel.isCancelled { return .stop }
        let name = entry.name
        if entry.isDirectory {
          guard entry.depth > 0 else { return .proceed }
          let ext = (name as NSString).pathExtension.lowercased()
          if TextExtractor.readablePackages.contains(ext), !name.hasPrefix(".") {
            if entry.isDataless { counts.cloud += 1; return .skip }
            if protection.isProtectedName(name) || !protection.canScan(entry.path) { counts.protected += 1; return .skip }
            if let kind = TextExtractor.kind(for: name, isDirectory: true) {
              let size = DiskWalk.measure([entry.path]).bytes
              found.append(Candidate(path: entry.path, size: size, modified: Double(entry.modified.timeIntervalSince1970), kind: kind, isPackage: true))
            }
            return .skip
          }
          if !name.hasPrefix("."), protection.isProtectedName(name) { counts.protected += 1; return .skip }
          return rules.shouldPrune(entry) ? .skip : .proceed
        }
        // "~$Report.docx" is Office's lock file for an open document, not a document.
        if entry.isSymlink || name.hasPrefix(".") || name.hasPrefix("~$") {
          if protection.isProtectedName(name) { counts.protected += 1 }
          return .proceed
        }
        if protection.isProtectedName(name) || !protection.canScan(entry.path) { counts.protected += 1; return .proceed }
        guard let kind = TextExtractor.kind(for: name) else { counts.unsupported += 1; return .proceed }
        if entry.isDataless { counts.cloud += 1; return .proceed }
        if entry.linkCount > 1, !links.insert(FileIdentity(device: entry.device, inode: entry.inode)).inserted { return .proceed }
        // Seconds with fractions, so a quick re-save is noticed.
        let modified = Double(entry.entry.pointee.fts_statp.pointee.st_mtimespec.tv_sec)
          + Double(entry.entry.pointee.fts_statp.pointee.st_mtimespec.tv_nsec) / 1e9
        found.append(Candidate(path: entry.path, size: entry.length, modified: modified, kind: kind, isPackage: false))
        return .proceed
      }
    }
    return (found, counts)
  }

  /// Runs `work`, giving up after `seconds`. Work that overruns is abandoned, not
  /// stopped, so it also checks a deadline of its own between pages.
  static func withTimeout<T: Sendable>(_ seconds: Double, _ work: @escaping @Sendable () async throws -> T) async throws -> T {
    let gate = OnceGate<T>()
    return try await withCheckedThrowingContinuation { continuation in
      gate.set(continuation)
      let task = Task(priority: .utility) {
        do { gate.resume(.success(try await work())) } catch { gate.resume(.failure(error)) }
      }
      let timer = Task(priority: .utility) {
        do { try await Task.sleep(for: .seconds(seconds)) } catch { return }
        task.cancel()
        gate.resume(.failure(ExtractionError.timedOut))
      }
      Task(priority: .utility) {
        _ = await task.result
        timer.cancel()
      }
    }
  }
}

/// Resumes a continuation exactly once, from whichever side finishes first.
final class OnceGate<T: Sendable>: @unchecked Sendable {
  private let lock = NSLock()
  private var continuation: CheckedContinuation<T, Error>?
  private var pending: Result<T, Error>?

  func set(_ continuation: CheckedContinuation<T, Error>) {
    lock.lock()
    if let pending {
      lock.unlock()
      continuation.resume(with: pending)
      return
    }
    self.continuation = continuation
    lock.unlock()
  }

  func resume(_ result: Result<T, Error>) {
    lock.lock()
    guard let continuation else {
      if pending == nil { pending = result }
      lock.unlock()
      return
    }
    self.continuation = nil
    pending = result
    lock.unlock()
    continuation.resume(with: result)
  }
}
