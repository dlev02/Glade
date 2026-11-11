import Foundation

/// The catalog of known locations. Each entry says what a place holds, how it comes
/// back after removal, and how careful to be. Classification errs toward caution:
/// when in doubt an entry is `caution` or left out.
public enum Catalog {
  public static let rules: [LocationRule] =
    temporary + appCaches + browsers + logs + trash + xcode + simulators + packageCaches
    + developerCaches + toolkits + emulators + models + agents + media + games + backups

  /// How long agent sessions and editor state sit untouched before they count as stale.
  public static let staleAgentDays = 14

  // MARK: Owners

  static let xcode_ = Owner("Xcode", bundleIDs: ["com.apple.dt.Xcode"])
  static let simulator = Owner("Simulator", bundleIDs: ["com.apple.iphonesimulator"])
  static let safari = Owner("Safari", bundleIDs: ["com.apple.Safari"])
  static let chrome = Owner("Chrome", bundleIDs: ["com.google.Chrome", "com.google.Chrome.*"])
  static let cursor = Owner("Cursor", bundleIDs: ["com.todesktop.230313mzl4w4u92"], processNames: ["Cursor"])
  static let vscode = Owner("Visual Studio Code", bundleIDs: ["com.microsoft.VSCode"], processNames: ["Code"])
  static let docker = Owner("Docker", bundleIDs: ["com.docker.docker"], processNames: ["com.docker.backend"])
  static let ollama = Owner("Ollama", bundleIDs: ["com.electron.ollama"], processNames: ["ollama"])
  static let spotify = Owner("Spotify", bundleIDs: ["com.spotify.client"])
  static let steam = Owner("Steam", bundleIDs: ["com.valvesoftware.steam"], processNames: ["steam_osx"])

  // MARK: Temporary files

  static let temporary: [LocationRule] = [
    LocationRule(
      id: "tmp.user", category: .temporaryFiles, title: "Temporary files",
      detail: "Scratch files apps left behind. Only ones untouched for three days are counted.",
      paths: ["$TMP/*"], olderThanDays: 3,
      skip: ["com.apple.*", "TemporaryItems", ".*", "*.sock", "*.lock", "*.pid"], minimumBytes: 1_000_000
    ),
    LocationRule(
      id: "tmp.cache", category: .temporaryFiles, title: "System-managed caches",
      detail: "Per-user caches macOS keeps for apps. They refill as apps run.",
      paths: ["$CACHE/*"], olderThanDays: 7,
      skip: ["com.apple.*", ".*", "clang", "TemporaryItems"], minimumBytes: 1_000_000
    ),
  ]

  // MARK: App caches

  static let appCaches: [LocationRule] = [
    LocationRule(
      id: "cache.app", category: .appCaches, title: "cache",
      detail: "Files this app saved to load faster. It rebuilds them as you use it.",
      paths: ["~/Library/Caches/*"], split: .each, titleStyle: .bundleID, blockWhileRunning: true,
      skip: [
        // Owned by more specific rules below, or by macOS itself.
        "com.apple.*", "CloudKit", "FamilyCircle", "GeoServices", "PassKit", "familycircled",
        "askpermissiond", "Homebrew", "Google", "BraveSoftware", "Microsoft Edge", "Firefox", "Mozilla",
        "Arc", "company.thebrowser.*", "com.operasoftware.*", "Vivaldi", "com.vivaldi.*",
        "com.openai.atlas", "at.studio.*", "com.duckduckgo.*", "pip", "pypoetry", "Yarn", "pnpm",
        "CocoaPods", "org.swift.swiftpm", "org.carthage.CarthageKit", "composer", "go-build",
        "ms-playwright", "ms-playwright-go", "electron", "Cypress", "typescript", "deno", "JetBrains",
        "com.spotify.client", "node-gyp", "Glade", "io.github.dlev02.glade", "com.apple.dt.Xcode",
        "SentryCrash", "bun", "uv", "huggingface", "turbo", "puppeteer",
      ]
    ),
    LocationRule(
      id: "cache.sandboxed", category: .appCaches, title: "cache",
      detail: "Files this app saved to load faster. It rebuilds them as you use it.",
      paths: ["~/Library/Containers/*/Data/Library/Caches"], split: .each, titleStyle: .container,
      blockWhileRunning: true, skipContaining: ["/Containers/com.apple."], minimumBytes: 20_000_000
    ),
    LocationRule(
      id: "cache.electron", category: .appCaches, title: "App web caches",
      detail: "Web content cached by apps built on Chromium (Slack, Discord, Claude, Notion and others). It reloads as needed.",
      paths: [
        "~/Library/Application Support/*/Cache", "~/Library/Application Support/*/Code Cache",
        "~/Library/Application Support/*/GPUCache", "~/Library/Application Support/*/DawnCache",
        "~/Library/Application Support/*/DawnGraphiteCache", "~/Library/Application Support/*/DawnWebGPUCache",
        "~/Library/Application Support/*/ShaderCache", "~/Library/Application Support/*/GrShaderCache",
        "~/Library/Application Support/*/CachedData", "~/Library/Application Support/*/CachedExtensionVSIXs",
        "~/Library/Application Support/*/Service Worker/CacheStorage",
        "~/Library/Application Support/*/Service Worker/ScriptCache",
        "~/Library/Application Support/*/Crashpad/completed", "~/Library/Application Support/*/Crashpad/pending",
        "~/Library/Application Support/*/component_crx_cache",
      ],
      olderThanDays: 2
    ),
  ]

