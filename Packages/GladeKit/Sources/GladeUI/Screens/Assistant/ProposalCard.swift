import GladeKit
import SwiftUI

/// What an answer proposed removing: each item with its reason, the second opinion’s
/// note, and its tick, and one button that opens the usual confirmation with what is
/// ticked. Nothing is removed from the card itself. After the clean it says what went,
/// with Put Back; items a newer scan no longer has show as no longer available.
struct ProposalCard: View {
  @Environment(AppModel.self) private var model
  @Environment(\.accentMark) private var accentMark
  @Environment(\.reviewRemoval) private var reviewRemoval
  var message: UUID
  var state: ProposalState
  @State private var showsRefused = false

  /// The same side padding as the advice card: the ticks hang in it.
  private static let inset: CGFloat = Metrics.xxl

  var body: some View {
    Card(padding: 0) {
      VStack(alignment: .leading, spacing: Metrics.l) {
        if showsHeader { header }
        VStack(alignment: .leading, spacing: Metrics.m) {
          ForEach(state.proposal.items) { item in
            ProposalRow(item: item, message: message, state: state)
          }
        }
        footer
      }
      .padding(.horizontal, Self.inset)
      .padding(.vertical, Metrics.l)
    }
    // Its fill reaches outside the answer’s text edge, as the advice card’s does, so
    // the names start where the answer’s words do.
    .padding(.horizontal, -Self.inset)
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  /// Shown once anything can be ticked, or after a clean.
  private var showsHeader: Bool {
    state.outcome != nil || state.proposal.items.contains { model.currentAction(of: $0) == .remove }
  }

  private var header: some View {
    let ticked = model.tickedItems(state)
    return HStack(alignment: .center, spacing: Metrics.m) {
      if let outcome = state.outcome, ticked.isEmpty {
        figure(
          caption: outcome.putBack ? "Put back" : outcome.trashedAll ? "Moved to the Trash" : "Removed",
          value: Format.bytes(outcome.bytes)
        )
        Spacer(minLength: Metrics.m)
        if !outcome.putBack, outcome.removed.values.contains(true) {
          Button("Put Back") { model.putBackRemoval(in: message) }
            .secondaryAction()
            .accessibilityIdentifier("proposal.putBack")
        }
      } else {
        figure(caption: "To remove", value: ticked.isEmpty ? nil : Format.bytes(ticked.reduce(0) { $0 + $1.bytes }))
        Spacer(minLength: Metrics.m)
        Button("Review and Remove…") { reviewRemoval(message) }
          .principalAction()
          .disabled(ticked.isEmpty || model.isCleaning)
          .accessibilityIdentifier("proposal.review")
      }
    }
  }

  private func figure(caption: String, value: String?) -> some View {
    VStack(alignment: .leading, spacing: 2) {
      Text(caption)
        .font(.callout)
        .foregroundStyle(.secondary)
      Text(value ?? "Nothing ticked")
        .font(.figure(24))
        .foregroundStyle(value == nil ? AnyShapeStyle(.tertiary) : AnyShapeStyle(accentMark))
        .contentTransition(.numericText())
    }
    .accessibilityElement(children: .combine)
  }

  private var footer: some View {
    let proposal = state.proposal
    return HStack(alignment: .firstTextBaseline, spacing: Metrics.l) {
      if let reviewer = proposal.reviewer {
        Label("Second opinion from \(model.responderName(reviewer, model: proposal.reviewerModel))", systemImage: "person.2")
      } else {
        Label("No second opinion was available", systemImage: "person.2.slash")
      }
      if !proposal.rejected.isEmpty {
        AdviceDisclosure(isExpanded: $showsRefused) {
          Text(proposal.rejected.count == 1 ? "1 suggestion refused" : "\(proposal.rejected.count) suggestions refused")
        } content: {
          VStack(alignment: .leading, spacing: Metrics.s) {
            ForEach(Array(proposal.rejected.enumerated()), id: \.offset) { _, note in
              VStack(alignment: .leading, spacing: 1) {
                // An identifier the assistant made up; show it exactly, as data.
                Text(verbatim: model.proposedFinding(note.id)?.title ?? note.id)
                  .foregroundStyle(.primary)
                  .lineLimit(1)
                  .truncationMode(.middle)
                Text(verbatim: note.why)
              }
              .accessibilityElement(children: .combine)
            }
          }
        }
      }
    }
    .font(.caption)
    .foregroundStyle(.secondary)
  }
}

/// One proposed item: its tick (or why it has none) hung in the card’s gutter, its
/// icon, name and the AI’s reason, a button when it’s removed another way, its size,
/// and the second opinion’s note under it.
private struct ProposalRow: View {
  @Environment(AppModel.self) private var model
  @Environment(\.accentMark) private var accentMark
  var item: RemovalProposal.Item
  var message: UUID
  var state: ProposalState

