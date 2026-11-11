import ArgumentParser
import Foundation
import GladeKit

/// One tool offered to agents over the Model Context Protocol.
struct MCPTool: Sendable {
  var name: String
  var description: String
  /// A JSON Schema object for the arguments, as text.
  var schema: String
  /// Never changes anything on the Mac.
  var readOnly: Bool
  var run: @Sendable (JSONValue) async throws -> String
}

struct MCPFailure: Error, LocalizedError {
  var message: String
  var errorDescription: String? { message }
}

struct MCP: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "mcp",
    abstract: "Run as a Model Context Protocol server on standard input and output, for AI agents.",
    discussion: "Add it to an agent with, for example: claude mcp add glade -- glade mcp"
  )

  func run() async throws {
    Log.echoToStandardError(minimum: nil)
    await MCPServer(tools: MCPTools.all).serve()
  }
}

struct Guidance: ParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "guide",
    abstract: "Print the briefing for AI agents: what Glade does, its safety rules, and how to drive it."
  )

  func run() {
    print(Guide.text)
  }
}

/// A minimal MCP server: newline-delimited JSON-RPC 2.0 over stdio, tools only.
struct MCPServer {
  var tools: [MCPTool]

  func serve() async {
    Log.info(.mcp, "MCP server started with \(tools.count) tools")
    do {
      for try await line in FileHandle.standardInput.bytes.lines {
        guard let request = JSONValue.parse(line) else {
          send(.object(["jsonrpc": .string("2.0"), "id": .null, "error": error(-32700, "Parse error")]))
          continue
        }
        if let response = await handle(request) { send(response) }
      }
    } catch {
      Log.error(.mcp, "Reading requests failed: \(error)")
    }
    Log.info(.mcp, "MCP server stopped")
  }

  private func handle(_ request: JSONValue) async -> JSONValue? {
    let id = request["id"]
    let method = request["method"]?.string ?? ""
    // Notifications carry no id and get no reply.
    guard let id else { return nil }

    func reply(_ result: JSONValue) -> JSONValue {
      .object(["jsonrpc": .string("2.0"), "id": id, "result": result])
    }

    switch method {
    case "initialize":
      let version = request["params"]?["protocolVersion"]?.string ?? "2025-06-18"
      return reply(.object([
        "protocolVersion": .string(version),
        "capabilities": .object(["tools": .object([:])]),
        "serverInfo": .object(["name": .string(Brand.cli), "title": .string(Brand.name), "version": .string(Brand.version)]),
        "instructions": .string(Guide.text),
      ]))
    case "ping":
      return reply(.object([:]))
    case "tools/list":
      return reply(.object(["tools": .array(tools.map { tool in
        .object([
          "name": .string(tool.name),
          "description": .string(tool.description),
          "inputSchema": JSONValue.parse(tool.schema) ?? .object(["type": .string("object")]),
          "annotations": .object(["readOnlyHint": .bool(tool.readOnly), "destructiveHint": .bool(!tool.readOnly)]),
        ])
      })]))
    case "tools/call":
      let name = request["params"]?["name"]?.string ?? ""
      let arguments = request["params"]?["arguments"] ?? .object([:])
      guard let tool = tools.first(where: { $0.name == name }) else {
        return .object(["jsonrpc": .string("2.0"), "id": id, "error": error(-32602, "Unknown tool: \(name)")])
      }
      let started = Date()
      do {
        let text = try await tool.run(arguments)
        Log.info(.mcp, "Tool \(name) succeeded in \(String(format: "%.1f", Date().timeIntervalSince(started)))s")
        return reply(.object(["content": .array([.object(["type": .string("text"), "text": .string(text)])]), "isError": .bool(false)]))
      } catch {
        Log.warning(.mcp, "Tool \(name) failed: \(error.localizedDescription)")
        return reply(.object(["content": .array([.object(["type": .string("text"), "text": .string(error.localizedDescription)])]), "isError": .bool(true)]))
      }
    default:
      return .object(["jsonrpc": .string("2.0"), "id": id, "error": error(-32601, "Method not found: \(method)")])
    }
  }

  private func error(_ code: Double, _ message: String) -> JSONValue {
    .object(["code": .number(code), "message": .string(message)])
  }

  private func send(_ value: JSONValue) {
    FileHandle.standardOutput.write(Data((value.text + "\n").utf8))
  }
}