  // MARK: Browsers

  static let browsers: [LocationRule] = [
    LocationRule(
      id: "browser.safari", category: .browserCaches, title: "Safari cache",
      detail: "Copies of pages and images. Safari downloads them again when you revisit a site.",
      paths: ["~/Library/Caches/com.apple.Safari", "~/Library/Caches/com.apple.Safari.SafeBrowsing", "~/Library/Caches/com.apple.WebKit.*"],
      owner: safari, blockWhileRunning: true
    ),
    LocationRule(
      id: "browser.chrome", category: .browserCaches, title: "Chrome cache",
      detail: "Copies of pages and images. Chrome downloads them again when you revisit a site.",
      paths: ["~/Library/Caches/Google/Chrome", "~/Library/Caches/Google/Chrome Beta", "~/Library/Caches/Google/Chrome Canary"],
      owner: chrome, blockWhileRunning: true
    ),
    LocationRule(
      id: "browser.others", category: .browserCaches, title: "cache",
      detail: "Copies of pages and images. The browser downloads them again when you revisit a site.",
      paths: [
        "~/Library/Caches/BraveSoftware", "~/Library/Caches/Microsoft Edge", "~/Library/Caches/Firefox",
        "~/Library/Caches/Mozilla", "~/Library/Caches/Arc", "~/Library/Caches/company.thebrowser.*",
        "~/Library/Caches/com.operasoftware.*", "~/Library/Caches/Vivaldi", "~/Library/Caches/com.vivaldi.*",
        "~/Library/Caches/com.openai.atlas", "~/Library/Caches/at.studio.*", "~/Library/Caches/com.duckduckgo.*",
      ],
      split: .each, titleStyle: .bundleID, blockWhileRunning: true
    ),
  ]

  // MARK: Logs

  static let logs: [LocationRule] = [
    LocationRule(
      id: "logs.user", category: .logs, title: "App logs",
      detail: "Diagnostic logs older than a week. Apps write new ones as they run.",
      paths: ["~/Library/Logs/*"], olderThanDays: 7,
      skip: ["Glade", "DiagnosticReports", "CoreSimulator"], minimumBytes: 1_000_000
    ),
    LocationRule(
      id: "logs.crashes", category: .logs, title: "Crash reports",
      detail: "Crash and hang reports older than two weeks. Useful only if you're still chasing that crash.",
      paths: ["~/Library/Logs/DiagnosticReports/*", "~/Library/Application Support/CrashReporter/*"],
      olderThanDays: 14, minimumBytes: 1_000_000
    ),
    LocationRule(
      id: "logs.electron", category: .logs, title: "App logs (Chromium apps)",
      detail: "Logs written by apps built on Chromium. They start fresh ones each launch.",
      paths: ["~/Library/Application Support/*/logs"], olderThanDays: 7, minimumBytes: 1_000_000
    ),
    LocationRule(
      id: "logs.simulator", category: .logs, title: "Simulator logs",
      detail: "Logs from iOS simulators. New ones are written when a simulator runs.",
      paths: ["~/Library/Logs/CoreSimulator"], owner: simulator, minimumBytes: 1_000_000
    ),
  ]

  // MARK: Trash

  static let trash: [LocationRule] = [
    LocationRule(
      id: "trash.user", category: .trash, title: "Trash",
      detail: "Things you've already thrown away. Emptying it removes them for good.",
      paths: ["~/.Trash"], recovery: .permanent, risk: .caution, method: .emptyTrash,
      contentsOnly: true, auto: .at(.balanced), minimumBytes: 1_000_000
    ),
  ]

  // MARK: Xcode

