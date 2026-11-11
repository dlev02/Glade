import GladeKit
import SwiftUI

/// Small symbols after an app’s name for what Activity Monitor doesn’t tell you: it’s
/// playing sound, using the microphone, keeping the Mac awake, or kept
/// running on purpose. Each explains itself on hover and to VoiceOver.
struct StatusMarks: View {
  var app: AppUsage
  var keepsRunning: Bool

  var body: some View {
    HStack(spacing: 3) {
      if app.isPlayingAudio {
        mark("speaker.wave.2.fill", "Playing audio")
      }
      if app.isCapturingAudio {
        mark("microphone.fill", "Using the microphone", color: .orange)
      }
      if let reason = app.preventingSleep {
        mark("cup.and.saucer.fill", "Keeping the Mac awake: \(reason)")
      }
      if keepsRunning {
        mark("pin.fill", "Kept running: never suggested for quitting")
      }
    }
  }

  /// Every mark sits in the same square at the same weight, so a row of them lines up
  /// whatever the symbols' own proportions.
  private func mark(_ symbol: String, _ detail: String, color: Color? = nil) -> some View {
    Image(systemName: symbol)
      .font(.system(size: 10, weight: .medium))
      .imageScale(.medium)
      .foregroundStyle(color.map { AnyShapeStyle($0) } ?? AnyShapeStyle(.secondary))
      .frame(width: 14, height: 14)
      .help(detail)
      .accessibilityLabel(detail)
  }
}