enum MCPTools {
  static var all: [MCPTool] { storage + system }

  private static let noArguments = #"{"type":"object","properties":{},"additionalProperties":false}"#

  /// A finding trimmed to what an agent needs to reason about it.
  struct FindingSummary: Encodable {
    var id: String
    var title: String
    var category: String
    var bytes: Int64
    var size: String
    var lastUsed: String
    var comesBack: String
    var risk: String
    var blocked: String?
    var detail: String
    var location: String
    var selectableFrom: String?

    init(_ finding: Finding) {
      id = finding.id
      title = finding.title
      category = finding.category.rawValue
      bytes = finding.bytes
      size = Format.bytes(finding.bytes)
      lastUsed = Format.age(finding.lastUsed)
      comesBack = finding.recovery.rawValue
      risk = finding.risk.rawValue
      blocked = finding.blockers.first?.detail
      detail = finding.detail
      location = finding.paths.count == 1 ? Redactor.tilde(finding.paths[0]) : "\(finding.paths.count) locations"
      selectableFrom = finding.autoLevel?.rawValue
    }
  }

  static let storage: [MCPTool] = [
    MCPTool(
      name: "glade_scan",
      description: "Scan this Mac for reclaimable storage. Read-only; takes 30–60 seconds. Returns totals by category and the largest findings. Protected areas (credentials, Photos, Mail, Messages, cloud folders, agent memory) are never included.",
      schema: #"{"type":"object","properties":{"limit":{"type":"integer","description":"How many of the largest findings to return (default 40)."},"category":{"type":"string","description":"Only this category, e.g. xcode, simulators, packageCaches, agentHistory, downloads."}},"additionalProperties":false}"#,
      readOnly: true
    ) { arguments in
      let result = await ScanEngine.run()
      ScanEngine.save(result)
      return summarise(result, limit: arguments["limit"]?.int ?? 40, category: arguments["category"]?.string)
    },
    MCPTool(
      name: "glade_findings",
      description: "List findings from the most recent scan without scanning again. Use after glade_scan to page through or filter.",
      schema: #"{"type":"object","properties":{"limit":{"type":"integer"},"category":{"type":"string"},"includeBlocked":{"type":"boolean","description":"Include findings that can't be removed right now."}},"additionalProperties":false}"#,
      readOnly: true
    ) { arguments in
      guard let result = ScanEngine.loadLast() else { throw MCPFailure(message: "No scan yet. Call glade_scan first.") }
      return summarise(result, limit: arguments["limit"]?.int ?? 60, category: arguments["category"]?.string, includeBlocked: arguments["includeBlocked"]?.bool ?? false)
    },
    MCPTool(
      name: "glade_plan",
      description: "Show what a clean at a given level would remove, without removing anything. Levels: careful (only things that rebuild themselves and are idle), balanced (adds package caches, stale agent sessions, idle simulators and models), aggressive (everything that can come back).",
      schema: #"{"type":"object","properties":{"level":{"type":"string","enum":["careful","balanced","aggressive"]}},"required":["level"],"additionalProperties":false}"#,
      readOnly: true
    ) { arguments in
      guard let level = arguments["level"]?.string.flatMap(CleanLevel.init(rawValue:)) else {
        throw MCPFailure(message: "level must be careful, balanced or aggressive.")
      }
      let scan = try await Scans.recent(rescan: false, quiet: true)
      let plan = Planner.plan(scan: scan, level: level)
      struct Report: Encodable {
        var level: String
        var total: String
        var totalBytes: Int64
        var freedImmediately: String
        var movedToTrash: String
        var selected: [FindingSummary]
      }
      return JSONFiles.string(Report(
        level: level.rawValue, total: Format.bytes(plan.selectedBytes), totalBytes: plan.selectedBytes,
        freedImmediately: Format.bytes(plan.immediateBytes), movedToTrash: Format.bytes(plan.selectedBytes - plan.immediateBytes),
        selected: plan.selectedIDs.compactMap { scan.finding($0) }.map(FindingSummary.init)
      ))
    },
    MCPTool(
      name: "glade_clean",
      description: "Remove findings by level or by id. A dry run unless confirm is true: always do a dry run first and tell the person what will happen. Rebuildable things are deleted; everything else goes to the Trash and can be put back with glade_undo. Only ids from a scan are accepted, never paths.",
      schema: #"{"type":"object","properties":{"level":{"type":"string","enum":["careful","balanced","aggressive"]},"ids":{"type":"array","items":{"type":"string"},"description":"Finding ids from glade_scan or glade_plan."},"confirm":{"type":"boolean","description":"Set true to actually remove. Defaults to a dry run."}},"additionalProperties":false}"#,
      readOnly: false
    ) { arguments in
      let scan = try await Scans.recent(rescan: false, quiet: true)
      var ids = arguments["ids"]?.strings ?? []
      if let level = arguments["level"]?.string.flatMap(CleanLevel.init(rawValue:)) {
        ids += Planner.plan(scan: scan, level: level).selectedIDs
      }
      guard !ids.isEmpty else { throw MCPFailure(message: "Give a level or a list of ids.") }
      let receipt = try await Cleaner.clean(
        ids: ids, from: scan,
        options: CleanOptions(dryRun: arguments["confirm"]?.bool != true, initiator: .assistant(provider: "MCP client"))
      )
      if !receipt.dryRun { ScanEngine.save(scan.removing(receipt)) }
      return JSONFiles.string(receipt)
    },
    MCPTool(
      name: "glade_undo",
      description: "Put back everything the most recent clean moved to the Trash. Things that were deleted outright (caches, build data) rebuild by themselves and can't be put back.",
      schema: noArguments, readOnly: false
    ) { _ in
      guard let receipt = Cleaner.receipts().first else { throw MCPFailure(message: "Nothing has been cleaned yet.") }
      return JSONFiles.string(Cleaner.restore(receipt))
    },
    MCPTool(
      name: "glade_protect_check",
      description: "Ask whether Glade could ever remove a path, and why not. Use it to explain the safety rules; it reads nothing.",
      schema: #"{"type":"object","properties":{"path":{"type":"string"}},"required":["path"],"additionalProperties":false}"#,
      readOnly: true
    ) { arguments in
      guard let path = arguments["path"]?.string else { throw MCPFailure(message: "path is required.") }
      let protection = Protection(config: ConfigStore.load())
      let full = URL(fileURLWithPath: (path as NSString).expandingTildeInPath).standardizedFileURL.path
      let verdict = protection.verdict(forRemoving: full)
      return JSONValue.object([
        "removable": .bool(verdict.isAllowed), "explanation": .string(verdict.explanation),
        "visibleToScans": .bool(protection.canScan(full)),
      ]).text
    },
    MCPTool(
      name: "glade_guide",
      description: "The full briefing on what Glade does, its safety rules and how to use it well.",
      schema: noArguments, readOnly: true
    ) { _ in Guide.text },
  ]