  static let xcode: [LocationRule] = [
    LocationRule(
      id: "xcode.deriveddata", category: .xcode, title: "Build data",
      detail: "Xcode's build products and indexes for one project. Rebuilt the next time you build it.",
      paths: ["~/Library/Developer/Xcode/DerivedData/*"], split: .each, titleStyle: .derivedData,
      owner: xcode_, idleDays: 3
    ),
    LocationRule(
      id: "xcode.bitrig", category: .xcode, title: "Bitrig build data",
      detail: "Build products Bitrig made for one project. Rebuilt the next time that project is built or previewed.",
      paths: ["~/Library/Bitrig/Users/*/Builds/*/DerivedData"], split: .each, titleStyle: .parent,
      owner: Owner("Bitrig", bundleIDs: ["app.bitrig.Bitrig"], processNames: ["Bitrig"]), idleDays: 3
    ),
    LocationRule(
      id: "xcode.testdevices", category: .simulators, title: "Test simulators",
      detail: "Copies of simulators Xcode makes to run tests in parallel. Xcode makes fresh ones the next time tests run.",
      paths: ["~/Library/Developer/XCTestDevices"], owner: xcode_, method: .simulatorSet(name: "testing"),
      idleDays: 3, allowsLibrariesInside: true
    ),
    LocationRule(
      id: "xcode.previews", category: .simulators, title: "Preview simulators",
      detail: "Simulators Xcode keeps for SwiftUI previews. Xcode makes fresh ones the next time a preview runs.",
      paths: ["~/Library/Developer/Xcode/UserData/Previews"], owner: xcode_, method: .simulatorSet(name: "previews"),
      idleDays: 3, allowsLibrariesInside: true
    ),
    LocationRule(
      id: "xcode.caches", category: .xcode, title: "Xcode caches",
      detail: "Interface Builder, documentation and playground caches. Xcode recreates them when needed.",
      paths: [
        "~/Library/Developer/Xcode/UserData/IB Support", "~/Library/Developer/Xcode/DocumentationCache",
        "~/Library/Developer/Xcode/DocumentationIndex", "~/Library/Caches/com.apple.dt.Xcode",
        "~/Library/Developer/XCPGDevices",
      ],
      owner: xcode_, allowsLibrariesInside: true
    ),
    LocationRule(
      id: "xcode.devicesupport", category: .xcode, title: "Device support",
      detail: "Debug symbols copied from a connected iPhone, iPad, Watch or Apple TV. Copied again when that device next connects.",
      paths: [
        "~/Library/Developer/Xcode/iOS DeviceSupport/*", "~/Library/Developer/Xcode/watchOS DeviceSupport/*",
        "~/Library/Developer/Xcode/tvOS DeviceSupport/*", "~/Library/Developer/Xcode/visionOS DeviceSupport/*",
        "~/Library/Developer/Xcode/macOS DeviceSupport/*",
      ],
      split: .each, titleStyle: .child, owner: xcode_, idleDays: 14
    ),
    LocationRule(
      id: "xcode.archives", category: .xcode, title: "Archive",
      detail: "A build you archived for release. Needed to symbolicate crashes from that version; nothing recreates it.",
      paths: ["~/Library/Developer/Xcode/Archives/*/*"], split: .each, titleStyle: .child,
      recovery: .permanent, risk: .caution, owner: xcode_, method: .trash, auto: .never
    ),
    LocationRule(
      id: "xcode.devicelogs", category: .xcode, title: "Device logs & test results",
      detail: "Logs pulled from devices and old test result bundles.",
      paths: ["~/Library/Developer/Xcode/iOS Device Logs", "~/Library/Developer/Xcode/UserData/IDEEditorInteractivityHistory"],
      owner: xcode_, minimumBytes: 1_000_000
    ),
  ]

  // MARK: Simulators (devices are handled by SimulatorScanner)

  static let simulators: [LocationRule] = [
    LocationRule(
      id: "sim.caches", category: .simulators, title: "Simulator caches",
      detail: "Shared system caches for simulators. Rebuilt when a simulator next boots, which makes that boot slower.",
      paths: ["~/Library/Developer/CoreSimulator/Caches"], owner: simulator, blockWhileRunning: true,
      allowsLibrariesInside: true
    ),
  ]

  // MARK: Package caches

