import Foundation

/// A part of the disk Glade stays out of.
public struct ProtectedZone: Sendable, Identifiable, Hashable {
  public var id: String
  public var title: String
  public var reason: String
  /// Path patterns. `~` is the home folder and `*` matches within one path component.
  public var paths: [String]
  /// Names that are protected wherever they appear, such as `*.photoslibrary`.
  public var names: [String]
  /// Locked zones can never be lifted. The rest are on by default and can be switched off.
  public var locked: Bool
  /// A folder that merely contains one of these names is off limits too.
  public var strictInside: Bool

  public init(
    id: String, title: String, reason: String, paths: [String] = [], names: [String] = [],
    locked: Bool = true, strictInside: Bool = false
  ) {
    self.id = id
    self.title = title
    self.reason = reason
    self.paths = paths
    self.names = names
    self.locked = locked
    self.strictInside = strictInside
  }
}

public enum ProtectedZones {
  /// Everything Glade protects out of the box. Order doesn't matter.
  public static let builtIn: [ProtectedZone] = [
    ProtectedZone(
      id: "credentials",
      title: "Keys & Credentials",
      reason: "Sign-in keys and tokens for servers, clouds and developer tools.",
      paths: [
        "~/.ssh", "~/.gnupg", "~/.aws", "~/.azure", "~/.kube", "~/.oci", "~/.docker/config.json",
        "~/.docker/contexts", "~/.config/gcloud", "~/.config/gh", "~/.config/hub", "~/.config/doctl",
        "~/.config/op", "~/.config/rclone", "~/.config/sops", "~/.config/git/credentials",
        "~/.config/configstore", "~/.config/netlify", "~/.config/vercel", "~/.config/wrangler",
        "~/.config/supabase", "~/.config/stripe", "~/.config/firebase", "~/.config/heroku",
        "~/.wrangler/config", "~/.vercel", "~/.netlify",
        "~/.netrc", "~/.npmrc", "~/.yarnrc", "~/.yarnrc.yml", "~/.pypirc", "~/.git-credentials",
        "~/.gitconfig", "~/.vault-token", "~/.age", "~/.password-store", "~/.1password",
        "~/.terraform.d/credentials.tfrc.json", "~/.cargo/credentials", "~/.cargo/credentials.toml",
        "~/.gem/credentials", "~/.m2/settings.xml", "~/.m2/settings-security.xml",
        "~/.gradle/gradle.properties", "~/.android/adbkey", "~/.android/adbkey.pub",
        "~/.android/debug.keystore", "~/.appstoreconnect", "~/.expo", "~/.fastlane",
        "~/Library/Application Support/com.apple.TCC",
        "~/Library/MobileDevice/Provisioning Profiles",
        "~/Library/Developer/Xcode/UserData/Provisioning Profiles",
      ],
      names: [
        ".env", ".env.*", "*.pem", "*.p12", "*.p8", "*.keystore", "*.jks", "*.mobileprovision",
        "id_rsa", "id_ed25519", "id_ecdsa", "*.kdbx",
      ]
    ),
    ProtectedZone(
      id: "keychains",
      title: "Keychain & Password Managers",
      reason: "Saved passwords, passkeys and the apps that manage them.",
      paths: [
        "~/Library/Keychains",
        "~/Library/Group Containers/2BUA8C4S2C.com.1password",
        "~/Library/Group Containers/2BUA8C4S2C.com.agilebits",
        "~/Library/Containers/com.1password.*", "~/Library/Containers/com.agilebits.*",
        "~/Library/Application Support/1Password", "~/Library/Application Support/Bitwarden",
        "~/Library/Containers/com.bitwarden.desktop", "~/Library/Application Support/KeePassXC",
        "~/Library/Application Support/Dashlane", "~/Library/Application Support/LastPass",
        "~/Library/Application Support/Proton Pass", "~/Library/Application Support/Enpass",
        "~/Library/Application Support/NordPass", "~/Library/Application Support/Authy Desktop",
      ]
    ),
    ProtectedZone(
      id: "agent-memory",
      title: "Agent Memory, Skills & Sign-ins",
      reason: "What you've taught your AI agents, their settings, and their sign-in files.",
      paths: [
        "~/.claude/CLAUDE.md", "~/.claude/settings.json", "~/.claude/settings.local.json",
        "~/.claude/.credentials.json", "~/.claude.json", "~/.claude/skills", "~/.claude/agents",
        "~/.claude/commands", "~/.claude/plugins", "~/.claude/keybindings.json", "~/.claude/hooks",
        "~/.claude/bin", "~/.claude/projects/*/memory", "~/.claude/workflows", "~/.claude-mem",
        "~/.codex/auth.json", "~/.codex/config.toml", "~/.codex/AGENTS.md", "~/.codex/guides",
        "~/.codex/skills", "~/.codex/memories", "~/.codex/prompts", "~/.codex/rules",
        "~/.cursor/mcp.json", "~/.cursor/rules", "~/.cursor/cli-config.json", "~/.cursor/skills",
        "~/.gemini/oauth_creds.json", "~/.gemini/settings.json", "~/.gemini/GEMINI.md",
        "~/.gemini/google_accounts.json", "~/.gemini/extensions", "~/.gemini/skills", "~/.gemini/agents",
        "~/.gemini/commands", "~/.gemini/hooks", "~/.gemini/antigravity/knowledge", "~/.gemini/antigravity/skills",
        "~/.config/opencode", "~/.local/share/opencode/auth.json", "~/.config/agents", "~/.agents",
      ],
      names: ["CLAUDE.md", "AGENTS.md", "GEMINI.md", "MEMORY.md", "SKILL.md"]
    ),
    ProtectedZone(
      id: "photos",
      title: "Photo, Music & Video Libraries",
      reason: "Libraries that apps manage as a single unit. Removing pieces corrupts them.",
      names: [
        "*.photoslibrary", "*.photolibrary", "*.aplibrary", "*.migratedphotolibrary",
        "*.musiclibrary", "*.tvlibrary", "*.imovielibrary", "*.fcpbundle", "*.theater",
        "*.logicx", "*.band", "*.dvdmedia", "*.lrcat", "*.lrdata", "*.cocatalog",
      ],
      strictInside: true
    ),
    ProtectedZone(
      id: "messages-mail",
      title: "Messages & Mail",
      reason: "Your conversations, email and their attachments.",
      paths: [
        "~/Library/Messages", "~/Library/Mail", "~/Library/Mail Downloads",
        "~/Library/Containers/com.apple.mail", "~/Library/Containers/com.apple.MailServiceAgent",
        "~/Library/Containers/com.apple.iChat", "~/Library/Containers/com.apple.MobileSMS",
        "~/Library/Group Containers/group.com.apple.mail",
        "~/Library/Containers/com.microsoft.Outlook", "~/Library/Group Containers/UBF8T346G9.Office/Outlook",
        "~/Library/Application Support/Signal", "~/Library/Application Support/WhatsApp",
        "~/Library/Group Containers/group.net.whatsapp.*", "~/Library/Containers/net.whatsapp.*",
        "~/Library/Application Support/Telegram Desktop",
        "~/Library/Group Containers/*.ru.keepcoder.Telegram",
        "~/Library/Application Support/Slack/storage", "~/Library/Application Support/discord/Local Storage",
        "~/Library/Thunderbird", "~/Library/Application Support/Spark",
      ]
    ),
    ProtectedZone(
      id: "apple-personal",
      title: "Notes, Contacts, Calendars & Health",
      reason: "Personal records kept by Apple's own apps.",
      paths: [
        "~/Library/Group Containers/group.com.apple.notes", "~/Library/Containers/com.apple.Notes",
        "~/Library/Calendars", "~/Library/Group Containers/group.com.apple.calendar",
        "~/Library/Application Support/AddressBook", "~/Library/Contacts", "~/Library/Reminders",
        "~/Library/Group Containers/group.com.apple.reminders", "~/Library/Health",
        "~/Library/HomeKit", "~/Library/Passes", "~/Library/Accounts", "~/Library/IdentityServices",
        "~/Library/Cookies", "~/Library/Suggestions", "~/Library/PersonalizationPortrait",
        "~/Library/Biome", "~/Library/DuetExpertCenter", "~/Library/Sharing", "~/Library/Shortcuts",
        "~/Library/Group Containers/group.com.apple.VoiceMemos.shared",
        "~/Library/Containers/com.apple.VoiceMemos", "~/Library/Containers/com.apple.freeform",
        "~/Library/Group Containers/group.com.apple.freeform", "~/Library/Journal",
        "~/Library/Containers/com.apple.journal", "~/Library/Stickers", "~/Library/StickiesDatabase",
        "~/Library/Containers/com.apple.Stickies", "~/Library/Containers/com.apple.Passwords",
        "~/Library/Preferences", "~/Library/Fonts", "~/Library/Keyboard Layouts",
        "~/Library/LaunchAgents", "~/Library/Services", "~/Library/Scripts",
        "~/Library/Application Scripts", "~/Library/Autosave Information",
        "~/Library/Application Support/Knowledge", "~/Library/Application Support/CallHistoryDB",
        "~/Library/Application Support/CallHistoryTransactions", "~/Library/Assistant",
        "~/Library/Metadata", "~/Library/Spelling", "~/Library/Dictionaries", "~/Library/ColorSync",
      ]
    ),
    ProtectedZone(
      id: "cloud",
      title: "iCloud Drive & Cloud Storage",
      reason: "Synced folders. Removing a file here removes it from every device.",
      paths: [
        "~/Library/Mobile Documents", "~/Library/CloudStorage", "~/Library/Application Support/CloudDocs",
        "~/Library/Application Support/FileProvider", "~/Library/Application Support/iCloud",
        "~/iCloud Drive", "~/iCloud Drive (Archive)*", "~/Dropbox", "~/Dropbox (*)", "~/Google Drive",
        "~/GoogleDrive", "~/My Drive", "~/OneDrive", "~/OneDrive - *", "~/Box", "~/Box Sync",
        "~/pCloud Drive", "~/MEGA", "~/Sync", "~/Nextcloud", "~/ownCloud", "~/Proton Drive",
        "~/Library/Application Support/Dropbox", "~/Library/Application Support/Google/DriveFS",
        "~/.dropbox",
      ]
    ),
    ProtectedZone(
      id: "browsers",
      title: "Browser Profiles",
      reason: "Bookmarks, history, saved logins, extensions and open tabs.",
      paths: [
        "~/Library/Safari", "~/Library/Containers/com.apple.Safari",
        "~/Library/Containers/com.apple.Safari.*", "~/Library/Group Containers/group.com.apple.safari*",
        "~/Library/Application Support/Google/Chrome", "~/Library/Application Support/Google/Chrome *",
        "~/Library/Application Support/Chromium", "~/Library/Application Support/BraveSoftware",
        "~/Library/Application Support/Microsoft Edge", "~/Library/Application Support/Microsoft Edge *",
        "~/Library/Application Support/Firefox", "~/Library/Application Support/Arc",
        "~/Library/Application Support/Vivaldi", "~/Library/Application Support/com.operasoftware.*",
        "~/Library/Application Support/zen", "~/Library/Application Support/Orion",
        "~/Library/Application Support/Dia", "~/Library/Application Support/Comet",
        "~/Library/Application Support/Aside*", "~/Library/Application Support/at.studio.*",
        "~/Library/Application Support/Atlas", "~/Library/Application Support/com.openai.atlas",
        "~/Library/Application Support/DuckDuckGo", "~/Library/Containers/com.duckduckgo.*",
        "~/Library/Application Support/Sidekick", "~/Library/Application Support/Thorium",
        "~/Library/Application Support/TorBrowser-Data", "~/Library/Application Support/Ladybird",
      ]
    ),
    ProtectedZone(
      id: "security-software",
      title: "Security & Device Management",
      reason: "Endpoint security, VPN and device management agents. Removing their files can set off tamper alarms your organisation's security team sees.",
      // Matched wherever they appear: ~/Library, app containers with a team prefix,
      // and the per-user temporary and cache folders under /private/var/folders.
      names: [
        "*com.crowdstrike.*", "*com.sentinelone.*", "*com.sentinel-labs.*", "*com.eset.*", "*com.jamf.*",
        "*com.jamfsoftware.*", "*com.paloaltonetworks.*", "*com.cisco.anyconnect*", "*com.cisco.secureclient*",
        "*com.alibaba.security.*",
      ]
    ),
    ProtectedZone(
      id: "git",
      title: "Git Repositories",
      reason: "Commit history. A project's .git folder is never touched, and a repository is never removed whole.",
      names: [".git", ".jj", ".hg", ".svn"]
    ),
    ProtectedZone(
      id: "glade",
      title: "Glade",
      reason: "Glade's own settings, receipts and logs.",
      paths: ["~/Library/Application Support/Glade", "~/Library/Logs/Glade"]
    ),
    ProtectedZone(
      id: "backups",
      title: "Time Machine & Backups",
      reason: "Backups are only useful when they're complete.",
      paths: ["~/Library/Application Support/Backblaze", "~/Library/Application Support/Arq*"],
      names: ["*.backupbundle", "*.sparsebundle", "Backups.backupdb", "*.timemachine", "*.arqbackup"],
      strictInside: true
    ),
    ProtectedZone(
      id: "virtual-machines",
      title: "Virtual Machines",
      reason: "Whole computers stored as one file. They can't be partly cleaned.",
      names: ["*.pvm", "*.vmwarevm", "*.utm", "*.vbox", "*.qcow2", "*.vmdk"],
      locked: false,
      strictInside: true
    ),
  ]
}
