import Accelerate
import Foundation
import NaturalLanguage
import Vision

/// Turns text into vectors whose closeness reflects closeness in meaning. The index
/// records which embedder made each vector (`id`) and re-embeds when it changes, so a
/// different model can be added later without touching the store or the search.
public protocol TextEmbedder: Sendable {
  /// Stable for as long as the vectors stay comparable. Change it when the model changes.
  var id: String { get }
  var dimension: Int { get }
  /// One L2-normalised vector per text, in order.
  func embed(_ texts: [String]) async throws -> [[Float]]
}

public enum EmbeddingError: Error, CustomStringConvertible {
  case unavailable(String)

  public var description: String {
    switch self {
    case .unavailable(let reason): "Embedding unavailable: \(reason)"
    }
  }
}

/// Apple's built-in contextual embedding (a BERT-style model that ships with macOS),
/// mean-pooled over its token vectors. Falls back to the older sentence embedding when
/// the contextual model's assets can't be fetched. Everything runs on this Mac.
public actor AppleTextEmbedder: TextEmbedder {
  public nonisolated let id: String
  public nonisolated let dimension = 512
  private let contextual: Bool
  private var models: [String: NLContextualEmbedding] = [:]
  private var sentence: NLEmbedding?

  /// Makes sure the model is on this Mac (asking the system to fetch it if needed) and
  /// picks the contextual model or the fallback.
  public static func load() async -> AppleTextEmbedder {
    if let model = NLContextualEmbedding(script: .latin) {
      if model.hasAvailableAssets { return AppleTextEmbedder(contextual: true) }
      do {
        let result = try await model.requestAssets()
        if result == .available { return AppleTextEmbedder(contextual: true) }
        Log.warning(.index, "The contextual text model isn’t available (\(result)); using the sentence embedding")
      } catch {
        Log.warning(.index, "The contextual text model couldn’t be fetched (\(error)); using the sentence embedding")
      }
    } else {
      Log.warning(.index, "No contextual text model on this Mac; using the sentence embedding")
    }
    return AppleTextEmbedder(contextual: false)
  }

  init(contextual: Bool) {
    self.contextual = contextual
    id = contextual ? "apple.contextual.meanpool.1" : "apple.sentence.1"
  }

  public func embed(_ texts: [String]) async throws -> [[Float]] {
    try texts.map { try embedOne($0) }
  }

  private func embedOne(_ text: String) throws -> [Float] {
    let language = AppleTextEmbedder.language(of: text)
    if contextual {
      let model = try self.model(for: language)
      // Ask the model for the language it was given when it supports it.
      let tagged = model.languages.contains(language) ? language : nil
      let result = try model.embeddingResult(for: text, language: tagged)
      var sum = [Double](repeating: 0, count: model.dimension)
      var count = 0
      result.enumerateTokenVectors(in: text.startIndex..<text.endIndex) { vector, _ in
        let n = min(vector.count, sum.count)
        vector.withUnsafeBufferPointer { source in
          sum.withUnsafeMutableBufferPointer { target in
            guard let s = source.baseAddress, let t = target.baseAddress else { return }
            vDSP_vaddD(t, 1, s, 1, t, 1, vDSP_Length(n))
          }
        }
        count += 1
        return true
      }
      guard count > 0 else { return [Float](repeating: 0, count: dimension) }
      return VectorMath.normalized(sum.prefix(dimension).map { Float($0 / Double(count)) })
    }
    if sentence == nil { sentence = NLEmbedding.sentenceEmbedding(for: .english) }
    guard let sentence else { throw EmbeddingError.unavailable("no sentence embedding for English") }
    guard let vector = sentence.vector(for: text) else { return [Float](repeating: 0, count: dimension) }
    var floats = vector.map(Float.init)
    if floats.count != dimension { floats = Array(floats.prefix(dimension)) + [Float](repeating: 0, count: max(0, dimension - floats.count)) }
    return VectorMath.normalized(floats)
  }

  /// One loaded model per script, kept for the life of the embedder.
  private func model(for language: NLLanguage) throws -> NLContextualEmbedding {
    let model = NLContextualEmbedding(language: language) ?? NLContextualEmbedding(language: .english)
    guard let model else { throw EmbeddingError.unavailable("no contextual model") }
    if let loaded = models[model.modelIdentifier] { return loaded }
    try model.load()
    models[model.modelIdentifier] = model
    return model
  }

  /// The text's dominant language, falling back to English when it's unclear.
  static func language(of text: String) -> NLLanguage {
    let recognizer = NLLanguageRecognizer()
    recognizer.processString(String(text.prefix(1000)))
    guard let language = recognizer.dominantLanguage, language != .undetermined else { return .english }
    return language
  }
}