  static let packageCaches: [LocationRule] = [
    pkg("homebrew", "Homebrew downloads", ["~/Library/Caches/Homebrew"], "Installers Homebrew already unpacked. It downloads them again if you reinstall."),
    pkg("npm", "npm cache", ["~/.npm/_cacache", "~/.npm/_npx", "~/.npm/_logs"], "Packages npm has downloaded. It fetches them again on the next install."),
    pkg("pnpm", "pnpm store", ["~/Library/pnpm/store", "~/Library/Caches/pnpm", "~/.local/share/pnpm/store", "~/.pnpm-store"], "Packages pnpm has downloaded. Projects keep their own copies; new installs fetch again."),
    pkg("yarn", "Yarn cache", ["~/Library/Caches/Yarn", "~/.yarn/berry/cache", "~/.cache/yarn"], "Packages Yarn has downloaded. It fetches them again on the next install."),
    pkg("bun", "Bun cache", ["~/.bun/install/cache", "~/Library/Caches/bun"], "Packages Bun has downloaded. It fetches them again on the next install."),
    pkg("pip", "pip cache", ["~/Library/Caches/pip", "~/Library/Caches/pypoetry", "~/.cache/pip"], "Python packages already downloaded. pip fetches them again when needed."),
    pkg("uv", "uv cache", ["~/.cache/uv", "~/Library/Caches/uv"], "Python packages and builds uv has cached. It fetches them again when needed."),
    pkg("conda", "Conda packages", ["~/miniconda3/pkgs", "~/anaconda3/pkgs", "~/.conda/pkgs", "~/miniforge3/pkgs", "~/mambaforge/pkgs"], "Downloaded Conda packages. Environments keep working; new ones download again."),
    pkg("cargo", "Cargo registry", ["~/.cargo/registry/cache", "~/.cargo/registry/src", "~/.cargo/git/checkouts", "~/.cargo/git/db"], "Rust crates Cargo has downloaded. It fetches them again on the next build."),
    pkg("go", "Go modules", ["~/go/pkg/mod", "~/go/pkg/sumdb"], "Go modules already downloaded. Go fetches them again on the next build."),
    pkg("gobuild", "Go build cache", ["~/Library/Caches/go-build"], "Compiled Go packages. Rebuilt on the next build.", recovery: .automatic),
    pkg("cocoapods", "CocoaPods cache", ["~/Library/Caches/CocoaPods", "~/.cocoapods/repos"], "Pods and spec repos CocoaPods has downloaded. It fetches them again on the next install."),
    pkg("swiftpm", "Swift packages cache", ["~/Library/Caches/org.swift.swiftpm", "~/Library/Caches/org.carthage.CarthageKit"], "Swift packages already downloaded. Xcode fetches them again when it resolves packages."),
    pkg("gradle", "Gradle cache", ["~/.gradle/caches", "~/.gradle/wrapper/dists", "~/.gradle/daemon", "~/.gradle/native", "~/.gradle/.tmp"], "Dependencies and Gradle versions already downloaded. Gradle fetches them again on the next build."),
    pkg("maven", "Maven repository", ["~/.m2/repository"], "Java libraries Maven has downloaded. It fetches them again on the next build."),
    pkg("composer", "Composer cache", ["~/Library/Caches/composer", "~/.composer/cache"], "PHP packages already downloaded. Composer fetches them again when needed."),
    pkg("pub", "Dart & Flutter packages", ["~/.pub-cache"], "Dart packages already downloaded. `pub get` fetches them again."),
    pkg("playwright", "Test browsers", ["~/Library/Caches/ms-playwright", "~/Library/Caches/ms-playwright-go", "~/.cache/puppeteer", "~/Library/Caches/Cypress", "~/.cache/selenium"], "Browsers downloaded for automated testing. The test tool downloads them again when it next runs."),
    pkg("electron", "Electron & native build caches", ["~/Library/Caches/electron", "~/.cache/electron", "~/.cache/electron-builder", "~/Library/Caches/node-gyp", "~/.cache/node-gyp", "~/.node-gyp", "~/Library/Caches/typescript", "~/.cache/prisma", "~/.cache/pre-commit", "~/.cache/turbo"], "Build tools and headers downloaded for Node projects. Fetched again when a build needs them."),
    pkg("deno", "Deno cache", ["~/Library/Caches/deno", "~/.deno/npm", "~/.cache/deno"], "Modules Deno has downloaded. It fetches them again when needed."),
    pkg("nuget", ".NET packages", ["~/.nuget/packages", "~/.nuget/v3-cache", "~/.local/share/NuGet/http-cache"], "Packages NuGet has downloaded. It fetches them again on the next restore."),
    LocationRule(
      id: "pkg.agent-runtimes", category: .packageCaches, title: "Agent tool runtimes",
      detail: "Runtimes an agent downloaded to run tools. It downloads them again when needed.",
      paths: ["~/.cache/codex-runtimes"], recovery: .redownload,
      owner: Owner("Codex", bundleIDs: ["com.openai.codex"], processNames: ["codex"]), blockWhileRunning: true
    ),
    pkg("nvm", "Node version manager cache", ["~/.nvm/.cache", "~/.fnm/node-versions/.downloads", "~/.volta/cache", "~/.cache/node/corepack", "~/.rustup/downloads", "~/.rustup/tmp"], "Installer downloads kept by version managers. Fetched again if you reinstall."),
  ]

