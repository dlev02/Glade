import ArgumentParser
import Foundation
import GladeKit

/// Options shared by the content-index commands.
struct IndexLocation: ParsableArguments {
  @Option(name: .long, help: ArgumentHelp("Use this index database instead of Glade's own (for experiments).", visibility: .hidden))
  var database: String?

  var url: URL {
    database.map { URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath) } ?? GladePaths.index
  }

  func open() throws -> IndexStore {
    do {
      return try IndexStore(location: url)
    } catch {
      throw ValidationError("The index couldn’t be opened: \(error)")
    }
  }
}

struct Index: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    abstract: "Build or update the on-device content index. Reads files; changes nothing.",
    discussion: "Indexes the folders in Settings (or --folder) so files can be found by what they contain. Nothing leaves this Mac."
  )

  @OptionGroup var output: OutputOptions
  @OptionGroup var location: IndexLocation

  @Flag(name: .long, help: "Show what's in the index without updating it.")
  var status = false

  @Flag(name: .long, help: "Throw the index away and build it again.")
  var rebuild = false

  @Option(name: .long, help: "Index this folder instead of the configured ones (repeatable).")
  var folder: [String] = []

  func run() async throws {
    if status {
      let current = try location.open().status()
      emit(current, json: output.json) { printStatus(current) }
      return
    }
    if rebuild { IndexStore.delete(at: location.url) }
    let store = try location.open()
    var config = ConfigStore.load()
    if !folder.isEmpty {
      config.index.folders = folder.map { ($0 as NSString).expandingTildeInPath }.map {
        $0.hasPrefix("/") ? $0 : FileManager.default.currentDirectoryPath + "/" + $0
      }
    }
    let embedder = await AppleTextEmbedder.load()
    let indexer = Indexer(store: store, embedder: embedder)
    let cancel = CancelFlag()
    let quiet = output.json
    let report = await indexer.run(config: config, cancel: cancel) { progress in
      guard !quiet else { return }
      let name = (progress.path as NSString).lastPathComponent.prefix(50)
      FileHandle.standardError.write(Data("\r\u{1B}[K  indexing… \(progress.finished + 1)/\(progress.total) \(name)".utf8))
    }
    if !quiet { FileHandle.standardError.write(Data("\r\u{1B}[K".utf8)) }
    emit(report, json: output.json) {
      print("Indexed \(report.folders.map(Redactor.tilde).joined(separator: ", ")) in \(String(format: "%.1f", report.seconds))s\(report.cancelled ? " (cancelled)" : "")")
      print("  \(report.seen) files seen, \(report.indexed) indexed, \(report.skippedUnchanged) unchanged, \(report.failed) failed")
      print("  skipped: \(report.skippedProtected) protected, \(report.skippedTooLarge) too large, \(report.skippedUnsupported) unsupported, \(report.skippedCloud) in the cloud")
      if report.removed > 0 { print("  \(report.removed) old entries removed") }
      print(String(format: "  time reading %.1fs, images %.1fs, embedding %.1fs", report.extractSeconds, report.imageSeconds, report.embedSeconds))
      printStatus(store.status())
    }
  }

  private func printStatus(_ status: IndexStatus) {
    print("Index: \(status.files) files, \(status.chunks) passages, \(status.images) images, \(Format.bytes(status.databaseBytes)) at \(Redactor.tilde(status.location))")
    if let lastRun = status.lastRun { print("Last updated \(Format.age(lastRun)) with \(status.embedder ?? "unknown model")") }
  }
}

struct Search: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    abstract: "Find files by what they contain, using the on-device index."
  )

  @OptionGroup var output: OutputOptions
  @OptionGroup var location: IndexLocation

  @Argument(help: "What you're looking for, in your own words.")
  var query: String

  @Option(name: .long, help: "How many files to list.")
  var limit = 10

  @Option(name: .long, help: "Only this kind of file (repeatable): \(ContentKind.allCases.map(\.rawValue).joined(separator: ", ")).")
  var kind: [String] = []

  func run() async throws {
    let kinds = try IndexCommandSupport.kinds(kind)
    let store = try location.open()
    let search = ContentSearch(store: store, embedder: await AppleTextEmbedder.load())
    let hits = await search.search(query, limit: limit, kinds: kinds)
    emit(hits, json: output.json) { IndexCommandSupport.print(hits, empty: store.status().files == 0) }
  }
}

struct Similar: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    abstract: "List indexed files most like an indexed file: pictures by look, documents by meaning."
  )

  @OptionGroup var output: OutputOptions
  @OptionGroup var location: IndexLocation

  @Argument(help: "An indexed file.")
  var path: String

  @Option(name: .long, help: "How many files to list.")
  var limit = 10

  func run() async throws {
    let full = URL(fileURLWithPath: (path as NSString).expandingTildeInPath).standardizedFileURL.path
    let store = try location.open()
    let search = ContentSearch(store: store, embedder: await AppleTextEmbedder.load())
    guard search.describe(path: full) != nil else { throw ValidationError("\(Redactor.tilde(full)) isn’t in the index. Run `\(Brand.cli) index` first.") }
    let hits = search.similar(to: full, limit: limit)
    emit(hits, json: output.json) { IndexCommandSupport.print(hits, empty: false) }
  }
}

struct Lookalikes: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    abstract: "Groups of near-identical images or documents that aren't exact copies. Report only."
  )

  @OptionGroup var output: OutputOptions
  @OptionGroup var location: IndexLocation

  @Option(name: .long, help: "image or document.")
  var kind: String?

  func run() async throws {
    let filter: ContentKind?
    switch kind?.lowercased() {
    case nil: filter = nil
    case "image", "images": filter = .image
    case "document", "documents": filter = .document
    case let other?: throw ValidationError("Unknown kind “\(other)”. Use image or document.")
    }
    let store = try location.open()
    let groups = ContentSearch(store: store, embedder: await AppleTextEmbedder.load()).lookalikes(kind: filter)
    emit(groups, json: output.json) {
      if groups.isEmpty { print("No near-identical files found."); return }
      for group in groups {
        print("\(group.kind.title)s that look alike (\(group.members.count), \(Format.bytes(group.totalBytes)), spread \(String(format: "%.2f", group.spread))):")
        for member in group.members {
          print("  \(Format.bytes(member.size).leftPadded(10))  \(member.modified.formatted(.dateTime.year().month(.abbreviated).day()))  \(Redactor.tilde(member.path))")
        }
      }
    }
  }
}

enum IndexCommandSupport {
  static func kinds(_ names: [String]) throws -> Set<ContentKind> {
    var result = Set<ContentKind>()
    for name in names {
      guard let kind = ContentKind(rawValue: name.lowercased()) ?? ContentKind(rawValue: String(name.lowercased().dropLast())) else {
        throw ValidationError("Unknown kind “\(name)”. Use one of: \(ContentKind.allCases.map(\.rawValue).joined(separator: ", ")).")
      }
      result.insert(kind)
    }
    return result
  }

  static func print(_ hits: [SearchHit], empty: Bool) {
    if hits.isEmpty {
      Swift.print(empty ? "The index is empty. Run `\(Brand.cli) index` first." : "Nothing matched.")
      return
    }
    for hit in hits {
      Swift.print("  \(String(format: "%.2f", hit.score))  \(hit.kind.rawValue.padding(toLength: 12, withPad: " ", startingAt: 0)) \(Format.bytes(hit.size).leftPadded(9))  \(Redactor.tilde(hit.path))")
      let line = hit.snippet.replacingOccurrences(of: "\n", with: " ").prefix(140)
      if !line.isEmpty { Swift.print("        \(line)") }
    }
  }
}
