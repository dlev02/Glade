import AppKit
import GladeKit
import SwiftUI

/// Spacing, shapes and colours used everywhere, so every screen looks like it came
/// from the same hand. Layout sits on a 4-point grid.
public enum Metrics {
  public static let hairline: CGFloat = 0.5
  public static let xs: CGFloat = 4
  public static let s: CGFloat = 8
  public static let m: CGFloat = 12
  public static let l: CGFloat = 16
  public static let xl: CGFloat = 24
  public static let xxl: CGFloat = 32
  /// Corner radius of a card. Things inside a card use `innerRadius`.
  public static let cardRadius: CGFloat = 18
  public static let innerRadius: CGFloat = 10
  /// The widest a page’s content gets before it stops growing; past that it sits in
  /// the middle of the window. Storage is the exception: its list uses the full width.
  public static let contentWidth: CGFloat = 960
  /// History’s rows are narrower, so a clean’s size sits near its name.
  public static let listWidth: CGFloat = 720
}

/// How the app looks: follow the system, or always light or dark.
public enum Appearance: String, CaseIterable, Identifiable, Sendable {
  case system, light, dark

  public var id: String { rawValue }
  public var title: String { rawValue.capitalized }

  public var colorScheme: ColorScheme? {
    switch self {
    case .system: nil
    case .light: .light
    case .dark: .dark
    }
  }
}

/// The accent colours on offer, plus one of the person’s own choosing.
public enum Accent: String, CaseIterable, Identifiable, Sendable {
  case glade, blue, indigo, purple, pink, orange, graphite, custom

  public var id: String { rawValue }

  public var title: String {
    switch self {
    case .glade: "Glade"
    case .graphite: "Graphite"
    case .custom: "Custom"
    default: rawValue.capitalized
    }
  }

  /// - Parameter custom: The person’s own colour as a hex string, used for `.custom`.
  public func color(custom: String = "") -> Color {
    switch self {
    case .glade: Palette.glade
    case .blue: .blue
    case .indigo: .indigo
    case .purple: .purple
    case .pink: .pink
    case .orange: .orange
    case .graphite: Color(nsColor: .systemGray)
    case .custom: Color(hex: custom) ?? Palette.glade
    }
  }
}

public enum Palette {
  /// The app’s own green: calmer and a touch cooler than the system green.
  public static let glade = Color(light: 0x1C9A68, dark: 0x3FD897)
  /// The surface cards sit on.
  public static let card = Color(nsColor: .controlBackgroundColor)
  public static let hairline = Color(nsColor: .separatorColor)
  /// The empty part of a bar or gauge.
  public static let track = Color.primary.opacity(0.08)

  public static let good = Color.green
  public static let warning = Color.orange
  public static let critical = Color.red
  /// What an accent fill becomes in a window that isn’t active: the grey the system
  /// gives a ticked checkbox there, dark enough to hold a white tick.
  public static let inactiveFill = Color(nsColor: .systemGray)

  /// The colour for a level of load from 0 to 1: calm until it matters.
  public static func load(_ fraction: Double) -> Color {
    switch fraction {
    case ..<0.7: good
    case ..<0.9: warning
    default: critical
    }
  }
}

/// Storage categories gathered into the handful of families shown in the storage bar.
/// Twenty-six colours would be noise; seven can be told apart at a glance.
public enum CategoryFamily: String, CaseIterable, Identifiable, Sendable {
  case developer, simulators, agents, models, apps, files, system

  public var id: String { rawValue }

  public var title: String {
    switch self {
    case .developer: "Developer"
    case .simulators: "Simulators"
    case .agents: "Agents"
    case .models: "AI Models"
    case .apps: "Apps"
    case .files: "Files & Media"
    case .system: "System"
    }
  }

  public var color: Color {
    switch self {
    case .developer: .blue
    case .simulators: .teal
    case .agents: .purple
    case .models: .pink
    case .apps: .orange
    case .files: .yellow
    case .system: Color(nsColor: .systemGray)
    }
  }

  /// The colour for a symbol on the family’s pale tile: yellow and teal are too light
  /// to read on their own tint in light mode, so they darken there.
  public var glyphColor: Color {
    switch self {
    case .files: Color(light: 0x9A6700, dark: 0xFFD60A)
    case .simulators: Color(light: 0x0A7A8C, dark: 0x40C8E0)
    default: color
    }
  }
}

extension StorageCategory {
  public var family: CategoryFamily {
    switch self {
    case .developerCaches, .packageCaches, .buildOutputs, .projectDependencies, .xcode, .sdks, .editorExtensions: .developer
    case .simulators, .emulators: .simulators
    case .agentHistory, .agentWorktrees: .agents
    case .aiModels: .models
    case .installedApps, .appCaches, .browserCaches, .appLeftovers, .appCopies: .apps
    case .downloads, .mediaDownloads, .largeFiles, .duplicates, .games, .deviceBackups: .files
    case .temporaryFiles, .logs, .trash, .documentVersions: .system
    }
  }