  // MARK: Developer tool caches

  static let developerCaches: [LocationRule] = [
    LocationRule(
      id: "dev.jetbrains", category: .developerCaches, title: "JetBrains caches",
      detail: "Indexes and caches for JetBrains IDEs. Rebuilt when you reopen a project, which takes a few minutes.",
      paths: ["~/Library/Caches/JetBrains/*"], split: .each, titleStyle: .child
    ),
    LocationRule(
      id: "dev.vscode-caches", category: .developerCaches, title: "Editor caches",
      detail: "Compiled code and extension downloads cached by VS Code and editors built on it. Recreated on launch.",
      paths: [
        "~/Library/Application Support/Code/CachedExtensionVSIXs", "~/Library/Application Support/Code/CachedProfilesData",
        "~/Library/Application Support/Cursor/CachedExtensionVSIXs", "~/Library/Application Support/Cursor/CachedProfilesData",
        "~/Library/Application Support/Windsurf/CachedExtensionVSIXs", "~/Library/Application Support/Code - Insiders/CachedExtensionVSIXs",
        "~/Library/Application Support/Zed/node", "~/Library/Application Support/Zed/languages",
        "~/Library/Caches/Zed", "~/Library/Application Support/Zed/copilot",
      ]
    ),
    LocationRule(
      id: "dev.docker-desktop", category: .emulators, title: "Docker disk image",
      detail: "Docker's virtual disk: images, containers and volumes together.",
      paths: [
        "~/Library/Containers/com.docker.docker/Data/vms", "~/Library/Group Containers/HUAQ24HBR6.dev.orbstack/data",
        "~/.orbstack/data", "~/.colima", "~/.lima", "~/.local/share/containers", "~/Library/Application Support/rancher-desktop/lima",
      ],
      recovery: .redownload, risk: .caution, owner: docker, minimumBytes: 100_000_000,
      reportOnly: "Use the tool's own clean-up (for Docker: `docker system prune`), which knows what's still in use."
    ),
    LocationRule(
      id: "dev.terraform", category: .developerCaches, title: "Infrastructure tool caches",
      detail: "Provider plugins and build caches for infrastructure and build tools. Downloaded again when needed.",
      paths: ["~/.terraform.d/plugin-cache", "~/.cache/bazel", "~/.cache/ccache", "~/Library/Caches/ccache", "~/.cache/sccache", "~/Library/Caches/Mozilla.sccache", "~/.cache/zig", "~/.cache/clangd", "~/.cache/swiftly"],
      recovery: .redownload
    ),
  ]

  // MARK: Toolkits & SDKs

  static let toolkits: [LocationRule] = [
    sdk("node", "Node.js", ["~/.nvm/versions/node/*", "~/.fnm/node-versions/*", "~/.volta/tools/image/node/*", "~/.local/share/fnm/node-versions/*"]),
    sdk("rust", "Rust toolchain", ["~/.rustup/toolchains/*"]),
    sdk("python", "Python", ["~/.pyenv/versions/*", "~/.local/share/uv/python/*"]),
    sdk("ruby", "Ruby", ["~/.rbenv/versions/*", "~/.rvm/rubies/*"]),
    sdk("swift", "Swift toolchain", ["~/Library/Developer/Toolchains/*", "~/.swiftly/toolchains/*"]),
    sdk("android-images", "Android system image", ["~/Library/Android/sdk/system-images/*/*"]),
    sdk("android-ndk", "Android NDK", ["~/Library/Android/sdk/ndk/*"]),
    sdk("android-tools", "Android build tools", ["~/Library/Android/sdk/build-tools/*", "~/Library/Android/sdk/platforms/*"]),
    sdk("flutter", "Flutter SDK cache", ["~/flutter/bin/cache", "~/fvm/versions/*", "~/.fvm/versions/*"]),
    sdk("java", "Java runtime", ["~/Library/Java/JavaVirtualMachines/*", "~/.sdkman/candidates/*/*", "~/.jdks/*"]),
  ]

  // MARK: Emulators

