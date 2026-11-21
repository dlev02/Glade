import AppKit
import ApplicationServices
import ArgumentParser
import Foundation
import GladeKit

/// For checking Glade itself: a copy of the app showing sample data, started in the
/// background, whose buttons and links are pressed through Accessibility (as VoiceOver
/// would) and whose window is captured. Snapshots can’t press anything; this can.
/// The sample copy runs beside the real one and never saves settings.
struct Drive: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "drive",
    abstract: "For checking Glade itself: start a sample copy of the app, press its buttons, capture its window.",
    discussion: """
      The terminal needs Accessibility access. Steps:
        glade drive launch <Glade.app> -startSection network -demoRouter att
        glade drive tree --match Forget
        glade drive press Forget
        glade drive shot --out /tmp/x.png
        glade drive quit
      """,
    shouldDisplay: false,
    subcommands: [Launch.self, Tree.self, Press.self, Click.self, Shot.self, End.self]
  )

  static let pidFile = FileManager.default.temporaryDirectory.appendingPathComponent("glade-drive.pid")

  static func pid() throws -> pid_t {
    guard let text = try? String(contentsOf: pidFile, encoding: .utf8), let pid = pid_t(text.trimmingCharacters(in: .whitespacesAndNewlines)),
          NSRunningApplication(processIdentifier: pid) != nil
    else { throw ValidationError("No sample copy is running. Start one with `glade drive launch <Glade.app>`.") }
    return pid
  }

  static func requireAccessibility() throws {
    guard AXIsProcessTrusted() else { throw ValidationError("This terminal needs Accessibility access (System Settings › Privacy & Security › Accessibility).") }
  }

  // MARK: Launch

  struct Launch: AsyncParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Start a sample copy of the app in the background.")
    @Argument(help: "The Glade.app to start.") var app: String
    @Argument(parsing: .captureForPassthrough, help: "Launch arguments, such as -startSection network.") var arguments: [String] = []

    func run() async throws {
      try Drive.requireAccessibility()
      let configuration = NSWorkspace.OpenConfiguration()
      configuration.activates = false
      configuration.createsNewApplicationInstance = true
      configuration.arguments = ["-demo", "YES"] + arguments
      let running = try await NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: app), configuration: configuration)
      try String(running.processIdentifier).write(to: Drive.pidFile, atomically: true, encoding: .utf8)
      // Wait for its window.
      let element = AXUIElementCreateApplication(running.processIdentifier)
      for _ in 0..<60 {
        if !(AX.children(element, kAXWindowsAttribute).isEmpty) { break }
        try await Task.sleep(for: .milliseconds(250))
      }
      try await Task.sleep(for: .seconds(2))
      print("Started pid \(running.processIdentifier)")
    }
  }

  // MARK: Tree

  struct Tree: AsyncParsableCommand {
    static let configuration = CommandConfiguration(abstract: "List the window’s elements: role, identifier and text.")
    @Option(help: "Only lines containing this text.") var match: String?

    func run() async throws {
      try Drive.requireAccessibility()
      let app = AXUIElementCreateApplication(try Drive.pid())
      var lines: [String] = []
      AX.walk(app) { element, depth in
        let line = String(repeating: "  ", count: depth) + AX.describe(element)
        if match.map({ line.localizedCaseInsensitiveContains($0) }) ?? true { lines.append(line) }
        return lines.count < 600
      }
      print(lines.joined(separator: "\n"))
    }
  }

  // MARK: Press

  struct Press: AsyncParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Press the first element whose identifier, title or text matches.")
    @Argument(help: "An accessibility identifier, or the element’s title or text.") var target: String
    @Option(help: "Seconds to wait afterwards.") var settle: Double = 1.5

    func run() async throws {
      try Drive.requireAccessibility()
      let app = AXUIElementCreateApplication(try Drive.pid())
      var exact: AXUIElement?
      var partial: AXUIElement?
      AX.walk(app) { element, _ in
        // Links in SwiftUI often don't list their press action, but take it.
        let role = AX.string(element, kAXRoleAttribute) ?? ""
        guard AX.actions(element).contains(kAXPressAction as String) || ["AXLink", "AXButton"].contains(role) else { return true }
        let texts = [AX.string(element, kAXIdentifierAttribute), AX.string(element, kAXTitleAttribute),
                     AX.string(element, kAXDescriptionAttribute), AX.string(element, kAXValueAttribute)].compactMap { $0 }
        if texts.contains(target) { exact = element; return false }
        if partial == nil, texts.contains(where: { $0.localizedCaseInsensitiveContains(target) }) { partial = element }
        return true
      }
      guard let element = exact ?? partial else { throw ValidationError("Nothing pressable matches “\(target)”. Try `glade drive tree --match …`.") }
      let name = AX.describe(element)
      let result = AXUIElementPerformAction(element, kAXPressAction as CFString)
      guard result == .success else { throw ValidationError("Pressing \(name) failed (AXError \(result.rawValue)).") }
      print("Pressed \(name)")
      try await Task.sleep(for: .seconds(settle))
    }
  }

  // MARK: Click

  /// For what Accessibility can’t press, such as a link inside an answer’s text: brings
  /// the sample copy forward for a moment, clicks the element’s centre with the real
  /// pointer, and gives the front back to the app that had it.
  struct Click: AsyncParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Click an element with the pointer; takes over the screen for about a second.")
    @Argument(help: "An accessibility identifier, or the element’s title or text.") var target: String

    func run() async throws {
      try Drive.requireAccessibility()
      let pid = try Drive.pid()
      let previous = NSWorkspace.shared.frontmostApplication
      let returnTo = previous?.processIdentifier == pid ? nil : previous
      NSRunningApplication(processIdentifier: pid)?.activate()
      try await Task.sleep(for: .seconds(1))
      var found: AXUIElement?
      AX.walk(AXUIElementCreateApplication(pid)) { element, _ in
        let texts = [AX.string(element, kAXIdentifierAttribute), AX.string(element, kAXTitleAttribute), AX.string(element, kAXValueAttribute)].compactMap { $0 }
        if texts.contains(where: { $0.localizedCaseInsensitiveContains(target) }), AX.string(element, kAXRoleAttribute) != "AXStaticText" || found == nil {
          found = element
          if AX.string(element, kAXRoleAttribute) != "AXStaticText" { return false }
        }
        return true
      }
      defer { returnTo?.activate() }
      guard let element = found, let frame = AX.frame(element) else { throw ValidationError("Nothing on screen matches “\(target)”.") }
      let point = CGPoint(x: frame.midX, y: frame.midY)
      for type in [CGEventType.leftMouseDown, .leftMouseUp] {
        CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: point, mouseButton: .left)?.post(tap: .cghidEventTap)
        try await Task.sleep(for: .milliseconds(60))
      }
      print("Clicked \(AX.describe(element)) at \(Int(point.x)),\(Int(point.y))")
      try await Task.sleep(for: .milliseconds(800))
    }
  }

  // MARK: Shot

  struct Shot: AsyncParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Have the sample copy draw its largest window to a PNG, even behind others or in Stage Manager.")
    @Option(help: "Where to write the PNG.") var out = "/tmp/glade-drive.png"

    func run() async throws {
      _ = try Drive.pid()
      let path = URL(fileURLWithPath: out).standardizedFileURL.path
      try? FileManager.default.removeItem(atPath: path)
      DistributedNotificationCenter.default().postNotificationName(
        Notification.Name("io.github.dlev02.glade.drive.shot"), object: path, userInfo: nil, deliverImmediately: true
      )
      for _ in 0..<40 {
        if FileManager.default.fileExists(atPath: path) { print(path); return }
        try await Task.sleep(for: .milliseconds(250))
      }
      throw ValidationError("The sample copy didn’t draw its window. Was it started with `glade drive launch`?")
    }
  }

  // MARK: Quit

  struct End: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "quit", abstract: "Quit the sample copy.")

    func run() async throws {
      let pid = try Drive.pid()
      NSRunningApplication(processIdentifier: pid)?.terminate()
      try? FileManager.default.removeItem(at: Drive.pidFile)
      print("Quit pid \(pid)")
    }
  }
}