/// Vision's image feature print: a vector where near-identical pictures land close
/// together, whatever their size or compression.
public struct ImageEmbedder: Sendable {
  public let id = "vision.featureprint.1"

  public init() {}

  public func featurePrint(_ image: CGImage) async throws -> [Float] {
    let request = GenerateImageFeaturePrintRequest()
    let observation = try await request.perform(on: image)
    return observation.data.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
  }
}

/// Splits text into passages of a few sentences so each one fits the embedding model
/// (about 256 tokens) and a match points at a specific part of a document.
public enum TextChunker {
  public static let target = 750
  public static let maximum = 900
  public static let overlap = 120
  /// Long documents are sampled evenly down to this many passages.
  public static let perFile = 40

  public static func chunks(_ raw: String, limit: Int = perFile) -> [String] {
    let text = normalize(raw)
    guard !text.isEmpty else { return [] }
    var units: [String] = []
    for paragraph in text.components(separatedBy: "\n\n") {
      let trimmed = paragraph.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !trimmed.isEmpty else { continue }
      if trimmed.count <= maximum {
        units.append(trimmed)
      } else {
        units.append(contentsOf: sentences(trimmed).flatMap(hardSplit))
      }
    }
    var chunks: [String] = []
    var current = ""
    for unit in units {
      if current.isEmpty {
        current = unit
      } else if current.count + unit.count + 1 <= maximum, current.count < target {
        current += (current.hasSuffix("\n") ? "" : "\n") + unit
      } else {
        chunks.append(current)
        // Carry the end of the previous passage over so a sentence cut at the edge
        // still has its context.
        let tail = String(current.suffix(overlap))
        let start = tail.firstIndex(where: { $0 == " " || $0 == "\n" }).map { tail.index(after: $0) } ?? tail.startIndex
        let carried = String(tail[start...])
        current = carried.count + unit.count + 1 <= maximum ? carried + " " + unit : unit
      }
    }
    if !current.isEmpty { chunks.append(current) }
    guard chunks.count > limit, limit > 0 else { return chunks }
    return (0..<limit).map { chunks[$0 * chunks.count / limit] }
  }

  /// Collapses runs of spaces and blank lines, keeping paragraph breaks.
  static func normalize(_ text: String) -> String {
    var output = ""
    output.reserveCapacity(text.utf8.count)
    var spaces = 0
    var newlines = 0
    for scalar in text.unicodeScalars {
      if scalar == "\n" || scalar == "\r" || scalar == "\u{2029}" || scalar == "\u{0C}" {
        newlines += scalar == "\r" ? 0 : 1
        spaces = 0
      } else if scalar == " " || scalar == "\t" || scalar == "\u{A0}" || scalar.properties.isWhitespace {
        spaces += 1
      } else if scalar.properties.generalCategory == .control || scalar == "\u{FFFC}" {
        continue
      } else {
        if newlines > 0, !output.isEmpty {
          output += newlines > 1 ? "\n\n" : "\n"
        } else if spaces > 0, !output.isEmpty {
          output += " "
        }
        newlines = 0
        spaces = 0
        output.unicodeScalars.append(scalar)
      }
    }
    return output
  }

