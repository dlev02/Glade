import GladeKit
import SwiftUI

/// The turns of the conversation, newest at the bottom, scrolling new ones into view.
struct ConversationView: View {
  var messages: [AppModel.Message]
  var state: AppModel.AssistantState
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  /// The widest the conversation column gets.
  static let columnWidth: CGFloat = 720
  private static let thinkingID = "thinking"

  var body: some View {
    // Only the newest piece of advice describes the plan as it is now.
    let currentAdvice = messages.last { $0.advice != nil }?.id
    ScrollViewReader { proxy in
      ScrollView {
        LazyVStack(alignment: .leading, spacing: Metrics.xl) {
          ForEach(messages) { message in
            MessageRow(message: message, isCurrentAdvice: message.id == currentAdvice)
              .id(message.id.uuidString)
          }
          if case .thinking(let label) = state {
            ThinkingRow(label: label)
              .id(Self.thinkingID)
          }
        }
        .padding(.horizontal, Metrics.xl)
        .padding(.top, Metrics.xl)
        .padding(.bottom, Metrics.l)
        .frame(maxWidth: Self.columnWidth)
        .frame(maxWidth: .infinity)
      }
      .defaultScrollAnchor(.bottom)
      .onChange(of: messages.count) { scrollToEnd(proxy) }
      .onChange(of: state) { scrollToEnd(proxy) }
    }
  }

  private func scrollToEnd(_ proxy: ScrollViewProxy) {
    let target: String? = if case .thinking = state { Self.thinkingID } else { messages.last?.id.uuidString }
    guard let target else { return }
    withAnimation(reduceMotion ? nil : .smooth) {
      proxy.scrollTo(target, anchor: .bottom)
    }
  }
}

/// The assistant at work, in the place its answer will appear.
private struct ThinkingRow: View {
  var label: String

  var body: some View {
    HStack(spacing: Metrics.s) {
      ProgressView()
        .controlSize(.small)
      Text(label)
        .foregroundStyle(.secondary)
    }
    .accessibilityElement(children: .combine)
  }
}
