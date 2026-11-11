import Accelerate
import Foundation

/// Searches the content index: by meaning, for files like a given one, and for groups of
/// near-identical files. Reads the index only; never opens the files themselves.
public struct ContentSearch: Sendable {
  public let store: IndexStore
  public let embedder: any TextEmbedder

  /// Euclidean distance between feature prints under which two pictures count as the
  /// same picture (Vision's own `distance(to:)` is this value squared). Calibrated on a
  /// 6016-pixel photo: resized, re-compressed, PNG and 95%-cropped copies measured
  /// 0.02–0.10, an 80% crop 0.13, a mirror image 0.17; the same artwork in another
  /// colour 0.28–0.35, a heavy crop 0.48, different pictures 0.55 and up. 0.25 keeps
  /// real copies and leaves out recolours, erring toward reporting too little.
  public static let imageThreshold: Float = 0.25
  /// Documents count as near-identical when their meaning vectors agree this closely
  /// (two drafts differing by one sentence measured 0.999, but unrelated short files
  /// reach 0.967, so the wording check below does the real work)…
  public static let documentCosine: Float = 0.97
  /// …their lengths are within this ratio…
  public static let documentLengthRatio = 0.8
  /// …and at least this share of their three-word phrases are the same.
  public static let documentWording = 0.5

  /// Weights for combining the signals in `search`.
  static let wordWeight = 0.2
  static let nameWeight = 0.3

  public init(store: IndexStore, embedder: any TextEmbedder) {
    self.store = store
    self.embedder = embedder
  }

  // MARK: Search

  /// Files whose contents match `query` by meaning, boosted when its words appear in the
  /// passage, the file name, title or labels. One hit per file, best first.
  public func search(_ query: String, limit: Int = 10, kinds: Set<ContentKind> = []) async -> [SearchHit] {
    guard let snapshot = try? store.snapshot(), !snapshot.files.isEmpty else { return [] }
    let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return [] }
    let fileCount = snapshot.files.count

    // Meaning: the best passage per file.
    var semantic = [Float](repeating: -1, count: fileCount)
    var semanticChunk = [Int](repeating: -1, count: fileCount)
    if let vector = try? await embedder.embed([trimmed]).first, vector.count == snapshot.dimension {
      // Every stored vector is normalised, so the dot product is the cosine.
      let scores = VectorMath.multiply(snapshot.matrix, rows: snapshot.chunkIDs.count, columns: snapshot.dimension, by: vector)
      for (row, score) in scores.enumerated() {
        let file = snapshot.chunkFile[row]
        if score > semantic[file] {
          semantic[file] = score
          semanticChunk[file] = row
        }
      }
    }

    // Words: passages that contain the query's words, and matches in names and labels.
    let words = Lexicon.words(trimmed)
    var wordScore = [Double](repeating: 0, count: fileCount)
    var wordChunk = [Int](repeating: -1, count: fileCount)
    let matches = store.wordMatches(words)
    let best = matches.map(\.score).max() ?? 0
    for match in matches {
      guard let row = snapshot.chunkIndex[match.chunk] else { continue }
      let file = snapshot.chunkFile[row]
      let normalized = best > 0 ? match.score / best : 0
      if normalized > wordScore[file] {
        wordScore[file] = normalized
        wordChunk[file] = row
      }
    }
    let stems = Set(words.map(Lexicon.stem))