  private static func sentences(_ text: String) -> [String] {
    let tokenizer = NLTokenizer(unit: .sentence)
    tokenizer.string = text
    var result: [String] = []
    tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
      let sentence = text[range].trimmingCharacters(in: .whitespacesAndNewlines)
      if !sentence.isEmpty { result.append(sentence) }
      return true
    }
    return result.isEmpty ? [text] : result
  }

  /// Cuts a run of text with no sentence breaks (a table, a log) at spaces.
  private static func hardSplit(_ text: String) -> [String] {
    guard text.count > maximum else { return [text] }
    var pieces: [String] = []
    var rest = Substring(text)
    while rest.count > maximum {
      let window = rest.prefix(target)
      let cut = window.lastIndex(of: " ") ?? window.endIndex
      pieces.append(String(rest[..<cut]))
      rest = rest[cut...].drop(while: { $0 == " " })
    }
    if !rest.isEmpty { pieces.append(String(rest)) }
    return pieces
  }
}

/// Small vector helpers over Accelerate.
enum VectorMath {
  static func normalized(_ vector: [Float]) -> [Float] {
    var norm: Float = 0
    vDSP_svesq(vector, 1, &norm, vDSP_Length(vector.count))
    norm = norm.squareRoot()
    guard norm > 0 else { return vector }
    return vDSP.divide(vector, norm)
  }

  static func dot(_ a: [Float], _ b: [Float]) -> Float {
    vDSP.dot(a, b)
  }

  static func distance(_ a: [Float], _ b: [Float]) -> Float {
    vDSP.distanceSquared(a, b).squareRoot()
  }

  /// `matrix` (rows × columns, row-major) times `vector`.
  static func multiply(_ matrix: [Float], rows: Int, columns: Int, by vector: [Float]) -> [Float] {
    guard rows > 0 else { return [] }
    var result = [Float](repeating: 0, count: rows)
    matrix.withUnsafeBufferPointer { m in
      vector.withUnsafeBufferPointer { v in
        result.withUnsafeMutableBufferPointer { r in
          guard let mp = m.baseAddress, let vp = v.baseAddress, let rp = r.baseAddress else { return }
          vDSP_mmul(mp, 1, vp, 1, rp, 1, vDSP_Length(rows), 1, vDSP_Length(columns))
        }
      }
    }
    return result
  }

  static func blob(_ vector: [Float]) -> Data {
    vector.withUnsafeBufferPointer { Data(buffer: $0) }
  }

  static func vector(_ data: Data) -> [Float] {
    data.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
  }
}

/// A compact sketch of a text's word triples. Two texts whose sketches mostly agree
/// share most of their wording, which tells near-identical documents apart from ones
/// that are merely about the same thing.
enum MinHash {
  static let count = 64

  static func signature(_ text: String) -> [UInt32] {
    let words = text.lowercased().split { !$0.isLetter && !$0.isNumber }
    guard words.count >= 3 else { return [] }
    var signature = [UInt32](repeating: .max, count: count)
    for i in 0..<(words.count - 2) {
      var base: UInt64 = 0xcbf2_9ce4_8422_2325
      for word in words[i...(i + 2)] {
        for byte in word.utf8 { base = (base ^ UInt64(byte)) &* 0x100_0000_01b3 }
        base = (base ^ 0x20) &* 0x100_0000_01b3
      }
      for k in 0..<count {
        var h = base ^ (UInt64(k) &* 0x9E37_79B9_7F4A_7C15)
        h ^= h >> 33
        h = h &* 0xff51_afd7_ed55_8ccd
        h ^= h >> 33
        let value = UInt32(truncatingIfNeeded: h)
        if value < signature[k] { signature[k] = value }
      }
    }
    return signature
  }

  /// The estimated share of word triples the two texts have in common.
  static func similarity(_ a: [UInt32], _ b: [UInt32]) -> Double {
    guard a.count == count, b.count == count else { return 0 }
    var same = 0
    for k in 0..<count where a[k] == b[k] { same += 1 }
    return Double(same) / Double(count)
  }

  static func blob(_ signature: [UInt32]) -> Data {
    signature.withUnsafeBufferPointer { Data(buffer: $0) }
  }

  static func signature(_ data: Data) -> [UInt32] {
    data.withUnsafeBytes { Array($0.bindMemory(to: UInt32.self)) }
  }
}
