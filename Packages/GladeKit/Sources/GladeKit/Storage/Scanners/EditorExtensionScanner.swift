import Foundation

/// Finds old versions of editor extensions that VS Code and its relatives left behind
/// after updating. Only versions that are neither the newest nor listed in the editor’s
/// own `extensions.json` (what it actually loads) are reported.
public struct EditorExtensionScanner: StorageScanner {
  public let id = "editor-extensions"
  public let title = "Old editor extension versions"

  public init() {}

  struct Editor: Sendable {
    var name: String
    var folder: String
    var owner: Owner
  }

  static let editors: [Editor] = [
    Editor(name: "Visual Studio Code", folder: "~/.vscode/extensions",
           owner: Owner("Visual Studio Code", bundleIDs: ["com.microsoft.VSCode"], processNames: ["Code"])),
    Editor(name: "VS Code Insiders", folder: "~/.vscode-insiders/extensions",
           owner: Owner("VS Code Insiders", bundleIDs: ["com.microsoft.VSCodeInsiders"])),
    Editor(name: "Cursor", folder: "~/.cursor/extensions",
           owner: Owner("Cursor", bundleIDs: ["com.todesktop.230313mzl4w4u92"], processNames: ["Cursor"])),
    Editor(name: "Windsurf", folder: "~/.windsurf/extensions",
           owner: Owner("Windsurf", bundleIDs: ["com.exafunction.windsurf"], processNames: ["Windsurf"])),
    Editor(name: "VSCodium", folder: "~/.vscode-oss/extensions",
           owner: Owner("VSCodium", bundleIDs: ["com.vscodium"], processNames: ["VSCodium"])),
  ]

  /// Platform suffixes the marketplace appends to folder names.
  static let platforms: Set<String> = [
    "universal", "web", "darwin-arm64", "darwin-x64", "linux-x64", "linux-arm64", "linux-armhf",
    "alpine-x64", "alpine-arm64", "win32-x64", "win32-arm64", "win32-ia32",
  ]

  struct Installed: Sendable {
    var folder: String
    var id: String
    var version: [Int]
  }

  public func scan(_ context: ScanContext) async -> [Finding] {
    guard !context.config.ignoredCategories.contains(.editorExtensions) else { return [] }
    var findings: [Finding] = []
    for editor in Self.editors {
      if context.cancel.isCancelled { break }
      let folder = Protection.clean(Protection.expand(editor.folder, home: context.home))
      guard FileFacts.isDirectory(folder), context.protection.canScan(folder) else { continue }
      guard let found = await context.background({ Self.obsolete(in: folder) }), let example = found.folders.first else { continue }
      let paths = found.folders.map { folder + "/" + $0 }.filter { context.protection.canScan($0) }
      guard !paths.isEmpty else { continue }
      let measure = await context.measure(paths)
      guard measure.bytes > 0, !measure.cancelled else { continue }

      var evidence = [
        paths.count == 1
          ? "1 superseded version, \(example)."
          : "\(paths.count) superseded versions, for example \(example).",
        "Each has a newer version installed, and \(editor.name)’s extensions.json doesn’t load it.",
      ]
      if found.marked > 0 {
        evidence.append("\(found.marked == paths.count ? "All" : "\(found.marked)") of them \(editor.name) itself marked obsolete.")
      }
      if measure.unreadable > 0 {
        evidence.append("\(measure.unreadable) items couldn’t be read, so the real size may be larger.")
      }
      var blockers: [Blocker] = []
      for path in paths {
        let verdict = context.protection.verdict(forRemoving: path)
        if !verdict.isAllowed {
          blockers.append(Blocker(.inUse, verdict.explanation))
          break
        }
      }
      findings.append(Finding(
        id: Finding.makeID(rule: "editor.extensions.obsolete", path: folder),
        ruleID: "editor.extensions.obsolete", category: .editorExtensions,
        title: "Old extension versions – \(editor.name)",
        detail: "Earlier versions of extensions that \(editor.name) replaced with newer ones and no longer loads; nothing needs them.",
        paths: paths, bytes: measure.bytes, fileCount: measure.files, lastUsed: measure.lastUsed,
        recovery: .automatic, risk: .safe, owner: editor.owner, blockers: blockers, method: .delete,
        evidence: evidence, autoLevel: blockers.isEmpty ? .careful : nil, idleDaysRequired: 0
      ))
    }
    return findings
  }

