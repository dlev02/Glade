import Foundation

/// One kind of re-creatable folder inside a project, and what proves a folder is one.
/// A folder merely named `build` or `dist` is never enough: a manifest next to it (or a
/// marker inside it) has to say what made it.
struct ProjectRule: Sendable {
  var id: String
  var names: [String]
  /// Shown in titles: "node_modules – my-app".
  var label: String
  var category: StorageCategory
  var recovery: Recovery
  /// The gentlest clean level allowed to select it once the project has sat idle.
  var level: CleanLevel
  var detail: String
  /// Files next to the folder, any one of which proves what it is.
  var siblings: [String] = []
  /// Extensions of folders next to it ("xcodeproj") that prove it too.
  var siblingExtensions: [String] = []
  /// Entries inside the folder, any one of which must exist.
  var inside: [String] = []
  /// Names that are also used for source: only counted when git says they’re ignored.
  var mustBeIgnored = false
  /// Many small folders per project (Python caches): reported as one finding.
  var grouped = false
  /// The folder to report, relative to the matched one (`vendor` → `vendor/bundle`).
  var subpath: String?
  /// How long the project must sit untouched before `level` selects it. Bolder levels
  /// wait half as long, then not at all.
  var idleDays = ProjectScanner.idleDays

  func proves(parent: String, folder: String) -> Bool {
    if !inside.isEmpty, !inside.contains(where: { FileFacts.exists(folder + "/" + $0) }) { return false }
    if siblings.isEmpty && siblingExtensions.isEmpty { return true }
    if siblings.contains(where: { FileFacts.exists(parent + "/" + $0) }) { return true }
    if !siblingExtensions.isEmpty {
      let names = (try? FileManager.default.contentsOfDirectory(atPath: parent)) ?? []
      return names.contains { siblingExtensions.contains(($0 as NSString).pathExtension) }
    }
    return false
  }

  /// The proof, in words, for the evidence list.
  func proofSentence(parent: String, folder: String) -> String {
    if let file = siblings.first(where: { FileFacts.exists(parent + "/" + $0) }) {
      if let marker = inside.first(where: { FileFacts.exists(folder + "/" + $0) }), marker != subpath {
        return "Next to \(file) and contains \(marker)."
      }
      return "Next to \(file), which says what goes in it."
    }
    if !siblingExtensions.isEmpty {
      let names = (try? FileManager.default.contentsOfDirectory(atPath: parent)) ?? []
      if let project = names.sorted().first(where: { siblingExtensions.contains(($0 as NSString).pathExtension) }) {
        return "Next to \(project)."
      }
    }
    if let marker = inside.first(where: { FileFacts.exists(folder + "/" + $0) }) {
      return "Contains \(marker), which the tool that made it writes."
    }
    return "Named \(label), which only Python uses."
  }
}

enum ProjectRules {
  static let gradle = ["build.gradle", "build.gradle.kts", "settings.gradle", "settings.gradle.kts"]

  /// For build output the next build makes again from the project itself: Careful
  /// waits a week, Balanced three days, Aggressive none, in line with Xcode’s build
  /// data. Dependencies that are downloaded again keep the longer wait.
  static let rebuildIdleDays = 7

