import AppKit
import GladeKit
import SwiftUI

/// First-run setup on one page: each step shows whether it's done and offers the one
/// thing that does it. Nothing is required, so Done always works.
struct SetupView: View {
  @Environment(AppModel.self) private var model
  @Environment(\.screenOverrides) private var overrides
  @State private var commandLine: CommandLineTool.Status?
  @State private var opensAtLogin = LoginItem.isEnabled
  @State private var checkingProviders = false
  @State private var askedForNotifications = false
  @State private var installing = false
  @State private var problem: String?
  /// Open at login is switched on once, the first time setup appears.
  @AppStorage("setupTurnedOnLoginItem") private var turnedOnLoginItem = false

  var body: some View {
    let status = currentStatus
    VStack(alignment: .leading, spacing: Metrics.l) {
      HStack(spacing: Metrics.m) {
        Image(nsImage: NSApp.applicationIconImage)
          .resizable()
          .frame(width: 48, height: 48)
          .accessibilityHidden(true)
        Text("Set Up \(Brand.name)")
          .font(.title2.bold())
      }

      Card(padding: 0) {
        VStack(spacing: 0) {
          fullDiskAccessStep(status)
          Divider().padding(.leading, 52)
          notificationsStep(status)
          Divider().padding(.leading, 52)
          assistantStep(status)
          Divider().padding(.leading, 52)
          loginStep(status)
          Divider().padding(.leading, 52)
          commandLineStep(status)
        }
      }

      if let problem {
        Text(problem)
          .font(.callout)
          .foregroundStyle(.secondary)
      }

      Spacer(minLength: 0)

      HStack {
        Text("You can come back here from Help › Set Up \(Brand.name)…")
          .font(.callout)
          .foregroundStyle(.secondary)
        Spacer()
        Button("Done") { model.finishSetup() }
          .keyboardShortcut(.defaultAction)
          .controlSize(.large)
      }
    }
    .padding(Metrics.xl)
    .frame(width: 560, height: 560)
    .animation(.smooth, value: status.fullDiskAccess)
    .animation(.smooth, value: status.notifications)
    .onAppear(perform: turnOnLoginOnce)
    .task { await load() }
    .task(id: status.fullDiskAccess) { await watchFullDiskAccess(done: status.fullDiskAccess) }
  }

  // MARK: Steps

  private func fullDiskAccessStep(_ status: SetupStatus) -> some View {
    SetupStepRow(
      title: "Full Disk Access",
      detail: "So \(Brand.name) can measure the Trash and app data.",
      note: status.fullDiskAccess ? nil : "Already on in System Settings? Quit and reopen \(Brand.name).",
      done: status.fullDiskAccess
    ) {
      if !status.fullDiskAccess {
        Button("Open Settings") { model.openFullDiskAccessSettings() }
      }
    }
  }