  static func summarise(_ result: ScanResult, limit: Int, category: String?, includeBlocked: Bool = false) -> String {
    struct CategoryTotal: Encodable {
      var category: String
      var title: String
      var bytes: Int64
      var size: String
      var count: Int
    }
    struct Report: Encodable {
      var freeSpace: String
      var diskSize: String
      var reclaimable: String
      var scanned: Date
      var fullDiskAccess: Bool
      var categories: [CategoryTotal]
      var findings: [FindingSummary]
      var notShown: Int
    }
    var totals: [StorageCategory: (Int64, Int)] = [:]
    for finding in result.findings {
      totals[finding.category, default: (0, 0)].0 += finding.bytes
      totals[finding.category, default: (0, 0)].1 += 1
    }
    var shown = result.findings
    if let category { shown = shown.filter { $0.category.rawValue == category } }
    if !includeBlocked { shown = shown.filter { !$0.isBlocked } }
    return JSONFiles.string(Report(
      freeSpace: Format.bytes(result.volume.availableBytes), diskSize: Format.bytes(result.volume.totalBytes),
      reclaimable: Format.bytes(result.totalBytes), scanned: result.finished, fullDiskAccess: result.hasFullDiskAccess,
      categories: totals.sorted { $0.value.0 > $1.value.0 }.map {
        CategoryTotal(category: $0.key.rawValue, title: $0.key.title, bytes: $0.value.0, size: Format.bytes($0.value.0), count: $0.value.1)
      },
      findings: shown.prefix(limit).map(FindingSummary.init), notShown: max(0, shown.count - limit)
    ))
  }
}
