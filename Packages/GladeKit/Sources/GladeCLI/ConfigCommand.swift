import ArgumentParser
import Foundation
import GladeKit

struct Config: ParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "config",
    abstract: "Show or change Glade's settings.",
    discussion: """
      Settings are addressed by dotted path, for example:
        \(Brand.cli) config set level careful
        \(Brand.cli) config set assistant.order '["claude","codex","apple"]'
        \(Brand.cli) config set assistant.models.claude haiku
        \(Brand.cli) config set assistant.runsPerDay null
      """,
    subcommands: [Show.self, Set.self],
    defaultSubcommand: Show.self
  )

  struct Show: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Print the settings as JSON.")

    func run() {
      print(JSONFiles.string(ConfigStore.load()))
    }
  }

  struct Set: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Change one setting.")

    @Argument(help: "Dotted path, such as automation.storageFreeGB.")
    var key: String

    @Argument(help: "The new value: JSON, or plain text for a string.")
    var value: String

    func run() throws {
      guard var root = JSONValue.parse(JSONFiles.string(ConfigStore.load())) else {
        throw ValidationError("The settings couldn’t be read.")
      }
      let parsed = JSONValue.parse(value) ?? .string(value)
      let path = key.split(separator: ".").map(String.init)
      guard !path.isEmpty, Self.assign(&root, path[...], parsed) else {
        throw ValidationError("There’s no setting at “\(key)”.")
      }
      // Decoding back into the settings type rejects values of the wrong shape.
      guard let data = root.text.data(using: .utf8),
            let updated = try? JSONDecoder().decode(GladeConfig.self, from: data),
            JSONValue.parse(JSONFiles.string(updated)).flatMap({ Self.value(in: $0, path[...]) }) == parsed
              || parsed == .null
      else {
        throw ValidationError("“\(value)” isn’t a valid value for \(key).")
      }
      ConfigStore.save(updated)
      print("\(key) = \(parsed.text)")
    }

    /// Sets a value at a path. Only dictionaries keyed by name (per-provider models)
    /// accept a new key; everywhere else the key must already exist.
    private static func assign(_ node: inout JSONValue, _ path: ArraySlice<String>, _ value: JSONValue) -> Bool {
      guard case .object(var object) = node, let first = path.first else { return false }
      let openEnded = ["models", "deepModels"]
      if path.count == 1 {
        guard object[first] != nil || value == .null || true else { return false }
        if value == .null { object.removeValue(forKey: first) } else { object[first] = value }
        node = .object(object)
        return true
      }
      var child = object[first] ?? (openEnded.contains(first) ? .object([:]) : .null)
      guard assign(&child, path.dropFirst(), value) else { return false }
      object[first] = child
      node = .object(object)
      return true
    }

    private static func value(in node: JSONValue, _ path: ArraySlice<String>) -> JSONValue? {
      guard let first = path.first else { return node }
      return node[first].flatMap { value(in: $0, path.dropFirst()) }
    }
  }
}