  private func notificationsStep(_ status: SetupStatus) -> some View {
    SetupStepRow(
      title: "Notifications",
      detail: "For alerts when space runs low or the Mac is struggling.",
      done: status.notifications
    ) {
      if !status.notifications {
        if askedForNotifications {
          Button("Open Settings") {
            if let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension") {
              NSWorkspace.shared.open(url)
            }
          }
        } else {
          Button("Allow") {
            Task {
              await model.requestNotifications()
              askedForNotifications = true
            }
          }
        }
      }
    }
  }

  private func assistantStep(_ status: SetupStatus) -> some View {
    let ready = status.providers.filter(\.isReady)
    return SetupStepRow(
      title: "Connect an AI",
      detail: Self.assistantDetail(providers: status.providers),
      done: !ready.isEmpty
    ) {
      if checkingProviders {
        ProgressView().controlSize(.small)
      } else {
        Button("Check Again") {
          checkingProviders = true
          Task {
            await model.refreshProviders()
            checkingProviders = false
          }
        }
      }
    }
  }

  private func loginStep(_ status: SetupStatus) -> some View {
    SetupStepRow(
      title: "Open at Login",
      detail: "Keeps \(Brand.name) in the menu bar.",
      note: LoginItem.isAvailable || overrides.setup != nil ? nil : "Available in the installed app.",
      done: status.opensAtLogin
    ) {
      Toggle("Open at Login", isOn: Binding(get: { status.opensAtLogin }, set: setOpensAtLogin))
        .toggleStyle(.switch)
        .labelsHidden()
        .disabled(!LoginItem.isAvailable && overrides.setup == nil)
    }
  }

  private func commandLineStep(_ status: SetupStatus) -> some View {
    let detail = switch status.commandLine {
    case .installed(let path, _): "Installed at \(Redactor.tilde(path))."
    case .unavailable: "Available after installing the app."
    default: "Optional. Use \(Brand.cli) in Terminal and connect coding agents."
    }
    return SetupStepRow(title: "Command Line", detail: detail, done: status.commandLine.isInstalled) {
      if installing {
        ProgressView().controlSize(.small)
      } else if case .notInstalled = status.commandLine {
        Button("Install", action: installCommandLine)
      } else if case .otherCopy = status.commandLine {
        Button("Update", action: installCommandLine)
      }
    }
  }

  // MARK: State

  private var currentStatus: SetupStatus {
    overrides.setup ?? SetupStatus(
      fullDiskAccess: model.hasFullDiskAccess, notifications: model.notificationsAllowed,
      providers: model.providers, opensAtLogin: opensAtLogin, commandLine: commandLine ?? .notInstalled
    )
  }

  /// "Claude Code and Apple Intelligence are ready.", or what to do when none is.
  static func assistantDetail(providers: [ProviderStatus]) -> String {
    let ready = providers.filter(\.isReady).map(\.name)
    if !ready.isEmpty {
      return "\(ready.formatted(.list(type: .and))) \(ready.count == 1 ? "is" : "are") ready."
    }
    for provider in providers {
      if case .needsSignIn(let hint) = provider.state {
        return "Sign in to \(provider.name): \(hint.replacingOccurrences(of: "`", with: ""))"
      }
    }
    return "Install Claude Code or Codex, or turn on Apple Intelligence in System Settings."
  }

  private func load() async {
    guard overrides.setup == nil else { return }
    await model.refreshPermissions()
    commandLine = await CommandLineTool.status()
  }

  /// Checks every couple of seconds until access is granted or the sheet closes; the
  /// grant happens in System Settings, which tells no one.
  private func watchFullDiskAccess(done: Bool) async {
    guard overrides.setup == nil, !done else { return }
    while !Task.isCancelled, !model.hasFullDiskAccess {
      try? await Task.sleep(for: .seconds(2))
      guard !Task.isCancelled else { return }
      await model.refreshPermissions()
    }
  }

  /// A menu bar app is most useful when it's always there, so setup switches this on
  /// the first time it appears. The person can switch it straight back off.
  private func turnOnLoginOnce() {
    guard overrides.setup == nil, LoginItem.isAvailable, !turnedOnLoginItem else { return }
    turnedOnLoginItem = true
    if !LoginItem.isEnabled { setOpensAtLogin(true) }
  }

  private func setOpensAtLogin(_ enabled: Bool) {
    do {
      try LoginItem.set(enabled)
      problem = LoginItem.needsApproval ? "Allow \(Brand.name) in System Settings › General › Login Items." : nil
    } catch {
      problem = "Couldn’t change Open at Login: \(error.localizedDescription)"
    }
    opensAtLogin = LoginItem.isEnabled
  }

  private func installCommandLine() {
    installing = true
    Task {
      do {
        try await CommandLineTool.install()
        problem = nil
      } catch {
        problem = error.localizedDescription
      }
      commandLine = await CommandLineTool.status()
      installing = false
    }
  }
}
