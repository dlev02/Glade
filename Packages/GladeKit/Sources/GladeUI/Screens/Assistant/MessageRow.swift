import GladeKit
import SwiftUI

/// One turn: the person's words in a bubble on the right, the assistant's answer as
/// plain reading text on the left, or a quiet notice when something went wrong.
/// Everything a model wrote is shown verbatim: never as Markdown, never as a link.
struct MessageRow: View {
  @Environment(AppModel.self) private var model
  var message: AppModel.Message
  /// This message carries the newest advice, so its card can show the plan's size.
  var isCurrentAdvice: Bool

  /// A comfortable line length for reading.
  private static let readingWidth: CGFloat = 620

  var body: some View {
    switch message.role {
    case .person: person
    case .assistant: assistant
    case .problem: problem
    }
  }

  private var person: some View {
    HStack {
      Spacer(minLength: Metrics.xxl * 3)
      Text(verbatim: message.text)
        .textSelection(.enabled)
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(.tint.opacity(0.14), in: .rect(cornerRadius: 18))
    }
  }

  private var assistant: some View {
    VStack(alignment: .leading, spacing: Metrics.s) {
      Label(model.providerCaption(message.provider), systemImage: "sparkles")
        .font(.caption)
        .foregroundStyle(.secondary)
        .accessibilityLabel("\(model.providerCaption(message.provider)) answered")
      Text(verbatim: message.text)
        .lineSpacing(3)
        .textSelection(.enabled)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: Self.readingWidth, alignment: .leading)
      if let advice = message.advice {
        AdviceCard(advice: advice, isCurrent: isCurrentAdvice)
          .padding(.top, Metrics.xs)
      }
    }
  }

  private var problem: some View {
    Label {
      Text(verbatim: message.text)
        .textSelection(.enabled)
        .foregroundStyle(.secondary)
        .frame(maxWidth: Self.readingWidth, alignment: .leading)
    } icon: {
      Image(systemName: "exclamationmark.triangle")
        .foregroundStyle(Palette.warning)
        .accessibilityLabel("Problem")
    }
    .font(.callout)
  }
}
