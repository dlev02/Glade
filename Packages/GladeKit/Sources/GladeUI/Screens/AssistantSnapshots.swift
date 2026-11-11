import Foundation
import GladeKit
import SwiftUI

/// The assistant screens that can be drawn to an image with `glade snapshot <name>`.
/// Add an entry for each state worth checking: empty, busy, a sheet, an error.
enum AssistantSnapshots {
  static let all: [String: (AppModel) -> AnyView] = [
    "assistant": { _ in AnyView(NavigationStack { AssistantScreen() }) },
    "assistant-empty": { model in
      model.clearConversation()
      return AnyView(NavigationStack { AssistantScreen() })
    },
    "assistant-thinking": { model in
      let messages = model.messages + [AppModel.Message(role: .person, text: "What’s using my memory?")]
      return AnyView(NavigationStack {
        AssistantScreen(preview: AssistantPreview(messages: messages, state: .thinking("Thinking…")))
      })
    },
    "assistant-advice": { model in
      AnyView(NavigationStack {
        AssistantScreen(preview: AssistantPreview(messages: adviceConversation(model), adviceIsLive: true))
      })
    },
    "assistant-earlier": { model in
      // The same advice after a hand-made change: it no longer describes the selection.
      AnyView(NavigationStack {
        AssistantScreen(preview: AssistantPreview(messages: adviceConversation(model), adviceIsLive: false))
      })
    },
    "assistant-sent": { _ in AnyView(RunSheet(run: sampleRuns()[0])) },
    "assistant-details": { _ in AnyView(RunsInspector(runs: sampleRuns()) { _ in }.frame(width: 300)) },
    "assistant-problem": { model in
      let messages = model.messages + [
        AppModel.Message(role: .person, text: "Why is my Mac slow right now?"),
        AppModel.Message(role: .problem, text: "Claude Code didn’t answer within 180 seconds."),
      ]
      return AnyView(NavigationStack { AssistantScreen(preview: AssistantPreview(messages: messages)) })
    },
    "assistant-noai": { model in
      let providers = model.providers.map { status -> ProviderStatus in
        var copy = status
        if copy.state == .ready {
          copy.state = copy.isLocal ? .unavailable(reason: "Apple Intelligence is turned off in System Settings.") : .notInstalled
        }
        return copy
      }
      return AnyView(NavigationStack { AssistantScreen(preview: AssistantPreview(providers: providers)) })
    },
    "assistant-min": { model in
      model.section = .assistant
      return AnyView(RootView())
    },
    "history": { _ in AnyView(NavigationStack { HistoryScreen() }) },
    "history-selected": { model in
      AnyView(NavigationStack { HistoryScreen(selection: model.receipts.first?.id) })
    },
    "history-empty": { _ in AnyView(NavigationStack { HistoryScreen(previewReceipts: []) }) },
    "history-min": { model in
      model.section = .history
      return AnyView(RootView())
    },
  ]

  /// The sample conversation, then a request to free space answered with advice that
  /// adds, leaves alone, flags and refuses, as a real run would.
  private static func adviceConversation(_ model: AppModel) -> [AppModel.Message] {
    func id(_ title: String) -> String { model.scan?.findings.first { $0.title == title }?.id ?? title }
    let note = { (title: String, why: String) in ["id": id(title), "why": why] }
    let json: [String: Any] = [
      "summary": "I’d add the Lantern build data and the iOS 18 simulator system, which nothing uses, and leave Atlas alone because you built it this morning. The CleanShot history is worth a look yourself.",
      "select": [
        note("Build data – Lantern", "Not built in 41 days; Xcode rebuilds it on the next build."),
        note("Simulator system · iOS 18.0", "No simulator uses this version."),
      ],
      "deselect": [note("Build data – Atlas", "You built Atlas a few hours ago.")],
      "review": [note("CleanShot capture history", "22 GB of captures older than 30 days.")],
      "rejected": [
        note("Sintel (2010).mkv", "Personal files are never selected by an assistant."),
        ["id": "~/Documents/Old Projects", "why": "Not one of the findings it was shown."],
      ],
      "provider": "claude",
      "model": "sonnet",
      "escalated": true,
      "runID": "sample",
    ]
    let advice = (try? JSONSerialization.data(withJSONObject: json))
      .flatMap { try? JSONDecoder().decode(StorageAdvice.self, from: $0) }
    return model.messages + [
      AppModel.Message(role: .person, text: "Free up 30 GB"),
      AppModel.Message(role: .assistant, text: advice?.summary ?? "", provider: "claude", advice: advice),
    ]
  }

  /// A storage plan, a question that failed and an older plan, as the records of
  /// real runs would hold them.
  static func sampleRuns() -> [AssistantRun] {
    let now = Date().timeIntervalSinceReferenceDate
    func run(_ id: String, minutesAgo: Double, _ purpose: String, prompt: String, reply: String?, error: String? = nil) -> [String: Any] {
      var run: [String: Any] = [
        "id": id, "date": now - minutesAgo * 60, "purpose": purpose, "provider": "claude", "model": "sonnet",
        "system": "You advise on freeing space on a Mac. You are shown names, sizes and dates only.",
        "prompt": prompt, "duration": 8.4, "inputTokens": 5_210, "outputTokens": 412, "costUSD": 0.021,
        "rejected": ["~/Documents/Old Projects: Not one of the findings it was shown."], "proactive": false,
      ]
      run["reply"] = reply
      run["error"] = error
      return run
    }
    let records = [
      run(
        "sample", minutesAgo: 4, "storage plan",
        prompt: "Goal: Free up 30 GB\n\nFindings (name · size · last used · comes back):\n- Build data – Lantern · 18.2 GB · 41 days ago · rebuilds\n- Simulator system · iOS 18.0 · 9.8 GB · never used · downloads again",
        reply: "{\"summary\": \"I’d add the Lantern build data and the iOS 18 simulator system.\"}"
      ),
      run("question", minutesAgo: 62, "question", prompt: "Why is my Mac slow right now?", reply: nil, error: "Claude Code didn’t answer within 180 seconds."),
      run("older", minutesAgo: 60 * 26, "storage plan", prompt: "Goal: none", reply: "{\"summary\": \"Nothing to add.\"}"),
    ]
    return records.compactMap { record in
      (try? JSONSerialization.data(withJSONObject: record)).flatMap { try? JSONDecoder().decode(AssistantRun.self, from: $0) }
    }
  }
}