  static let emulators: [LocationRule] = [
    LocationRule(
      id: "emu.claude-vm", category: .emulators, title: "Claude desktop virtual machine",
      detail: "The Linux environment Claude's desktop app uses for agent tasks. Claude downloads it again when that feature is next used; anything saved only inside it is lost.",
      paths: ["~/Library/Application Support/Claude/vm_bundles/*"], recovery: .redownload, risk: .caution,
      owner: Owner("Claude", bundleIDs: ["com.anthropic.claudefordesktop"]), blockWhileRunning: true,
      method: .trash, used: .accessed, auto: .never, minimumBytes: 100_000_000
    ),
    LocationRule(
      id: "emu.codex-sideload", category: .buildOutputs, title: "Codex sideload builds",
      detail: "App builds Codex prepared for installing on your devices. They're rebuilt the next time you sideload that app.",
      paths: ["~/Library/Application Support/Codex/RemoteSideload/artifacts/*"], recovery: .reinstall, risk: .caution,
      olderThanDays: 14, auto: .at(.balanced), minimumBytes: 20_000_000
    ),
    LocationRule(
      id: "emu.android", category: .emulators, title: "Android emulator",
      detail: "A virtual Android device with its apps and data. You'd have to create and set it up again.",
      paths: ["~/.android/avd/*.avd"], split: .each, titleStyle: .child, recovery: .reinstall,
      risk: .caution, method: .trash, used: .accessed, idleDays: 60
    ),
    LocationRule(
      id: "emu.android-cache", category: .emulators, title: "Android emulator caches",
      detail: "Snapshots and caches the Android emulator recreates when a device boots.",
      paths: ["~/.android/cache", "~/.android/avd/*.avd/snapshots", "~/.android/avd/*.avd/cache.img"]
    ),
  ]

  // MARK: AI models

  static let models: [LocationRule] = [
    LocationRule(
      id: "ai.ollama", category: .aiModels, title: "Ollama models",
      detail: "Language models pulled with Ollama. `ollama pull` downloads them again.",
      paths: ["~/.ollama/models"], recovery: .redownload, risk: .caution, owner: ollama, used: .accessed, idleDays: 30
    ),
    LocationRule(
      id: "ai.huggingface", category: .aiModels, title: "Hugging Face model",
      detail: "A model or dataset downloaded from Hugging Face. Tools that use it download it again.",
      paths: ["~/.cache/huggingface/hub/models--*", "~/.cache/huggingface/hub/datasets--*", "~/.cache/huggingface/xet"],
      split: .each, titleStyle: .huggingFace, recovery: .redownload, risk: .caution, used: .accessed, idleDays: 30
    ),
    LocationRule(
      id: "ai.lmstudio", category: .aiModels, title: "LM Studio model",
      detail: "A model downloaded in LM Studio. You can download it again from the app.",
      paths: ["~/.lmstudio/models/*/*", "~/.cache/lm-studio/models/*/*"], split: .each, titleStyle: .child,
      recovery: .redownload, risk: .caution, used: .accessed, idleDays: 30
    ),
    LocationRule(
      id: "ai.whisper", category: .aiModels, title: "Speech models",
      detail: "Transcription models downloaded by MacWhisper and similar apps. The app downloads them again when you pick that model.",
      paths: [
        "~/Library/Application Support/MacWhisper/models/*", "~/Library/Application Support/MacWhisper/models-*",
        "~/Library/Containers/com.goodsnooze.MacWhisper/Data/Library/Application Support/MacWhisper/models/*",
        "~/Library/Group Containers/*MacWhisper*/models/*", "~/.cache/whisper", "~/.whisper-models/*",
        "~/Library/Application Support/superwhisper/models/*",
        "~/Library/Application Support/com.prakashjoshipax.VoiceInk/WhisperModels/*", "~/Library/Application Support/whisperkit",
        "~/Documents/huggingface/models/argmaxinc",
      ],
      split: .each, titleStyle: .child, recovery: .redownload, risk: .caution, used: .accessed, idleDays: 30
    ),
    LocationRule(
      id: "ai.other", category: .aiModels, title: "Other local models",
      detail: "Model weights kept by local AI tools. Each tool downloads its models again when asked.",
      paths: [
        "~/.cache/torch", "~/.cache/mlx", "~/.cache/modelscope", "~/Library/Application Support/nomic.ai/GPT4All",
        "~/Library/Application Support/Jan/data/models", "~/jan/models", "~/.diffusionbee",
        "~/Library/Application Support/DiffusionBee", "~/.cache/gpt4all", "~/.llama/checkpoints",
        "~/Library/Containers/com.liuliu.draw-things/Data/Documents/Models", "~/.cache/whisper.cpp",
        "~/Library/Application Support/Msty/models", "~/.aitk/models", "~/.foundry/cache/models",
      ],
      split: .each, titleStyle: .child, recovery: .redownload, risk: .caution, used: .accessed, idleDays: 30
    ),
  ]

  // MARK: Agents & editors (session transcripts are handled by AgentHistoryScanner)