  static let all: [ProjectRule] = [
    ProjectRule(
      id: "project.node_modules", names: ["node_modules"], label: "node_modules",
      category: .projectDependencies, recovery: .reinstall, level: .balanced,
      detail: "Packages npm, yarn, pnpm or bun installed for this project; running the install command puts them back.",
      siblings: ["package.json"]
    ),
    ProjectRule(
      id: "project.venv", names: [".venv", "venv", "env"], label: "Python environment",
      category: .projectDependencies, recovery: .reinstall, level: .balanced,
      detail: "A Python virtual environment for this project; recreating it and reinstalling its packages brings it back.",
      inside: ["pyvenv.cfg"]
    ),
    // The two Python cache rules share an id so a project’s caches add up to one finding.
    ProjectRule(
      id: "project.python-caches", names: ["__pycache__"],
      label: "Python caches", category: .buildOutputs, recovery: .automatic, level: .careful,
      detail: "Compiled Python files and test and lint caches, which Python and those tools write again as they run.",
      grouped: true, idleDays: rebuildIdleDays
    ),
    ProjectRule(
      id: "project.python-caches", names: [".pytest_cache", ".mypy_cache", ".ruff_cache"],
      label: "Python caches", category: .buildOutputs, recovery: .automatic, level: .careful,
      detail: "Compiled Python files and test and lint caches, which Python and those tools write again as they run.",
      inside: ["CACHEDIR.TAG"], grouped: true, idleDays: rebuildIdleDays
    ),
    ProjectRule(
      id: "project.tox", names: [".tox"], label: ".tox", category: .buildOutputs, recovery: .automatic, level: .balanced,
      detail: "Test environments made by tox, which it rebuilds the next time it runs.",
      siblings: ["tox.ini", "pyproject.toml", "setup.cfg"]
    ),
    ProjectRule(
      id: "project.pods", names: ["Pods"], label: "Pods", category: .projectDependencies, recovery: .reinstall,
      level: .balanced, detail: "CocoaPods libraries for this project; `pod install` puts them back.",
      siblings: ["Podfile"]
    ),
    ProjectRule(
      id: "project.composer", names: ["vendor"], label: "vendor", category: .projectDependencies, recovery: .reinstall,
      level: .balanced, detail: "PHP packages Composer installed for this project; `composer install` puts them back.",
      siblings: ["composer.json"]
    ),
    ProjectRule(
      id: "project.bundler", names: ["vendor"], label: "vendor/bundle", category: .projectDependencies,
      recovery: .reinstall, level: .balanced,
      detail: "Ruby gems Bundler installed into this project; `bundle install` puts them back.",
      siblings: ["Gemfile"], inside: ["bundle"], subpath: "bundle"
    ),
    ProjectRule(
      id: "project.swiftpm", names: [".build"], label: ".build", category: .buildOutputs, recovery: .automatic,
      level: .careful,
      detail: "Swift Package Manager’s build products and checked-out dependencies, which the next build recreates.",
      siblings: ["Package.swift"], idleDays: rebuildIdleDays
    ),
    ProjectRule(
      id: "project.deriveddata", names: ["DerivedData"], label: "DerivedData", category: .buildOutputs,
      recovery: .automatic, level: .careful,
      detail: "Xcode’s build products and index for this project, which the next build recreates.",
      siblings: ["Package.swift"], siblingExtensions: ["xcodeproj", "xcworkspace"], idleDays: rebuildIdleDays
    ),
    ProjectRule(
      id: "project.target", names: ["target"], label: "target", category: .buildOutputs, recovery: .automatic,
      level: .careful, detail: "Compiled output from Cargo or Maven, which the next build recreates.",
      siblings: ["Cargo.toml", "pom.xml"], idleDays: rebuildIdleDays
    ),
    ProjectRule(
      id: "project.build", names: ["build"], label: "build", category: .buildOutputs, recovery: .automatic,
      level: .careful, detail: "Output of this project’s build, which git ignores and the next build recreates.",
      siblings: ["package.json", "pyproject.toml", "setup.py", "CMakeLists.txt", "meson.build", "pubspec.yaml", "Podfile"] + gradle,
      siblingExtensions: ["xcodeproj", "xcworkspace"], mustBeIgnored: true, idleDays: rebuildIdleDays
    ),
    ProjectRule(
      id: "project.dist", names: ["dist"], label: "dist", category: .buildOutputs, recovery: .automatic,
      level: .careful, detail: "Bundled or packaged output of this project’s build, which git ignores and the next build recreates.",
      siblings: ["package.json", "pyproject.toml", "setup.py"], mustBeIgnored: true, idleDays: rebuildIdleDays
    ),
    ProjectRule(
      id: "project.out", names: ["out"], label: "out", category: .buildOutputs, recovery: .automatic,
      level: .careful, detail: "Output of this project’s build or export, which git ignores and the next build recreates.",
      siblings: ["package.json"], mustBeIgnored: true, idleDays: rebuildIdleDays
    ),
    ProjectRule(
      id: "project.next", names: [".next"], label: ".next", category: .buildOutputs, recovery: .automatic,
      level: .careful, detail: "Next.js build output and cache, which the next `next dev` or `next build` recreates.",
      siblings: ["package.json"], idleDays: rebuildIdleDays
    ),
    ProjectRule(
      id: "project.framework-generated", names: [".nuxt", ".svelte-kit"], label: "generated files",
      category: .buildOutputs, recovery: .automatic, level: .careful,
      detail: "Files the web framework generates, which it writes again the next time the dev server or a build runs.",
      siblings: ["package.json"], idleDays: rebuildIdleDays
    ),
    ProjectRule(
      id: "project.js-caches", names: [".turbo", ".parcel-cache", ".vite", ".angular"], label: "build cache",
      category: .buildOutputs, recovery: .automatic, level: .careful,
      detail: "A JavaScript build tool’s cache, which fills again on the next build.",
      siblings: ["package.json"], idleDays: rebuildIdleDays
    ),
    ProjectRule(
      id: "project.cache", names: [".cache"], label: ".cache", category: .buildOutputs, recovery: .automatic,
      level: .careful, detail: "A JavaScript build tool’s cache, which git ignores and the next build fills again.",
      siblings: ["package.json"], mustBeIgnored: true, idleDays: rebuildIdleDays
    ),
    ProjectRule(
      id: "project.expo", names: [".expo"], label: ".expo", category: .buildOutputs, recovery: .automatic,
      level: .careful, detail: "Expo’s local dev-server state for this project, which it recreates the next time you start it.",
      siblings: ["package.json"], idleDays: rebuildIdleDays
    ),
    ProjectRule(
      id: "project.gradle", names: [".gradle"], label: ".gradle", category: .buildOutputs, recovery: .automatic,
      level: .careful, detail: "Gradle’s caches for this project, which the next build recreates.",
      siblings: gradle + ["gradlew"], idleDays: rebuildIdleDays
    ),
    ProjectRule(
      id: "project.dart", names: [".dart_tool"], label: ".dart_tool", category: .buildOutputs, recovery: .automatic,
      level: .balanced, detail: "Dart and Flutter’s package setup and build cache, which `flutter pub get` or the next build recreates.",
      siblings: ["pubspec.yaml"]
    ),
    ProjectRule(
      id: "project.terraform", names: [".terraform"], label: ".terraform", category: .projectDependencies,
      recovery: .redownload, level: .balanced,
      detail: "Terraform providers and modules that `terraform init` downloaded, and downloads again.",
      siblingExtensions: ["tf"]
    ),
    ProjectRule(
      id: "project.coverage", names: ["coverage", ".nyc_output"], label: "coverage", category: .buildOutputs,
      recovery: .automatic, level: .careful,
      detail: "Test coverage reports, which the next test run with coverage writes again.",
      siblings: ["package.json"], mustBeIgnored: true, idleDays: rebuildIdleDays
    ),
    ProjectRule(
      id: "project.storybook", names: ["storybook-static"], label: "storybook-static", category: .buildOutputs,
      recovery: .automatic, level: .careful, detail: "A static Storybook build, which `build-storybook` recreates.",
      siblings: ["package.json"], idleDays: rebuildIdleDays
    ),
  ]