  /// Folder names of superseded versions, or `nil` when the editor’s list of loaded
  /// extensions can’t be read (then nothing is reported for that editor).
  static func obsolete(in folder: String) -> (folders: [String], marked: Int)? {
    guard let referenced = referencedFolders(folder) else {
      Log.info(.scan, "Couldn’t read \(folder)/extensions.json; leaving its extensions alone")
      return nil
    }
    let listedObsolete = obsoleteList(folder)
    let names = ((try? FileManager.default.contentsOfDirectory(atPath: folder)) ?? []).filter { name in
      !name.hasPrefix(".") && FileFacts.isDirectory(folder + "/" + name)
    }
    var byID: [String: [Installed]] = [:]
    for name in names {
      guard let parsed = parse(name) else { continue }
      byID[parsed.id.lowercased(), default: []].append(Installed(folder: name, id: parsed.id, version: parsed.version))
    }
    var result: [String] = []
    var marked = 0
    for (_, versions) in byID {
      guard let newest = versions.map(\.version).max(by: { compare($0, $1) < 0 }) else { continue }
      // The newest version and anything the editor loads are never included, even
      // when `.obsolete` names them (an uninstalled extension’s only folder, say).
      for installed in versions {
        if compare(installed.version, newest) == 0 { continue }
        if referenced.contains(installed.folder.lowercased()) { continue }
        result.append(installed.folder)
        if listedObsolete.contains(installed.folder.lowercased()) { marked += 1 }
      }
    }
    return (result.sorted(), marked)
  }

  /// Folder names the editor loads, from `extensions.json`.
  static func referencedFolders(_ folder: String) -> Set<String>? {
    guard let data = FileManager.default.contents(atPath: folder + "/extensions.json"),
          let list = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return nil }
    var names = Set<String>()
    for item in list {
      if let relative = item["relativeLocation"] as? String {
        names.insert(relative.lowercased())
      } else if let location = item["location"] as? [String: Any], let path = location["path"] as? String {
        names.insert((path as NSString).lastPathComponent.lowercased())
      }
    }
    return names
  }

  /// Folder names the editor marked for deletion in `.obsolete`.
  static func obsoleteList(_ folder: String) -> Set<String> {
    guard let data = FileManager.default.contents(atPath: folder + "/.obsolete"),
          let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [] }
    return Set(object.compactMap { key, value in (value as? Bool) == true ? key.lowercased() : nil })
  }

  /// `publisher.name-1.2.3[-platform]` → ("publisher.name", [1, 2, 3]).
  static func parse(_ name: String) -> (id: String, version: [Int])? {
    var base = name
    for platform in platforms where name.hasSuffix("-" + platform) {
      base = String(name.dropLast(platform.count + 1))
      break
    }
    guard let dash = base.lastIndex(of: "-") else { return nil }
    let id = String(base[..<dash])
    let versionText = base[base.index(after: dash)...]
    let parts = versionText.split(separator: ".", omittingEmptySubsequences: false)
    guard id.contains("."), parts.count >= 2, parts.allSatisfy({ !$0.isEmpty && $0.allSatisfy(\.isNumber) }) else { return nil }
    let numbers = parts.compactMap { Int($0) }
    guard numbers.count == parts.count else { return nil }
    return (id, numbers)
  }

  /// Compares dotted versions component by component, as numbers.
  static func compare(_ lhs: [Int], _ rhs: [Int]) -> Int {
    for index in 0..<max(lhs.count, rhs.count) {
      let a = index < lhs.count ? lhs[index] : 0
      let b = index < rhs.count ? rhs[index] : 0
      if a != b { return a < b ? -1 : 1 }
    }
    return 0
  }
}
