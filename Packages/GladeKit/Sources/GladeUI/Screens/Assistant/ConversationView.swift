import GladeKit
import SwiftUI

/// The turns of the conversation in one reading column. A short conversation starts at
/// the top; new turns are followed only when the person is already at the bottom.
struct ConversationView: View {
  @Environment(AppModel.self) private var model
  var messages: [AppModel.Message]
  var state: AppModel.AssistantState
  /// The provider chosen in the composer, so answers from another one say who wrote them.
  var chosen: ProviderStatus?
  /// Whether a piece of advice still describes the selection.
  var isLive: (StorageAdvice) -> Bool
  /// Opens what was sent for an answer.
  var showWhatWasSent: (AppModel.Message) -> Void
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var isAtBottom = true

  /// The widest the reading column gets, shared with the composer.
  static let columnWidth: CGFloat = 700
  private static let thinkingID = "thinking"

  var body: some View {
    ScrollViewReader { proxy in
      ScrollView {
        LazyVStack(alignment: .leading, spacing: Metrics.xl) {
          ForEach(messages) { message in
            MessageRow(
              message: message,
              isLiveAdvice: message.advice.map(isLive) ?? false,
              showsProvider: model.answeredByOther(message.provider, chosen: chosen),
              showWhatWasSent: { showWhatWasSent(message) }
            )
            .id(message.id.uuidString)
            .transition(insertion)
          }
          if case .thinking(let label) = state {
            ThinkingRow(label: label)
              .id(Self.thinkingID)
              .transition(.opacity)
          }
        }
        .animation(reduceMotion ? .easeOut(duration: 0.12) : .easeOut(duration: 0.16), value: messages.count)
        .animation(.easeOut(duration: 0.16), value: state)
        .padding(.horizontal, Metrics.xl)
        .padding(.top, Metrics.xl)
        .padding(.bottom, Metrics.l)
        .frame(maxWidth: Self.columnWidth + Metrics.xl * 2)
        .frame(maxWidth: .infinity)
      }
      .defaultScrollAnchor(.top, for: .alignment)
      .defaultScrollAnchor(.bottom, for: .initialOffset)
      .onScrollGeometryChange(for: ScrollPosition.self) { geometry in
        ScrollPosition(
          offset: geometry.contentOffset.y,
          gap: geometry.contentSize.height - geometry.contentOffset.y - geometry.containerSize.height
            + geometry.contentInsets.bottom
        )
      } action: { old, new in
        // Only a scroll changes whether the person is following; content growing
        // underneath them doesn't.
        if old.offset != new.offset || new.gap <= 40 { isAtBottom = new.gap <= 40 }
      }
      .onChange(of: messages.count) {
        // The person just asked something: always show it.
        if messages.last?.role == .person || isAtBottom { scrollToEnd(proxy) }
      }
      .onChange(of: state) {
        if isAtBottom { scrollToEnd(proxy) }
      }
    }
  }

  /// New turns fade in and rise a few points, or only fade with Reduce Motion.
  private var insertion: AnyTransition {
    reduceMotion ? .opacity : .asymmetric(insertion: .opacity.combined(with: .offset(y: 4)), removal: .opacity)
  }

  private func scrollToEnd(_ proxy: ScrollViewProxy) {
    let target: String? = if case .thinking = state { Self.thinkingID } else { messages.last?.id.uuidString }
    guard let target else { return }
    withAnimation(reduceMotion ? nil : .smooth(duration: 0.3)) {
      proxy.scrollTo(target, anchor: .bottom)
    }
  }
}

/// Where the reading column sits, and how far its end is below the visible part.
private struct ScrollPosition: Equatable {
  var offset: CGFloat
  var gap: CGFloat
}

/// The assistant at work, in the place its answer will appear.
private struct ThinkingRow: View {
  var label: String
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.accentMark) private var accentMark

  var body: some View {
    HStack(spacing: Metrics.s) {
      if reduceMotion {
        ProgressView()
          .controlSize(.small)
      } else {
        Image(systemName: Symbols.assistant)
          .foregroundStyle(accentMark)
          .symbolEffect(.variableColor.iterative.dimInactiveLayers, options: .repeating)
          .accessibilityHidden(true)
      }
      Text(label)
        .foregroundStyle(.secondary)
    }
    .accessibilityElement(children: .combine)
  }
}