  static let byName: [String: [Int]] = {
    var map: [String: [Int]] = [:]
    for (index, rule) in all.enumerated() {
      for name in rule.names { map[name, default: []].append(index) }
    }
    return map
  }()

  /// Folders never walked into even when nothing proves what they are: they only ever
  /// hold installed packages or Xcode’s output.
  static let prunedNames: Set<String> = ["node_modules", "Pods", "DerivedData", "bower_components", "jspm_packages"]

  /// Files whose modification shows someone worked on the project. Install folders
  /// themselves are never consulted: installing touches every file in them.
  static let manifests = [
    "package.json", "package-lock.json", "yarn.lock", "pnpm-lock.yaml", "bun.lockb", "bun.lock",
    "Podfile", "Podfile.lock", "Gemfile", "Gemfile.lock", "composer.json", "composer.lock",
    "Cargo.toml", "Cargo.lock", "Package.swift", "Package.resolved", "pyproject.toml",
    "requirements.txt", "setup.py", "setup.cfg", "poetry.lock", "uv.lock", "Pipfile", "Pipfile.lock",
    "tox.ini", "pubspec.yaml", "pubspec.lock", "pom.xml", "CMakeLists.txt", "go.mod",
  ] + gradle

  /// Files that list a Python environment’s packages so they can be reinstalled.
  static let pythonDependencyLists = [
    "requirements.txt", "requirements-dev.txt", "pyproject.toml", "Pipfile", "Pipfile.lock",
    "poetry.lock", "uv.lock", "setup.py", "setup.cfg", "environment.yml",
  ]

  static func match(name: String, parent: String, folder: String) -> (rule: Int, path: String)? {
    guard let indices = byName[name] else { return nil }
    for index in indices where all[index].proves(parent: parent, folder: folder) {
      let rule = all[index]
      return (index, rule.subpath.map { folder + "/" + $0 } ?? folder)
    }
    return nil
  }
}