  static let agents: [LocationRule] = [
    LocationRule(
      id: "agent.claude-scratch", category: .agentHistory, title: "Claude Code working files",
      detail: "Shell snapshots, debug logs, paste caches and to-do lists from finished sessions. Not needed once a session ends.",
      paths: [
        "~/.claude/shell-snapshots/*", "~/.claude/debug/*", "~/.claude/paste-cache/*", "~/.claude/todos/*",
        "~/.claude/statsig/*", "~/.claude/session-env/*", "~/.claude/telemetry/*", "~/.claude/image-cache/*",
        "~/.claude/cache/*", "~/.claude/logs/*", "~/.claude/ide/*", "~/.claude/tasks/*",
      ],
      risk: .caution, olderThanDays: staleAgentDays, auto: .at(.balanced), minimumBytes: 1_000_000
    ),
    LocationRule(
      id: "agent.claude-file-history", category: .agentHistory, title: "Claude Code file checkpoints",
      detail: "Copies of files Claude saved before editing them, used to rewind a session. Stale ones only matter if you'd rewind that old session.",
      paths: ["~/.claude/file-history/*"], recovery: .permanent, risk: .caution,
      olderThanDays: staleAgentDays, auto: .at(.balanced), minimumBytes: 1_000_000
    ),
    LocationRule(
      id: "agent.codex-scratch", category: .agentHistory, title: "Codex working files",
      detail: "Logs and temporary files from Codex runs.",
      // Not all of `~/.codex/.tmp`: despite the name it holds Codex's synced plugins,
      // its bundled marketplace, backups and lock files. Only scratch clones and
      // abandoned marketplace staging folders are taken from it.
      paths: [
        "~/.codex/log/*", "~/.codex/logs/*", "~/.codex/tmp/*", "~/.codex/shell_snapshots/*", "~/.codex/cache/*",
        "~/.codex/.tmp/git-*", "~/.codex/.tmp/bundled-marketplaces/*.staging-*", "~/.codex/.tmp/marketplaces/.staging/marketplace-*",
      ],
      risk: .caution, olderThanDays: staleAgentDays, auto: .at(.balanced), minimumBytes: 1_000_000
    ),
    LocationRule(
      id: "agent.gemini-scratch", category: .agentHistory, title: "Gemini CLI history",
      detail: "Conversation checkpoints and prompt history from Gemini CLI sessions. Stale ones only matter if you'd go back to that old session.",
      // `~/.gemini/antigravity` is left out: it holds Antigravity's knowledge, skills and conversations.
      paths: ["~/.gemini/tmp/*", "~/.gemini/history/*"],
      recovery: .permanent, risk: .caution, olderThanDays: staleAgentDays, auto: .at(.balanced), minimumBytes: 1_000_000
    ),
    LocationRule(
      id: "agent.editor-workspaces", category: .agentHistory, title: "workspace state",
      detail: "An editor's saved state for one folder: open tabs, chat history and local undo history. Stale ones belong to projects you haven't opened lately.",
      paths: [
        "~/Library/Application Support/Cursor/User/workspaceStorage/*", "~/Library/Application Support/Code/User/workspaceStorage/*",
        "~/Library/Application Support/Windsurf/User/workspaceStorage/*", "~/Library/Application Support/Code - Insiders/User/workspaceStorage/*",
        "~/Library/Application Support/VSCodium/User/workspaceStorage/*",
      ],
      recovery: .permanent, risk: .caution, olderThanDays: staleAgentDays, auto: .at(.balanced), minimumBytes: 1_000_000
    ),
    LocationRule(
      id: "agent.editor-history", category: .agentHistory, title: "Editor local history",
      detail: "Old versions of files your editor saved as you typed. Stale ones are only useful to recover a past edit.",
      paths: [
        "~/Library/Application Support/Cursor/User/History/*", "~/Library/Application Support/Code/User/History/*",
        "~/Library/Application Support/Windsurf/User/History/*", "~/Library/Application Support/Code - Insiders/User/History/*",
      ],
      recovery: .permanent, risk: .caution, olderThanDays: staleAgentDays, auto: .at(.balanced), minimumBytes: 1_000_000
    ),
  ]

  // MARK: Media downloads