/// Small readers over the Accessibility API.
enum AX {
  static func value(_ element: AXUIElement, _ attribute: String) -> AnyObject? {
    var value: AnyObject?
    return AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success ? value : nil
  }

  static func string(_ element: AXUIElement, _ attribute: String) -> String? {
    guard let text = value(element, attribute) as? String, !text.isEmpty else { return nil }
    return text
  }

  static func children(_ element: AXUIElement, _ attribute: String = kAXChildrenAttribute) -> [AXUIElement] {
    (value(element, attribute) as? [AXUIElement]) ?? []
  }

  /// The element’s frame in screen points, top-left origin as mouse events use.
  static func frame(_ element: AXUIElement) -> CGRect? {
    guard let position = value(element, kAXPositionAttribute), let size = value(element, kAXSizeAttribute) else { return nil }
    var origin = CGPoint.zero, extent = CGSize.zero
    guard AXValueGetValue(position as! AXValue, .cgPoint, &origin), AXValueGetValue(size as! AXValue, .cgSize, &extent) else { return nil }
    return CGRect(origin: origin, size: extent)
  }

  static func actions(_ element: AXUIElement) -> [String] {
    var names: CFArray?
    guard AXUIElementCopyActionNames(element, &names) == .success else { return [] }
    return (names as? [String]) ?? []
  }

  /// Visits every element depth first; the visitor returns false to stop.
  static func walk(_ root: AXUIElement, visit: (AXUIElement, Int) -> Bool) {
    var stopped = false
    func step(_ element: AXUIElement, _ depth: Int) {
      guard !stopped, depth < 40 else { return }
      if !visit(element, depth) { stopped = true; return }
      let kids = depth == 0 ? children(element, kAXWindowsAttribute) : children(element)
      for child in kids { step(child, depth + 1) }
    }
    step(root, 0)
  }

  static func describe(_ element: AXUIElement) -> String {
    let role = string(element, kAXRoleAttribute) ?? "?"
    var parts = [role]
    let names = actions(element).filter { $0 != "AXScrollToVisible" && $0 != "AXShowMenu" }
    if !names.isEmpty { parts.append("[\(names.joined(separator: ","))]") }
    if let id = string(element, kAXIdentifierAttribute) { parts.append("#\(id)") }
    for attribute in [kAXTitleAttribute, kAXDescriptionAttribute, kAXValueAttribute] {
      if let text = string(element, attribute) { parts.append("“\(text.prefix(80))”") }
    }
    return parts.joined(separator: " ")
  }
}
