import AppKit
import Foundation
import ImageIO
import PDFKit
import UniformTypeIdentifiers
import Vision

/// What reading one file produced.
public struct Extraction: Sendable {
  public var kind: ContentKind
  public var title: String
  /// Plain text, capped at `TextExtractor.maxCharacters`.
  public var text: String
  /// Words describing an image ("dog", "document", "screenshot").
  public var labels: [String]
  /// A fingerprint of the file's bytes, to tell exact copies from lookalikes.
  public var bytesHash: String?
  /// The image's feature print, when the file is an image.
  public var imageVector: [Float]?
}

/// Why a file couldn't be read. Never carries any of the file's contents.
public enum ExtractionError: Error, CustomStringConvertible, Sendable {
  case unreadable(String)
  case undecodable(String)
  case timedOut
  case cancelled

  public var description: String {
    switch self {
    case .unreadable(let reason): reason
    case .undecodable(let format): "couldn’t be read as \(format)"
    case .timedOut: "took too long to read"
    case .cancelled: "cancelled"
    }
  }
}

/// Turns a file into plain text and a kind, entirely on this Mac. Files are read into
/// memory through `SafeRead` and parsed from there, so nothing here opens a file in a
/// way that changes it, downloads it, or marks it as recently opened.
public struct TextExtractor: Sendable {
  /// Files bigger than this aren't read.
  public static let maxFileBytes: Int64 = 50_000_000
  public static let maxCharacters = 200_000
  public static let maxPDFPages = 200
  /// How many pages of a scan (a PDF with no text layer) are read with text recognition.
  public static let scannedPages = 3
  /// Images are shrunk to at most this many pixels on a side before Vision sees them.
  static let imagePixels = 2560

  public var readTextInImages: Bool
  public var images: ImageEmbedder

  public init(readTextInImages: Bool = true, images: ImageEmbedder = ImageEmbedder()) {
    self.readTextInImages = readTextInImages
    self.images = images
  }

  // MARK: Kinds

  /// Packages (folders that look like one file) whose contents can be read.
  static let readablePackages: Set<String> = ["pages", "key", "numbers", "rtfd"]
  private static let richText: [String: NSAttributedString.DocumentType] = [
    "docx": .officeOpenXML, "doc": .docFormat, "rtf": .rtf, "odt": .openDocument, "wordml": .wordML,
  ]
  private static let codeExtensions: Set<String> = [
    "json", "jsonc", "xml", "yaml", "yml", "toml", "ini", "cfg", "conf", "sql", "sh", "zsh", "bash", "fish",
    "graphql", "proto", "gradle", "cmake", "dockerfile", "tf", "svelte", "vue",
  ]
  /// Images Vision can't decode, or that are icons rather than pictures.
  private static let skippedImages: Set<String> = ["svg", "svgz", "ico", "icns", "pdf"]

  /// The kind of a file judged from its name, or `nil` when its contents can't be read.
  public static func kind(for path: String, isDirectory: Bool = false) -> ContentKind? {
    let ext = (path as NSString).pathExtension.lowercased()
    if isDirectory {
      switch ext {
      case "pages", "rtfd": return .document
      case "key": return .presentation
      case "numbers": return .spreadsheet
      default: return nil
      }
    }
    switch ext {
    case "": return nil
    case "pdf": return .pdf
    case "docx", "doc", "rtf", "odt", "wordml", "pages", "html", "htm", "xhtml": return .document
    case "xlsx", "numbers", "csv", "tsv": return .spreadsheet
    case "pptx", "key": return .presentation
    default: break
    }
    if codeExtensions.contains(ext) { return .code }
    guard let type = UTType(filenameExtension: ext) else { return nil }
    if type.conforms(to: .image) { return skippedImages.contains(ext) ? nil : .image }
    if type.conforms(to: .sourceCode) || type.conforms(to: .script) { return .code }
    if type.conforms(to: .plainText) { return .text }
    return nil
  }

  // MARK: Reading