  private static let iconSize: CGFloat = 26
  private static let gutter: CGFloat = 16 + Metrics.s

  private enum Status: Equatable {
    case tickable
    case removed(trashed: Bool)
    case putBack
    case stayed(String)
    case gone
    case uninstaller
    case finder
    case quitFirst
    case locked(String)
  }

  var body: some View {
    let finding = model.proposedFinding(item.id)
    let status = status(finding)
    VStack(alignment: .leading, spacing: Metrics.s) {
      HStack(alignment: .center, spacing: Metrics.s) {
        leading(status)
          .frame(width: 16)
        icon
        VStack(alignment: .leading, spacing: 1) {
          Text(item.title)
            .font(.callout.weight(.medium))
            .lineLimit(1)
            .truncationMode(.middle)
          if let line = secondLine(status) {
            Text(line)
              .font(.callout)
              .foregroundStyle(isWarning(status) ? AnyShapeStyle(Palette.warning) : AnyShapeStyle(.secondary))
              .fixedSize(horizontal: false, vertical: true)
          }
        }
        .accessibilityElement(children: .combine)
        Spacer(minLength: Metrics.m)
        trailing(status, finding)
        Text(Format.bytes(item.bytes))
          .font(.callout)
          .foregroundStyle(.secondary)
          .monospacedDigit()
      }
      .padding(.leading, -Self.gutter)
      .opacity(status == .gone ? 0.55 : 1)
      if let review = item.review, !review.note.isEmpty, showsReview(status) {
        ReviewNote(review: review, reviewer: model.responderName(state.proposal.reviewer))
          .padding(.leading, Self.iconSize + Metrics.s)
      }
    }
  }

  private func status(_ finding: Finding?) -> Status {
    if let outcome = state.outcome {
      if let trashed = outcome.removed[item.id] { return outcome.putBack && trashed ? .putBack : .removed(trashed: trashed) }
      if let reason = outcome.stayed[item.id] { return .stayed(reason) }
    }
    guard let finding else { return .gone }
    switch model.currentAction(of: item) {
    case .openUninstaller: return .uninstaller
    case .showInFinder: return .finder
    case .quitFirst: return .quitFirst
    case .listOnly: return .locked(finding.blockers.first?.detail ?? "")
    case .remove: return .tickable
    case nil: return .gone
    }
  }

  @ViewBuilder
  private func leading(_ status: Status) -> some View {
    switch status {
    case .tickable:
      Toggle(item.title, isOn: Binding(
        get: { state.ticks.contains(item.id) },
        set: { model.setTicked($0, item: item.id, in: message) }
      ))
      .toggleStyle(CheckToggleStyle())
    case .removed(let trashed):
      glyph(trashed ? Symbols.trash : "bolt", label: trashed ? "Moved to the Trash" : "Removed")
    case .putBack:
      glyph(Symbols.putBack, label: "Put back")
    case .stayed(let reason):
      glyph("exclamationmark.triangle.fill", label: "Not removed: \(reason)", style: AnyShapeStyle(Palette.warning))
    case .gone:
      glyph("circle.dashed", label: "No longer available")
    case .uninstaller:
      glyph(Symbols.uninstaller, label: "Has its own uninstaller")
    case .finder:
      glyph("lock.fill", label: "Needs your password; remove it in Finder")
    case .quitFirst:
      glyph("lock.fill", label: "Open now")
    case .locked(let reason):
      glyph("lock.fill", label: "Can’t be removed: \(reason)")
    }
  }

