import GladeKit
import SwiftUI

/// The battery and what is using it: the charge and its history, health, power and
/// heat, the apps using the most energy, what keeps the Mac awake, and how it slept.
/// On a Mac without a battery it’s "Energy" and shows only the parts that apply.
struct BatteryScreen: View {
  @Environment(AppModel.self) private var model
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var range: ChargeRange = .day
  @State private var period: EnergyPeriod
  @State private var notice: String?
  @State private var noticeTask: Task<Void, Never>?
  @State private var width: CGFloat = 0
  @State private var now = Date()
  /// For snapshots: shows Technical whatever the setting says.
  private let detailOverride: BatterySettings.Detail?

  init(range: ChargeRange = .day, period: EnergyPeriod = .now, detail: BatterySettings.Detail? = nil) {
    _range = State(initialValue: range)
    _period = State(initialValue: period)
    detailOverride = detail
  }

  private var detail: BatterySettings.Detail { detailOverride ?? model.config.battery.detail }

  var body: some View {
    let battery = model.battery
    let hasBattery = battery.status?.reading.hasBattery ?? BatteryReader.hasBattery
    ScrollView {
      VStack(alignment: .leading, spacing: Metrics.xl) {
        if hasBattery {
          VStack(alignment: .leading, spacing: Metrics.l) {
            ChargeCard(
              status: battery.status, history: battery.history, sleeps: battery.sleeps, detail: detail,
              range: $range, now: now
            )
            BatteryPanels(
              status: battery.status, history: battery.history, thermal: model.snapshot?.thermal, detail: detail,
              columns: width > 0 && width < 700 ? 2 : 3, now: now
            )
          }
        }
        if !battery.suggestions.isEmpty { suggestions(battery.suggestions) }
        energy
        if width >= 820 {
          HStack(alignment: .top, spacing: Metrics.l) {
            awake
            sleeps(battery)
          }
        } else {
          awake
          sleeps(battery)
        }
      }
      .frame(maxWidth: Metrics.contentWidth, alignment: .leading)
      .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
      .padding(Metrics.xl)
      .frame(maxWidth: .infinity)
    }
    .navigationTitle(model.batteryTitle)
    .navigationSubtitle(hasBattery ? (battery.status?.sentence ?? "") : "")
    .overlay(alignment: .bottom) {
      if let notice {
        Text(notice)
          .font(.callout)
          .multilineTextAlignment(.center)
          .padding(.horizontal, Metrics.l)
          .padding(.vertical, Metrics.s)
          .glassEffect(.regular, in: .capsule)
          .padding(Metrics.m)
          .transition(.opacity.combined(with: .move(edge: .bottom)))
      }
    }
    .task {
      while !Task.isCancelled {
        try? await Task.sleep(for: .seconds(30))
        now = .now
      }
    }
    .onChange(of: battery.status?.reading.date) { now = .now }
    .onAppear { model.batteryAppeared() }
    .onDisappear {
      model.batteryDisappeared()
      noticeTask?.cancel()
    }
  }

  // MARK: Sections

  private func suggestions(_ list: [PerformanceSuggestion]) -> some View {
    VStack(alignment: .leading, spacing: Metrics.s) {
      SectionTitle("Suggestions")
      Card(padding: 0) {
        VStack(spacing: 0) {
          ForEach(Array(list.prefix(3).enumerated()), id: \.element.id) { index, suggestion in
            VStack(spacing: 0) {
              if index > 0 { Divider().padding(.leading, 52).padding(.trailing, Metrics.l) }
              SuggestionRow(suggestion, iconSize: 24, report: show)
                .padding(.horizontal, Metrics.l)
                .padding(.vertical, Metrics.s)
            }
            .suggestionTransition(reduceMotion: reduceMotion)
          }
        }
      }
      .animation(reduceMotion ? nil : .smooth(duration: 0.3), value: list.map(\.id))
    }
  }

  private var energy: some View {
    let report = model.energyReport(period)
    let onBattery = model.battery.status?.reading.state == .onBattery
    return VStack(alignment: .leading, spacing: Metrics.s) {
      HStack(alignment: .firstTextBaseline) {
        SectionTitle("Using the most power")
        Spacer(minLength: Metrics.s)
        Picker("Period", selection: $period) {
          ForEach(EnergyPeriod.allCases.filter { $0 != .unplugged || model.battery.status?.reading.hasBattery ?? BatteryReader.hasBattery }) { option in
            Text(option.title).tag(option)
              .selectionDisabled(option == .unplugged && !onBattery)
          }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .fixedSize()
        .accessibilityLabel("Period")
      }
      EnergyTable(report: report, detail: detail, announce: show)
      if let note = report.note, !report.apps.isEmpty || detail == .technical {
        Text(note)
          .font(.caption)
          .foregroundStyle(.secondary)
      } else if detail == .technical, let system = model.battery.status?.reading.systemWatts, report.totalWatts > 0 {
        Text("Apps: \(BatteryFormat.watts(report.totalWatts)) of the \(BatteryFormat.watts(system)) the Mac is using. The rest is the screen, graphics and radios.")
          .font(.caption)
          .foregroundStyle(.secondary)
      }
    }
    .onChange(of: onBattery) { if !onBattery && period == .unplugged { period = .hour } }
  }

  private var awake: some View {
    VStack(alignment: .leading, spacing: Metrics.s) {
      SectionTitle("Keeping your Mac awake")
      AwakeList(report: model.battery.awake, detail: detail, now: now, announce: show)
    }
    .frame(maxWidth: .infinity, alignment: .topLeading)
  }

  private func sleeps(_ battery: BatteryState) -> some View {
    VStack(alignment: .leading, spacing: Metrics.s) {
      SectionTitle("While it slept")
      SleepList(
        sleeps: battery.sleeps, loaded: battery.sleepsLoaded, sleepDisabled: battery.awake?.sleepDisabled ?? false,
        detail: detail
      )
    }
    .frame(maxWidth: .infinity, alignment: .topLeading)
  }

  /// Shows what an action did for a few seconds, then lets it go.
  private func show(_ message: String) {
    noticeTask?.cancel()
    withAnimation(reduceMotion ? nil : .smooth) { notice = message }
    AccessibilityNotification.Announcement(message).post()
    noticeTask = Task {
      try? await Task.sleep(for: .seconds(5))
      guard !Task.isCancelled else { return }
      withAnimation(reduceMotion ? nil : .smooth) { notice = nil }
    }
  }
}
