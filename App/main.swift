import Foundation
import GladeCLI
import GladeKit
import SwiftUI

// Glade's executable is both the app and the command line. Launched normally it opens
// the app; launched as `glade` (a link to this executable) or with a command name as
// its first argument, it runs that command and exits.
let arguments = CommandLine.arguments
let invokedAs = arguments.first.map { ($0 as NSString).lastPathComponent } ?? ""
let isCommandLine = invokedAs == Brand.cli || (arguments.count > 1 && CLI.subcommands.contains(arguments[1]))

if isCommandLine {
  Task {
    await CLI.run(Array(arguments.dropFirst()))
    exit(0)
  }
  // A run loop rather than dispatchMain(), which gives up the main thread: commands
  // that draw (`snapshot`) need main-actor work to run on the real main thread.
  CFRunLoopRun()
} else {
  GladeApp.main()
}