  /// An SF Symbol for the category. Every name here is checked against the catalog.
  public var symbol: String {
    switch self {
    case .temporaryFiles: "document.badge.clock"
    case .appCaches: "square.stack.3d.up"
    case .browserCaches: "globe"
    case .logs: "text.page.badge.magnifyingglass"
    case .trash: "trash"
    case .developerCaches: "hammer"
    case .packageCaches: "shippingbox"
    case .buildOutputs: "gearshape.2"
    case .projectDependencies: "puzzlepiece.extension"
    case .xcode: "wrench.and.screwdriver"
    case .simulators: "iphone"
    case .emulators: "server.rack"
    case .sdks: "cube.transparent"
    case .aiModels: "brain"
    case .agentHistory: "bubble.left.and.text.bubble.right"
    case .agentWorktrees: "arrow.trianglehead.branch"
    case .editorExtensions: "puzzlepiece"
    case .installedApps: "square.grid.2x2"
    case .appLeftovers: "app.dashed"
    case .appCopies: "square.on.square"
    case .downloads: "arrow.down.circle"
    case .mediaDownloads: "play.rectangle"
    case .largeFiles: "zipper.page"
    case .duplicates: "document.on.document"
    case .games: "gamecontroller"
    case .deviceBackups: "externaldrive.badge.timemachine"
    case .documentVersions: "clock.arrow.trianglehead.2.counterclockwise.rotate.90"
    }
  }
}

extension Recovery {
  public var symbol: String {
    switch self {
    case .automatic: "arrow.trianglehead.2.clockwise.rotate.90"
    case .redownload: "arrow.down.circle"
    case .reinstall: "shippingbox"
    case .permanent: "exclamationmark.triangle"
    }
  }

  public var color: Color {
    switch self {
    case .automatic: .green
    case .redownload: .blue
    case .reinstall: .orange
    case .permanent: .red
    }
  }

  /// What happens after removal, for a tooltip or a detail line.
  public var explanation: String {
    switch self {
    case .automatic: "The app or tool that made this rebuilds it when it’s next needed."
    case .redownload: "It downloads again when needed, which takes time and bandwidth."
    case .reinstall: "It comes back when you reinstall or rebuild."
    case .permanent: "Nothing recreates this once it’s gone."
    }
  }
}

extension Color {
  /// A colour with separate light and dark values, given as 0xRRGGBB.
  public init(light: UInt32, dark: UInt32) {
    self.init(nsColor: NSColor(name: nil) { appearance in
      let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
      return NSColor(hex: isDark ? dark : light)
    })
  }

  /// Parses `#RRGGBB` or `RRGGBB`.
  public init?(hex: String) {
    let cleaned = hex.trimmingCharacters(in: CharacterSet(charactersIn: "# "))
    guard cleaned.count == 6, let value = UInt32(cleaned, radix: 16) else { return nil }
    self.init(nsColor: NSColor(hex: value))
  }

  /// The colour as `#RRGGBB`, for saving.
  public var hexString: String {
    let color = NSColor(self).usingColorSpace(.sRGB) ?? .systemGreen
    return String(format: "#%02X%02X%02X", Int(color.redComponent * 255), Int(color.greenComponent * 255), Int(color.blueComponent * 255))
  }
}

extension Color {
  /// This colour, darkened just enough for white text on it to be readable (4.5:1).
  /// The accent as people choose it is for marks: figures, chart lines, ticks. This is
  /// the version for fills: the sidebar selection, prominent buttons, switches.
  public var readableFill: Color {
    let source = NSColor(self)
    return Color(nsColor: NSColor(name: nil) { appearance in
      var resolved = NSColor.systemGreen
      appearance.performAsCurrentDrawingAppearance {
        resolved = source.usingColorSpace(.sRGB) ?? .systemGreen
      }
      var steps = 0
      while resolved.contrastWithWhite < 4.5, steps < 24 {
        resolved = resolved.blended(withFraction: 0.06, of: .black) ?? resolved
        steps += 1
      }
      return resolved
    })
  }
}

extension EnvironmentValues {
  /// The accent at full brightness, for figures, chart lines and ticks. Fills use
  /// `.tint`, which is the darker `readableFill`.
  @Entry public var accentMark: Color = Palette.glade
}

extension View {
  /// Applies the person’s accent: the readable fill as the tint, and the bright
  /// mark in the environment.
  public func accent(_ accent: Color) -> some View {
    tint(accent.readableFill).environment(\.accentMark, accent)
  }
}

extension NSColor {
  /// The WCAG contrast ratio between this colour and white.
  var contrastWithWhite: CGFloat {
    func linear(_ value: CGFloat) -> CGFloat {
      value <= 0.03928 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
    }
    let color = usingColorSpace(.sRGB) ?? self
    let luminance = 0.2126 * linear(color.redComponent) + 0.7152 * linear(color.greenComponent) + 0.0722 * linear(color.blueComponent)
    return 1.05 / (luminance + 0.05)
  }

  convenience init(hex: UInt32) {
    self.init(
      srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
      blue: CGFloat(hex & 0xFF) / 255, alpha: 1
    )
  }
}

extension Font {
  /// Large figures: free space, sizes, totals. SF Pro semibold, like every other large
  /// number, with natural digit widths so "114 GB" has no gaps around its ones.
  public static func figure(_ size: CGFloat = 34) -> Font {
    .system(size: size, weight: .semibold)
  }

  /// A large figure that updates while it’s watched (memory, processor, graphics):
  /// steady-width digits so it doesn’t jitter.
  public static func liveFigure(_ size: CGFloat = 34) -> Font {
    figure(size).monospacedDigit()
  }
}

extension String {
  /// The same text with a no-break space before each dash, so a wrapped name like
  /// "Old installer – Figma.dmg" never starts its second line with the dash.
  public var keepingDashWithName: String {
    replacingOccurrences(of: " \u{2013} ", with: "\u{00A0}\u{2013} ")
  }
}