  private func glyph(_ name: String, label: String, style: AnyShapeStyle = AnyShapeStyle(.secondary)) -> some View {
    Image(systemName: name)
      .foregroundStyle(style)
      .help(label)
      .accessibilityLabel(label)
  }

  @ViewBuilder private var icon: some View {
    if item.isApp {
      AppIconView(path: item.appPath, size: Self.iconSize)
    } else {
      Image(systemName: item.category.symbol)
        .font(.system(size: 13))
        .foregroundStyle(.secondary)
        .frame(width: Self.iconSize, height: Self.iconSize)
        .background(Palette.track, in: .rect(cornerRadius: Self.iconSize * 0.24))
        .accessibilityHidden(true)
    }
  }

  private func secondLine(_ status: Status) -> String? {
    switch status {
    case .removed(let trashed): trashed ? "Moved to the Trash" : "Removed"
    case .putBack: "Put back where it was"
    case .stayed(let reason): reason
    case .gone: "No longer available"
    case .quitFirst: "Open now. Quit it first."
    case .tickable, .uninstaller, .finder, .locked: item.why.isEmpty ? nil : item.why
    }
  }

  private func isWarning(_ status: Status) -> Bool {
    if case .stayed = status { return true }
    return false
  }

  /// The second opinion matters while the item can still go.
  private func showsReview(_ status: Status) -> Bool {
    switch status {
    case .removed, .putBack, .gone: false
    default: true
    }
  }

  @ViewBuilder
  private func trailing(_ status: Status, _ finding: Finding?) -> some View {
    switch status {
    case .uninstaller:
      if let finding, finding.app?.uninstaller != nil {
        Button("Open Uninstaller") { model.openUninstaller(finding) }
          .buttonStyle(.bordered)
          .controlSize(.small)
          .font(.callout)
          .help(finding.blockers.first { $0.kind == .ownUninstaller }?.detail ?? "")
          .accessibilityLabel("Open Uninstaller for \(item.title)")
      }
    case .finder:
      if let path = finding?.paths.first {
        Button("Show in Finder") { model.showInFinder(path) }
          .buttonStyle(.bordered)
          .controlSize(.small)
          .font(.callout)
          .help(finding?.blockers.first { $0.kind == .needsAdmin }?.detail ?? "")
          .accessibilityLabel("Show \(item.title) in Finder")
      }
    default:
      EmptyView()
    }
  }
}

/// The second opinion on one item. A caution stands out on a faint orange ground; an
/// ok with something to say is a quiet line.
private struct ReviewNote: View {
  var review: RemovalProposal.Review
  var reviewer: String

  var body: some View {
    let caution = review.verdict == .caution
    HStack(alignment: .firstTextBaseline, spacing: 6) {
      Image(systemName: caution ? "exclamationmark.triangle.fill" : "checkmark.circle")
        .font(.caption)
        .foregroundStyle(caution ? AnyShapeStyle(Palette.warning) : AnyShapeStyle(.secondary))
        .accessibilityHidden(true)
      Text(verbatim: review.note)
        .font(.callout)
        .foregroundStyle(caution ? .primary : .secondary)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    .padding(.horizontal, caution ? Metrics.s : 0)
    .padding(.vertical, caution ? 6 : 0)
    .background(caution ? Palette.warning.opacity(0.1) : .clear, in: .rect(cornerRadius: 8))
    .accessibilityElement(children: .combine)
    .accessibilityLabel("\(caution ? "Caution" : "Second opinion") from \(reviewer): \(review.note)")
  }
}

extension EnvironmentValues {
  /// Opens the confirmation for a proposal’s ticked items, given its message.
  @Entry var reviewRemoval: (UUID) -> Void = { _ in }
}