  static let media: [LocationRule] = [
    LocationRule(
      id: "media.cleanshot", category: .largeFiles, title: "CleanShot capture history",
      detail: "Screenshots and recordings CleanShot keeps in its history, older than 30 days. Captures you saved or exported elsewhere are separate files and stay.",
      paths: ["~/Library/Application Support/CleanShot/media/*"], recovery: .permanent, risk: .personal,
      method: .trash, olderThanDays: 30, minimumBytes: 20_000_000
    ),
    LocationRule(
      id: "media.podcasts", category: .mediaDownloads, title: "Podcast downloads",
      detail: "Episodes downloaded by Podcasts. They stream or download again from the app.",
      paths: ["~/Library/Group Containers/243LU875E5.groups.com.apple.podcasts/Library/Cache"],
      recovery: .redownload, risk: .caution, owner: Owner("Podcasts", bundleIDs: ["com.apple.podcasts"]), blockWhileRunning: true
    ),
    LocationRule(
      id: "media.spotify", category: .mediaDownloads, title: "Spotify offline cache",
      detail: "Songs Spotify stored for quicker playback. It downloads them again as you listen.",
      paths: ["~/Library/Application Support/Spotify/PersistentCache", "~/Library/Caches/com.spotify.client"],
      recovery: .redownload, owner: spotify, blockWhileRunning: true
    ),
    LocationRule(
      id: "media.tv", category: .mediaDownloads, title: "Apple TV & Music caches",
      detail: "Artwork and streaming caches for TV and Music. Downloaded again as you browse.",
      paths: ["~/Library/Caches/com.apple.Music", "~/Library/Caches/com.apple.TV", "~/Library/Caches/com.apple.podcasts", "~/Library/Caches/com.apple.AMPArtworkAgent"],
      blockWhileRunning: false
    ),
  ]

  // MARK: Games

  static let games: [LocationRule] = [
    LocationRule(
      id: "games.steam", category: .games, title: "Steam game",
      detail: "An installed Steam game. Steam downloads it again from your library; cloud saves depend on the game.",
      paths: ["~/Library/Application Support/Steam/steamapps/common/*"], split: .each, titleStyle: .child,
      recovery: .redownload, risk: .caution, owner: steam, method: .trash, used: .accessed, auto: .never, minimumBytes: 50_000_000
    ),
    LocationRule(
      id: "games.steam-cache", category: .games, title: "Steam caches",
      detail: "Shader caches and download leftovers. Steam rebuilds them when a game next runs.",
      paths: [
        "~/Library/Application Support/Steam/steamapps/shadercache", "~/Library/Application Support/Steam/steamapps/downloading",
        "~/Library/Application Support/Steam/steamapps/temp", "~/Library/Application Support/Steam/appcache/httpcache",
      ],
      owner: steam, blockWhileRunning: true
    ),
    LocationRule(
      id: "games.bottles", category: .games, title: "Windows game bottle",
      detail: "A Windows environment with its games and saves, used by CrossOver or Whisky.",
      paths: ["~/Library/Application Support/CrossOver/Bottles/*", "~/Library/Containers/com.isaacmarovitz.Whisky/Bottles/*"],
      split: .each, titleStyle: .child, recovery: .permanent, risk: .personal, method: .trash, minimumBytes: 50_000_000
    ),
  ]

  // MARK: Device backups

  static let backups: [LocationRule] = [
    LocationRule(
      id: "backup.ios", category: .deviceBackups, title: "iPhone or iPad backup",
      detail: "A full backup of a device made through Finder. Nothing recreates it unless you back up again.",
      paths: ["~/Library/Application Support/MobileSync/Backup/*"], split: .each, titleStyle: .child,
      recovery: .permanent, risk: .personal, method: .trash, minimumBytes: 50_000_000
    ),
    LocationRule(
      id: "backup.ios-updates", category: .deviceBackups, title: "iPhone & iPad software updates",
      detail: "Downloaded iOS installers. Finder downloads them again if you update through the Mac.",
      paths: ["~/Library/iTunes/iPhone Software Updates", "~/Library/iTunes/iPad Software Updates", "~/Library/Group Containers/K36BKF7T3D.group.com.apple.configurator/Library/Caches/Firmware"],
      recovery: .redownload
    ),
  ]

  // MARK: Builders

  private static func pkg(_ id: String, _ title: String, _ paths: [String], _ detail: String, recovery: Recovery = .redownload) -> LocationRule {
    LocationRule(id: "pkg.\(id)", category: .packageCaches, title: title, detail: detail, paths: paths, recovery: recovery)
  }

  private static func sdk(_ id: String, _ title: String, _ paths: [String]) -> LocationRule {
    LocationRule(
      id: "sdk.\(id)", category: .sdks, title: title,
      detail: "An installed version of a developer toolkit. Reinstall it with the version manager that put it there.",
      paths: paths, split: .each, titleStyle: .child, recovery: .reinstall, risk: .caution,
      used: .accessed, auto: .at(.aggressive), idleDays: 90, minimumBytes: 50_000_000
    )
  }
}