  /// Reads one file. `deadline` is checked between pages so one huge PDF can't hang a run.
  public func extract(_ path: String, kind: ContentKind, isPackage: Bool, deadline: Date) async throws -> Extraction {
    let name = (path as NSString).lastPathComponent
    let ext = (name as NSString).pathExtension.lowercased()
    var result = Extraction(kind: kind, title: TextExtractor.title(fromName: name), text: "", labels: [], bytesHash: nil, imageVector: nil)

    if isPackage {
      try await readPackage(path, ext: ext, into: &result, deadline: deadline)
      return result
    }

    let data: Data
    do {
      data = try SafeRead.data(path, limit: TextExtractor.maxFileBytes)
    } catch let failure as SafeRead.Failure {
      throw ExtractionError.unreadable(failure.description)
    }
    result.bytesHash = SafeRead.fingerprint(data)

    switch kind {
    case .pdf:
      try await readPDF(data, into: &result, deadline: deadline)
    case .image:
      try await readImage(data, into: &result)
    case .text, .code:
      result.text = try TextExtractor.decodeText(data)
    case .document, .spreadsheet, .presentation:
      try await readOffice(data, ext: ext, into: &result, deadline: deadline)
    case .other:
      break
    }
    return result
  }

  private func readOffice(_ data: Data, ext: String, into result: inout Extraction, deadline: Date) async throws {
    if let type = TextExtractor.richText[ext] {
      var attributes: NSDictionary?
      // Never the HTML importer: it needs WebKit on the main thread.
      guard let string = try? NSAttributedString(
        data: data, options: [.documentType: type], documentAttributes: &attributes
      ) else { throw ExtractionError.undecodable(ext.uppercased()) }
      result.text = TextExtractor.capped(string.string)
      if let title = attributes?[NSAttributedString.DocumentAttributeKey.title] as? String,
         !title.trimmingCharacters(in: .whitespaces).isEmpty {
        result.title = title
      }
      return
    }
    switch ext {
    case "html", "htm", "xhtml":
      let page = TextExtractor.stripHTML(try TextExtractor.decodeText(data))
      result.text = page.text
      if let title = page.title, !title.isEmpty { result.title = title }
    case "csv", "tsv":
      result.text = try TextExtractor.decodeText(data)
    case "pptx", "xlsx":
      guard let zip = ZipArchive(data) else { throw ExtractionError.undecodable(ext.uppercased()) }
      result.text = TextExtractor.officeXMLText(zip, presentation: ext == "pptx")
    case "pages", "key", "numbers":
      // iWork files saved as one file are zips. Some carry a PDF preview; without one
      // only the name is searchable.
      if let zip = ZipArchive(data), let preview = zip.read("QuickLook/Preview.pdf") {
        try await readPDF(preview, into: &result, deadline: deadline, keepTitle: true)
      }
    default:
      break
    }
  }

  private func readPackage(_ path: String, ext: String, into result: inout Extraction, deadline: Date) async throws {
    switch ext {
    case "rtfd":
      let data: Data
      do { data = try SafeRead.data(path + "/TXT.rtf", limit: TextExtractor.maxFileBytes) } catch { return }
      result.bytesHash = SafeRead.fingerprint(data)
      if let string = try? NSAttributedString(data: data, options: [.documentType: NSAttributedString.DocumentType.rtf], documentAttributes: nil) {
        result.text = TextExtractor.capped(string.string)
      }
    default:
      let data: Data
      do { data = try SafeRead.data(path + "/QuickLook/Preview.pdf", limit: TextExtractor.maxFileBytes) } catch { return }
      result.bytesHash = SafeRead.fingerprint(data)
      try await readPDF(data, into: &result, deadline: deadline, keepTitle: true)
    }
  }

  private func readPDF(_ data: Data, into result: inout Extraction, deadline: Date, keepTitle: Bool = false) async throws {
    guard let document = PDFDocument(data: data) else { throw ExtractionError.undecodable("PDF") }
    if document.isLocked { throw ExtractionError.unreadable("password protected") }
    if !keepTitle, let title = document.documentAttributes?[PDFDocumentAttribute.titleAttribute] as? String,
       TextExtractor.isUsefulTitle(title) {
      result.title = title
    }
    let pages = min(document.pageCount, TextExtractor.maxPDFPages)
    var text = ""
    for index in 0..<pages {
      if Date() > deadline { throw ExtractionError.timedOut }
      if let page = document.page(at: index), let string = page.string {
        text += string
        text += "\n\n"
      }
      if text.count >= TextExtractor.maxCharacters { break }
    }
    if text.trimmingCharacters(in: .whitespacesAndNewlines).count < 20 * max(1, min(pages, 3)), readTextInImages {
      // A scan: no text layer, so read the first few pages as pictures.
      var recognized: [String] = []
      for index in 0..<min(pages, TextExtractor.scannedPages) {
        if Date() > deadline { throw ExtractionError.timedOut }
        guard let page = document.page(at: index), let image = TextExtractor.render(page) else { continue }
        recognized.append(contentsOf: try await recognizeText(image))
      }
      if !recognized.isEmpty { text = recognized.joined(separator: "\n") }
    }
    result.text = TextExtractor.capped(text)
  }

