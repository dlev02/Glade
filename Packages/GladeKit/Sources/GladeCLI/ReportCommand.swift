import ArgumentParser
import Foundation
import GladeKit

struct Report: ParsableCommand {
  static let configuration = CommandConfiguration(
    abstract: "Save a problem report to the Desktop and print the link for filing an issue.",
    discussion: "The report has versions, settings and recent log lines. Nothing is sent anywhere."
  )

  @Flag(name: .long, help: "Include finding names and locations from the last scan.")
  var includeFindings = false

  @Flag(name: .long, help: "Print the report instead of saving it.")
  var print = false

  func run() throws {
    let text = DiagnosticReport.build(options: .init(includeFindings: includeFindings))
    if print {
      Swift.print(text)
      return
    }
    let file = try DiagnosticReport.save(text)
    Swift.print("Saved \(Redactor.tilde(file.path))")
    if let url = DiagnosticReport.issueURL() { Swift.print("File an issue: \(url.absoluteString.prefix(60))…") }
  }
}
