import GladeKit
import SwiftUI

/// Earlier conversations, in a column beside the one on screen: pinned ones first,
/// then by day. Choosing one opens it to read or carry on; each can be renamed,
/// pinned or deleted from its menu.
struct ConversationList: View {
  @Environment(AppModel.self) private var model
  @State private var search = ""
  @State private var renaming: UUID?
  @State private var newName = ""
  @State private var deleting: SavedConversation?
  @FocusState private var nameFocused: Bool

  var body: some View {
    let shown = filtered
    List(selection: selection) {
      ForEach(groups(shown), id: \.title) { group in
        Section(group.title) {
          ForEach(group.items) { conversation in
            row(conversation)
              .tag(conversation.id)
              .contextMenu { menu(conversation) }
          }
        }
      }
    }
    .listStyle(.sidebar)
    .scrollContentBackground(.hidden)
    .overlay {
      if model.savedConversations.isEmpty {
        Text("No conversations yet")
          .foregroundStyle(.secondary)
      } else if shown.isEmpty {
        ContentUnavailableView.search(text: search)
      }
    }
    .safeAreaInset(edge: .top, spacing: 0) {
      if model.savedConversations.count > 6 {
        TextField("Search", text: $search)
          .textFieldStyle(.roundedBorder)
          .padding(.horizontal, Metrics.m)
          .padding(.vertical, Metrics.s)
      }
    }
    .confirmationDialog(
      "Delete “\(deleting?.title ?? "")”?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
      titleVisibility: .visible, presenting: deleting
    ) { conversation in
      Button("Delete", role: .destructive) { model.deleteConversation(conversation.id) }
    }
  }

  /// The list’s selection is the conversation on screen; choosing another opens it.
  private var selection: Binding<UUID?> {
    Binding(
      get: { model.savedConversations.contains { $0.id == model.conversationID } ? model.conversationID : nil },
      set: { id in if let id { model.openConversation(id) } }
    )
  }

  @ViewBuilder
  private func row(_ conversation: SavedConversation) -> some View {
    if renaming == conversation.id {
      TextField("Name", text: $newName)
        .focused($nameFocused)
        .onSubmit { finishRenaming(conversation.id) }
        .onExitCommand { renaming = nil }
        .onChange(of: nameFocused) { _, focused in if !focused { finishRenaming(conversation.id) } }
    } else {
      HStack(spacing: Metrics.xs) {
        VStack(alignment: .leading, spacing: 1) {
          Text(conversation.title)
            .lineLimit(1)
          Text(caption(conversation))
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)
        }
        Spacer(minLength: 0)
        if conversation.pinned {
          Image(systemName: "pin.fill")
            .font(.caption2)
            .foregroundStyle(.tertiary)
            .accessibilityLabel("Pinned")
        }
      }
      .padding(.vertical, 2)
      .disabled(!model.canSwitchConversation && conversation.id != model.conversationID)
    }
  }

  @ViewBuilder
  private func menu(_ conversation: SavedConversation) -> some View {
    Button(conversation.pinned ? "Unpin" : "Pin", systemImage: conversation.pinned ? "pin.slash" : "pin") {
      model.setPinned(conversation.id, !conversation.pinned)
    }
    Button("Rename…", systemImage: "pencil") {
      newName = conversation.name ?? conversation.title
      renaming = conversation.id
      nameFocused = true
    }
    Divider()
    Button("Delete…", systemImage: "trash", role: .destructive) { deleting = conversation }
  }

  private func finishRenaming(_ id: UUID) {
    guard renaming == id else { return }
    model.renameConversation(id, to: newName)
    renaming = nil
  }

  /// "2:14 PM · Claude Code", or the day for older ones.
  private func caption(_ conversation: SavedConversation) -> String {
    let date = conversation.updated
    let when = Calendar.current.isDateInToday(date)
      ? date.formatted(date: .omitted, time: .shortened)
      : date.formatted(.dateTime.day().month(.abbreviated))
    let who = conversation.turns.last { $0.role == .assistant }.map { model.responderName($0.provider) }
    return [when, who].compactMap { $0 }.joined(separator: " · ")
  }

  private var filtered: [SavedConversation] {
    let query = search.trimmingCharacters(in: .whitespaces)
    guard !query.isEmpty else { return model.savedConversations }
    return model.savedConversations.filter { conversation in
      conversation.title.localizedCaseInsensitiveContains(query)
        || conversation.turns.contains { $0.text.localizedCaseInsensitiveContains(query) }
    }
  }

  /// Pinned, Today, Yesterday, Previous 7 Days, then Older.
  private func groups(_ conversations: [SavedConversation]) -> [(title: String, items: [SavedConversation])] {
    let calendar = Calendar.current
    let weekAgo = calendar.date(byAdding: .day, value: -7, to: calendar.startOfDay(for: Date())) ?? .distantPast
    func group(_ conversation: SavedConversation) -> String {
      if conversation.pinned { return "Pinned" }
      if calendar.isDateInToday(conversation.updated) { return "Today" }
      if calendar.isDateInYesterday(conversation.updated) { return "Yesterday" }
      return conversation.updated >= weekAgo ? "Previous 7 Days" : "Older"
    }
    let order = ["Pinned", "Today", "Yesterday", "Previous 7 Days", "Older"]
    let grouped = Dictionary(grouping: conversations, by: group)
    return order.compactMap { title in grouped[title].map { (title, $0) } }
  }
}
