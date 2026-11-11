import Foundation
import GladeKit

/// The memory, processor and graphics tools offered to agents.
extension MCPTools {
  private static let none = #"{"type":"object","properties":{},"additionalProperties":false}"#

  static let system: [MCPTool] = [
    MCPTool(
      name: "glade_status",
      description: "This Mac right now: processor load, memory used and memory pressure, graphics load, free disk space, thermal state and power. Cheap; call it freely.",
      schema: none, readOnly: true
    ) { _ in
      JSONFiles.string(await SystemSampler().snapshot())
    },
    MCPTool(
      name: "glade_apps",
      description: "What is using memory, processor and graphics, grouped by app, with what Activity Monitor doesn’t show: which app is in front, when each was last used, which are playing audio or keeping the Mac awake. Processor is a share of one core, so it can exceed 100.",
      schema: #"{"type":"object","properties":{"limit":{"type":"integer","description":"How many apps, largest memory first (default 25)."},"includeSystem":{"type":"boolean","description":"Include macOS’s own processes."}},"additionalProperties":false}"#,
      readOnly: true
    ) { arguments in
      let apps = await SystemSampler().apps(full: arguments["includeSystem"]?.bool ?? false)
      let shown = apps.filter { arguments["includeSystem"]?.bool == true || !$0.isSystem }
        .sorted { $0.memoryBytes > $1.memoryBytes }
        .prefix(arguments["limit"]?.int ?? 25)
      return JSONFiles.string(Array(shown))
    },
    MCPTool(
      name: "glade_simulators",
      description: "Running iOS, watchOS, tvOS and visionOS simulators with the memory each one holds and whether it looks in use. Simulators are often the largest memory user on a developer’s Mac.",
      schema: none, readOnly: true
    ) { _ in
      JSONFiles.string(await SystemSampler().simulators())
    },
    MCPTool(
      name: "glade_context",
      description: "What the person is doing right now: the app in front, seconds since they last typed or moved the pointer, whether they’re gaming, and which apps are busy, playing audio or keeping the Mac awake. Check this before suggesting anything be quit.",
      schema: none, readOnly: true
    ) { _ in
      JSONFiles.string(await SystemSampler().context())
    },
    MCPTool(
      name: "glade_suggest",
      description: "What Glade’s own rules would quit or shut down to free memory, with the reason for each. It never suggests the app in front, anything playing audio, anything keeping the Mac awake, or anything doing real work.",
      schema: none, readOnly: true
    ) { _ in
      let sampler = SystemSampler()
      let snapshot = await sampler.snapshot()
      let apps = await sampler.apps()
      let context = ActivityContext.current(apps: apps, power: snapshot.power)
      let simulators = await sampler.simulators()
      return JSONFiles.string(PerformanceAdvisor.suggestions(snapshot: snapshot, apps: apps, context: context, simulators: simulators))
    },
    MCPTool(
      name: "glade_quit",
      description: "Ask an app to quit, as choosing Quit from its menu would, so it can ask about unsaved work. Tell the person what you’re quitting and why first. `force` ends it immediately and loses unsaved work: use it only when the person explicitly asks. macOS’s own apps and Glade are refused.",
      schema: #"{"type":"object","properties":{"app":{"type":"string","description":"The app’s name or bundle identifier."},"force":{"type":"boolean"},"relaunch":{"type":"boolean","description":"Quit and open it again."}},"required":["app"],"additionalProperties":false}"#,
      readOnly: false
    ) { arguments in
      guard let app = arguments["app"]?.string else { throw MCPFailure(message: "app is required.") }
      let result: AppActionResult
      if arguments["relaunch"]?.bool == true {
        result = try await AppControl.relaunch(app)
      } else if arguments["force"]?.bool == true {
        result = try await AppControl.forceQuit(app)
      } else {
        result = try await AppControl.quit(app)
      }
      return JSONFiles.string(result)
    },
    MCPTool(
      name: "glade_shutdown_simulator",
      description: "Shut down one simulator by name or identifier, like turning a phone off: its apps stop and its data stays. Refused when the simulator looks in use unless `force` is true.",
      schema: #"{"type":"object","properties":{"simulator":{"type":"string","description":"The simulator’s name or UDID from glade_simulators."},"force":{"type":"boolean"}},"required":["simulator"],"additionalProperties":false}"#,
      readOnly: false
    ) { arguments in
      guard let wanted = arguments["simulator"]?.string else { throw MCPFailure(message: "simulator is required.") }
      let simulator = try SimulatorControl.resolve(wanted, in: await SystemSampler().simulators())
      if simulator.inUse, arguments["force"]?.bool != true {
        throw MCPFailure(message: "\(simulator.name) looks in use (\(simulator.inUseReasons.joined(separator: ", "))). Pass force to shut it down anyway.")
      }
      return JSONFiles.string(try await SimulatorControl.shutdown(simulator))
    },
    MCPTool(
      name: "glade_show",
      description: "Open Glade’s window on a section, so the person can see what you’re talking about: overview, storage, performance, assistant or history. Starts the app if it isn’t running. Changes nothing on the Mac.",
      schema: #"{"type":"object","properties":{"section":{"type":"string","enum":["overview","storage","performance","assistant","history"]}},"required":["section"],"additionalProperties":false}"#,
      readOnly: true
    ) { arguments in
      guard let section = arguments["section"]?.string else { throw MCPFailure(message: "section is required.") }
      return try await Show.open(section)
    },
  ]
}
