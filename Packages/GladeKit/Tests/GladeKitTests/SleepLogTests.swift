import Foundation
import Testing
@testable import GladeKit

/// `pmset -g log` is undocumented text whose wording shifts between macOS versions, so
/// a change there would silently empty "While it slept". The lines below are the
/// macOS 27 format, tab-separated, as `SleepLog` receives them after its `grep`.
struct SleepLogTests {
  static let log = [
    "2026-11-10 23:02:11 -0600 Sleep               \tEntering Sleep state due to 'Clamshell Sleep':TCPKeepAlive=active Using Batt (Charge:91%)\t3600 secs",
    "2026-11-11 01:14:40 -0600 DarkWake            \tDarkWake from Deep Idle [CDNP] : due to NUB.SPMI0Sw3IRQ nub-spmi0.0x02 rtc/Maintenance Using BATT (Charge:89%)\t6 secs",
    "2026-11-11 01:14:52 -0600 Sleep               \tEntering Sleep state due to 'Sleep Service Back to Sleep':TCPKeepAlive=active Using Batt (Charge:89%)\t",
    "2026-11-11 03:20:05 -0600 DarkWake            \tDarkWake from Deep Idle [CDNP] : due to smc.sysState.Wake(0x70070000) wifibt SMC.OutboxNotEmpty bluetooth-pcie/ Using BATT (Charge:87%)\t9 secs",
    "2026-11-11 04:01:00 -0600 DarkWake            \tDarkWake from Deep Idle [CDNP] : due to smc.sysState.Wake(0x70070000) wifibt SMC.OutboxNotEmpty bluetooth-pcie/ Using BATT (Charge:86%)\t4 secs",
    "2026-11-11 07:30:12 -0600 Wake                \tWake from Deep Idle [CDNVA] : due to smc.sysState.Wake(0x70070000) lid SMC.OutboxNotEmpty RTP.multi-touch/HID Activity Using BATT (Charge:84%)\t",
    "2026-11-11 12:00:00 -0600 Sleep               \tEntering Sleep state due to 'Idle Sleep':TCPKeepAlive=active Using AC (Charge:100%)\t60 secs",
    "2026-11-11 12:45:00 -0600 Start               \tpowerd process is started\t",
  ].joined(separator: "\n")

  @Test func sleepsAreGroupedWithTheirWakes() throws {
    let sleeps = SleepLog.parse(Self.log)
    try #require(sleeps.count == 2)

    // Newest first: the idle sleep that ended in a restart.
    let restart = sleeps[0]
    #expect(restart.reason == "Left idle")
    #expect(!restart.onBattery)
    #expect(restart.wokeBy == nil)
    #expect(restart.seconds == 45 * 60)

    let night = sleeps[1]
    #expect(night.reason == "Lid closed")
    #expect(night.onBattery)
    #expect(night.chargeBefore == 91)
    #expect(night.chargeAfter == 84)
    #expect(night.drain == 7)
    #expect(night.wokeBy == "the lid opening")
    // The "back to sleep" line continues the same sleep rather than starting another.
    #expect(night.wakes.count == 3)
    #expect(night.wakes.first?.reason == "a check-in by macOS")
    #expect(night.wakes.first?.seconds == 6)
    #expect(night.wakeCounts.first == .init(reason: "the network", count: 2))
    let start = try #require(ISO8601DateFormatter().date(from: "2026-11-11T05:02:11Z"))
    #expect(night.start == start)
    #expect(night.seconds == 8 * 3600 + 28 * 60 + 1)
  }
}