  private func readImage(_ data: Data, into result: inout Extraction) async throws {
    guard let image = TextExtractor.decodeImage(data, maxPixels: TextExtractor.imagePixels) else {
      throw ExtractionError.undecodable("an image")
    }
    result.imageVector = try? await images.featurePrint(image)
    guard readTextInImages else { return }
    result.text = TextExtractor.capped(try await recognizeText(image).joined(separator: "\n"))
    var classify = ClassifyImageRequest()
    classify.cropAndScaleAction = .scaleToFit
    if let observations = try? await classify.perform(on: image) {
      result.labels = observations
        .filter { $0.confidence >= 0.3 }
        .sorted { $0.confidence > $1.confidence }
        .prefix(8)
        .map { $0.identifier.replacingOccurrences(of: "_", with: " ") }
    }
  }

  /// Loads Vision's models with a tiny blank image. The first request of a run can take
  /// tens of seconds while models load, which mustn't count against a file's time limit.
  public func warmUp() async {
    guard let space = CGColorSpace(name: CGColorSpace.sRGB),
          let context = CGContext(data: nil, width: 64, height: 64, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return }
    context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: 64, height: 64))
    guard let image = context.makeImage() else { return }
    let started = Date()
    _ = try? await images.featurePrint(image)
    if readTextInImages {
      _ = try? await recognizeText(image)
      _ = try? await ClassifyImageRequest().perform(on: image)
    }
    Log.debug(.index, String(format: "Vision models ready in %.1fs", Date().timeIntervalSince(started)))
  }

  private func recognizeText(_ image: CGImage) async throws -> [String] {
    var request = RecognizeTextRequest()
    request.recognitionLevel = .accurate
    let observations = try await request.perform(on: image)
    return observations.compactMap { $0.topCandidates(1).first?.string }
  }

  // MARK: Helpers

  /// "Chicago_lease-2024 final" from "Chicago_lease-2024 final.pdf", with separators as spaces.
  static func title(fromName name: String) -> String {
    let stem = (name as NSString).deletingPathExtension
    return stem.replacingOccurrences(of: "_", with: " ").trimmingCharacters(in: .whitespaces)
  }

  /// PDF producers often leave titles like "Microsoft Word - Document1" or "untitled".
  static func isUsefulTitle(_ title: String) -> Bool {
    let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
    guard trimmed.count >= 3 else { return false }
    let lower = trimmed.lowercased()
    return !["untitled", "microsoft word", "document1", "slide 1"].contains { lower.hasPrefix($0) }
      && !lower.hasSuffix(".doc") && !lower.hasSuffix(".docx")
  }

  static func capped(_ text: String) -> String {
    text.count > maxCharacters ? String(text.prefix(maxCharacters)) : text
  }

  /// UTF-8, falling back to Latin-1. Files with NUL bytes near the start are binary.
  static func decodeText(_ data: Data) throws -> String {
    if data.prefix(4096).contains(0) { throw ExtractionError.undecodable("text") }
    let head = data.prefix(maxCharacters * 4)
    let string = String(data: head, encoding: .utf8) ?? String(data: head, encoding: .isoLatin1) ?? ""
    return capped(string)
  }

  static func decodeImage(_ data: Data, maxPixels: Int) -> CGImage? {
    guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
    let options: [CFString: Any] = [
      kCGImageSourceCreateThumbnailFromImageAlways: true,
      kCGImageSourceCreateThumbnailWithTransform: true,
      kCGImageSourceShouldCacheImmediately: true,
      kCGImageSourceThumbnailMaxPixelSize: maxPixels,
    ]
    return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
  }

  /// A PDF page drawn on white, about 2000 pixels on its long side.
  static func render(_ page: PDFPage) -> CGImage? {
    let bounds = page.bounds(for: .mediaBox)
    guard bounds.width > 0, bounds.height > 0 else { return nil }
    let scale = min(4, 2000 / max(bounds.width, bounds.height))
    let width = Int(bounds.width * scale)
    let height = Int(bounds.height * scale)
    guard let space = CGColorSpace(name: CGColorSpace.sRGB),
          let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
    context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    context.scaleBy(x: scale, y: scale)
    context.translateBy(x: -bounds.minX, y: -bounds.minY)
    page.draw(with: .mediaBox, to: context)
    return context.makeImage()
  }

  /// Slide text from a .pptx, or cell text from an .xlsx, read from its XML parts.
  static func officeXMLText(_ zip: ZipArchive, presentation: Bool) -> String {
    let parts: [String]
    let pattern: String
    if presentation {
      parts = zip.names()
        .filter { $0.hasPrefix("ppt/slides/slide") && $0.hasSuffix(".xml") }
        .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
      pattern = #"<a:t>([^<]*)</a:t>"#
    } else {
      parts = ["xl/sharedStrings.xml"]
      pattern = #"<t[^>]*>([^<]*)</t>"#
    }
    guard let expression = try? NSRegularExpression(pattern: pattern) else { return "" }
    var text = ""
    for part in parts {
      guard let data = zip.read(part) else { continue }
      let xml = String(decoding: data, as: UTF8.self)
      let range = NSRange(xml.startIndex..., in: xml)
      var line: [String] = []
      for match in expression.matches(in: xml, range: range) {
        if let r = Range(match.range(at: 1), in: xml) { line.append(String(xml[r])) }
      }
      text += decodeEntities(line.joined(separator: presentation ? " " : "\n")) + "\n\n"
      if text.count >= maxCharacters { break }
    }
    return capped(text)
  }

  private static let blockTags: Set<String> = [
    "p", "div", "br", "li", "ul", "ol", "tr", "td", "th", "h1", "h2", "h3", "h4", "h5", "h6",
    "section", "article", "header", "footer", "blockquote", "pre", "table", "hr",
  ]

  /// The visible text of an HTML page and its title, with a small scanner rather than
  /// WebKit.
  static func stripHTML(_ html: String) -> (title: String?, text: String) {
    var output = ""
    var title: String?
    var index = html.startIndex
    while index < html.endIndex {
      let character = html[index]
      guard character == "<" else {
        output.append(character)
        index = html.index(after: index)
        continue
      }
      if html[index...].hasPrefix("<!--") {
        index = html.range(of: "-->", range: index..<html.endIndex)?.upperBound ?? html.endIndex
        continue
      }
      guard let close = html[index...].firstIndex(of: ">") else { break }
      let tag = html[html.index(after: index)..<close].lowercased()
      let name = String(tag.prefix { $0.isLetter || $0.isNumber || $0 == "/" })
      if name == "script" || name == "style" || name == "title" {
        if let end = html.range(of: "</\(name)", options: .caseInsensitive, range: close..<html.endIndex) {
          if name == "title" { title = decodeEntities(String(html[html.index(after: close)..<end.lowerBound])).trimmingCharacters(in: .whitespacesAndNewlines) }
          index = html[end.upperBound...].firstIndex(of: ">").map { html.index(after: $0) } ?? html.endIndex
          continue
        }
      }
      output.append(blockTags.contains(name.trimmingCharacters(in: CharacterSet(charactersIn: "/"))) ? "\n" : " ")
      index = html.index(after: close)
    }
    return (title, capped(decodeEntities(output)))
  }

  private static let entities: [String: String] = [
    "amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'", "nbsp": " ", "mdash": "—", "ndash": "–",
    "hellip": "…", "rsquo": "’", "lsquo": "‘", "rdquo": "”", "ldquo": "“", "copy": "©",
  ]

  static func decodeEntities(_ text: String) -> String {
    guard text.contains("&") else { return text }
    var output = ""
    var index = text.startIndex
    while index < text.endIndex {
      let character = text[index]
      if character == "&", let semicolon = text[index...].prefix(10).firstIndex(of: ";") {
        let name = String(text[text.index(after: index)..<semicolon])
        var replacement: String?
        if name.hasPrefix("#x") || name.hasPrefix("#X") {
          replacement = UInt32(name.dropFirst(2), radix: 16).flatMap(Unicode.Scalar.init).map { String(Character($0)) }
        } else if name.hasPrefix("#") {
          replacement = UInt32(name.dropFirst()).flatMap(Unicode.Scalar.init).map { String(Character($0)) }
        } else {
          replacement = entities[name]
        }
        if let replacement {
          output += replacement
          index = text.index(after: semicolon)
          continue
        }
      }
      output.append(character)
      index = text.index(after: index)
    }
    return output
  }
}