    var hits: [SearchHit] = []
    for (index, file) in snapshot.files.enumerated() {
      if !kinds.isEmpty, !kinds.contains(file.kind) { continue }
      let nameStems = Set(file.nameWords.map(Lexicon.stem))
      let nameScore = stems.isEmpty ? 0 : Double(stems.intersection(nameStems).count) / Double(stems.count)
      let meaning = semantic[index] > -1 ? Double(semantic[index]) : 0
      let score = meaning + ContentSearch.wordWeight * wordScore[index] + ContentSearch.nameWeight * nameScore
      guard semantic[index] > -1 || wordScore[index] > 0 || nameScore > 0 else { continue }
      let row = wordChunk[index] >= 0 ? wordChunk[index] : semanticChunk[index]
      hits.append(hit(file, score: score, chunkRow: row, snapshot: snapshot, words: words))
    }
    hits.sort { $0.score > $1.score }
    return Array(hits.prefix(limit))
  }

  // MARK: Similar

  /// The indexed files closest to an indexed file: pictures by how they look, everything
  /// else by what it says.
  public func similar(to path: String, limit: Int = 10) -> [SearchHit] {
    guard let snapshot = try? store.snapshot(), let index = snapshot.pathIndex[Protection.clean(path)] else { return [] }
    let file = snapshot.files[index]
    if let own = snapshot.images.first(where: { $0.file == index })?.vector {
      var hits: [SearchHit] = []
      for image in snapshot.images where image.file != index && image.vector.count == own.count {
        let distance = Double(VectorMath.distance(own, image.vector))
        hits.append(hit(snapshot.files[image.file], score: 1 / (1 + distance), chunkRow: -1, snapshot: snapshot, words: []))
      }
      hits.sort { $0.score > $1.score }
      return Array(hits.prefix(limit))
    }
    let means = ContentSearch.fileMeans(snapshot)
    guard let own = means[index] else { return [] }
    var hits: [SearchHit] = []
    for (other, vector) in means.enumerated() where other != index {
      guard let vector, snapshot.files[other].kind != .image || file.kind == .image else { continue }
      hits.append(hit(snapshot.files[other], score: Double(VectorMath.dot(own, vector)), chunkRow: -1, snapshot: snapshot, words: []))
    }
    hits.sort { $0.score > $1.score }
    return Array(hits.prefix(limit))
  }

  // MARK: Lookalikes

  /// Groups of near-identical images and near-identical documents that aren't exact
  /// copies (the duplicate scan covers those). Report only: nothing is selected for
  /// removal. Pass `.image` or `.document` for one side; documents include PDFs, text
  /// and the other text kinds.
  public func lookalikes(kind: ContentKind? = nil) -> [LookalikeGroup] {
    guard let snapshot = try? store.snapshot() else { return [] }
    var groups: [LookalikeGroup] = []
    if kind == nil || kind == .image { groups += imageGroups(snapshot) }
    if kind != .image { groups += documentGroups(snapshot) }
    return groups.sorted { $0.totalBytes > $1.totalBytes }
  }

  private func imageGroups(_ snapshot: IndexSnapshot) -> [LookalikeGroup] {
    let images = snapshot.images
    var pairs: [(Int, Int, Double)] = []
    for i in 0..<images.count {
      for j in (i + 1)..<max(i + 1, images.count) where images[i].vector.count == images[j].vector.count {
        let distance = VectorMath.distance(images[i].vector, images[j].vector)
        guard distance < ContentSearch.imageThreshold else { continue }
        let a = images[i].file, b = images[j].file
        if ContentSearch.identical(snapshot.files[a], snapshot.files[b]) { continue }
        pairs.append((a, b, Double(distance)))
      }
    }
    return ContentSearch.group(pairs, kind: .image, snapshot: snapshot)
  }

  private func documentGroups(_ snapshot: IndexSnapshot) -> [LookalikeGroup] {
    let means = ContentSearch.fileMeans(snapshot)
    let candidates = means.indices.filter { means[$0] != nil && snapshot.files[$0].kind != .image && snapshot.files[$0].textLength >= 200 }
    let dimension = snapshot.dimension
    guard candidates.count > 1, dimension > 0 else { return [] }
    var matrix: [Float] = []
    matrix.reserveCapacity(candidates.count * dimension)
    for index in candidates { matrix.append(contentsOf: means[index] ?? []) }
    var pairs: [(Int, Int, Double)] = []
    for (position, index) in candidates.enumerated() {
      guard let own = means[index] else { continue }
      let scores = VectorMath.multiply(matrix, rows: candidates.count, columns: dimension, by: own)
      for other in (position + 1)..<candidates.count where scores[other] >= ContentSearch.documentCosine {
        let a = snapshot.files[index], b = snapshot.files[candidates[other]]
        let shorter = Double(min(a.textLength, b.textLength)), longer = Double(max(a.textLength, b.textLength))
        guard longer > 0, shorter / longer >= ContentSearch.documentLengthRatio else { continue }
        guard MinHash.similarity(a.minHash, b.minHash) >= ContentSearch.documentWording else { continue }
        if ContentSearch.identical(a, b) { continue }
        pairs.append((index, candidates[other], Double(1 - scores[other])))
      }
    }
    return ContentSearch.group(pairs, kind: .document, snapshot: snapshot)
  }

  /// Byte-for-byte copies, which the exact-duplicate scan reports instead.
  static func identical(_ a: IndexSnapshot.File, _ b: IndexSnapshot.File) -> Bool {
    guard let x = a.bytesHash, let y = b.bytesHash else { return false }
    return x == y && a.size == b.size
  }

  /// Joins pairs into groups, keeping groups with at least two different files.
  static func group(_ pairs: [(Int, Int, Double)], kind: ContentKind, snapshot: IndexSnapshot) -> [LookalikeGroup] {
    var parent: [Int: Int] = [:]
    func root(_ x: Int) -> Int {
      var x = x
      while let p = parent[x], p != x { parent[x] = parent[p] ?? p; x = p }
      return x
    }
    for (a, b, _) in pairs {
      parent[a] = parent[a] ?? a
      parent[b] = parent[b] ?? b
      let ra = root(a), rb = root(b)
      if ra != rb { parent[rb] = ra }
    }
    var members: [Int: [Int]] = [:]
    for node in parent.keys { members[root(node), default: []].append(node) }
    var spread: [Int: Double] = [:]
    for (a, _, distance) in pairs { spread[root(a)] = max(spread[root(a)] ?? 0, distance) }
    return members.compactMap { key, nodes in
      let files = nodes.map { snapshot.files[$0] }.sorted { $0.modified < $1.modified }
      guard Set(files.map { $0.bytesHash ?? $0.path }).count >= 2 else { return nil }
      return LookalikeGroup(
        kind: kind, spread: spread[key] ?? 0,
        members: files.map { LookalikeMember(path: $0.path, size: $0.size, modified: $0.modified) }
      )
    }
  }

  // MARK: Describe

  /// Kind, title, labels and snippet for one indexed file, for the assistant.
  ///
  /// Privacy: the snippet and labels come from inside the file. Callers may pass this to
  /// an assistant that runs in the cloud only when `config.assistant.shareExcerpts` is
  /// true; otherwise share the kind and title at most, or use an on-device model.
  public func describe(path: String) -> FileDescription? {
    guard let snapshot = try? store.snapshot(), let index = snapshot.pathIndex[Protection.clean(path)] else { return nil }
    let file = snapshot.files[index]
    return FileDescription(
      path: file.path, kind: file.kind, title: file.title, labels: file.labels, snippet: file.snippet,
      size: file.size, modified: file.modified, indexed: file.indexed
    )
  }

  // MARK: Helpers

  private func hit(_ file: IndexSnapshot.File, score: Double, chunkRow: Int, snapshot: IndexSnapshot, words: [String]) -> SearchHit {
    var snippet = file.snippet
    if chunkRow >= 0, let text = store.chunkText(id: snapshot.chunkIDs[chunkRow]) {
      snippet = ContentSearch.excerpt(text, around: words)
    }
    return SearchHit(
      path: file.path, score: score, kind: file.kind, title: file.title, snippet: snippet,
      labels: file.labels, size: file.size, modified: file.modified
    )
  }

  /// About 300 characters of a passage, starting near the first query word it contains.
  static func excerpt(_ text: String, around words: [String], length: Int = 300) -> String {
    let flat = text.replacingOccurrences(of: "\n", with: " ")
    let lower = flat.lowercased()
    var start = lower.startIndex
    for word in words {
      if let range = lower.range(of: Lexicon.stem(word)) {
        start = lower.index(range.lowerBound, offsetBy: -min(60, lower.distance(from: lower.startIndex, to: range.lowerBound)))
        break
      }
    }
    let offset = min(lower.distance(from: lower.startIndex, to: start), flat.count)
    let begin = flat.index(flat.startIndex, offsetBy: offset)
    let piece = flat[begin...].prefix(length)
    return (offset > 0 ? "…" : "") + piece.trimmingCharacters(in: .whitespaces) + (piece.count == length ? "…" : "")
  }

  /// Each file's average passage vector, normalised.
  static func fileMeans(_ snapshot: IndexSnapshot) -> [[Float]?] {
    let dimension = snapshot.dimension
    var sums = [[Float]?](repeating: nil, count: snapshot.files.count)
    var counts = [Int](repeating: 0, count: snapshot.files.count)
    guard dimension > 0 else { return sums }
    for row in 0..<snapshot.chunkIDs.count {
      let file = snapshot.chunkFile[row]
      let vector = Array(snapshot.vector(ofChunk: row))
      sums[file] = sums[file].map { vDSP.add($0, vector) } ?? vector
      counts[file] += 1
    }
    return sums.enumerated().map { index, sum in
      guard let sum, counts[index] > 0 else { return nil }
      let average = vDSP.divide(sum, Float(counts[index]))
      return VectorMath.normalized(average)
    }
  }
}
