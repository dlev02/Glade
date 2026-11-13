import GladeKit
import SwiftUI
import UniformTypeIdentifiers

/// Little Snitch, when it’s installed: import an export, see what Glade notices, and
/// ask for a review. Glade never touches Little Snitch itself.
struct LittleSnitchCard: View {
  @Environment(AppModel.self) private var model
  var rules: LittleSnitchRules?
  @State private var importing = false
  @State private var problem: String?

  var body: some View {
    Card {
      VStack(alignment: .leading, spacing: Metrics.m) {
        HStack(alignment: .firstTextBaseline) {
          SectionTitle("Little Snitch")
          Spacer()
          if let rules {
            Text("Imported \(rules.imported.formatted(.relative(presentation: .named)))")
              .font(.caption)
              .foregroundStyle(.secondary)
          }
        }
        if let rules {
          let findings = rules.findings()
          HStack(spacing: Metrics.xl) {
            count("\(rules.rules.count)", "rules")
            count("\(rules.allowCount)", "allow")
            count("\(rules.denyCount)", "deny")
            if rules.blocklistEntries > 0 { count("\(rules.blocklistEntries)", "blocked") }
          }
          if !findings.isEmpty {
            VStack(alignment: .leading, spacing: Metrics.xs) {
              ForEach(findings.prefix(4)) { finding in
                Label(finding.sentence, systemImage: finding.kind == .allowsEverything || finding.kind == .conflict ? "exclamationmark.circle.fill" : "circle.fill")
                  .labelStyle(FindingLabel(prominent: finding.kind == .allowsEverything || finding.kind == .conflict))
              }
              if findings.count > 4 {
                Text("and \(findings.count - 4) more").foregroundStyle(.secondary)
              }
            }
            .font(.callout)
          }
          HStack {
            Button("Import Again…") { importing = true }
            Spacer()
            Button("Review with Assistant") { Task { await model.reviewLittleSnitch() } }
              .buttonStyle(.borderedProminent)
          }
        } else {
          Text("In Little Snitch, choose File › Create Backup, then import it here. Glade reads it, never Little Snitch itself.")
            .foregroundStyle(.secondary)
            .font(.callout)
            .fixedSize(horizontal: false, vertical: true)
          Button("Import Rules…") { importing = true }
        }
        if let problem {
          Text(problem).font(.caption).foregroundStyle(Palette.critical)
        }
      }
    }
    .fileImporter(isPresented: $importing, allowedContentTypes: [.json, UTType(filenameExtension: "lsbackup") ?? .data, UTType(filenameExtension: "lsrules") ?? .data, .data]) { result in
      switch result {
      case .success(let url): problem = model.importLittleSnitch(url)
      case .failure(let error): problem = error.localizedDescription
      }
    }
  }

  private func count(_ figure: String, _ label: String) -> some View {
    VStack(alignment: .leading, spacing: 0) {
      Text(figure).font(.liveFigure(20)).monospacedDigit()
      Text(label).font(.caption).foregroundStyle(.secondary)
    }
    .accessibilityElement(children: .combine)
  }
}

/// A small dot or mark before each thing Glade noticed.
private struct FindingLabel: LabelStyle {
  var prominent: Bool

  func makeBody(configuration: Configuration) -> some View {
    HStack(alignment: .firstTextBaseline, spacing: Metrics.s) {
      configuration.icon
        .font(prominent ? .callout : .system(size: 5))
        .foregroundStyle(prominent ? Palette.warning : .secondary)
        .frame(width: 14)
      configuration.title
    }
  }
}
