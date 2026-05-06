//
//  FmtCommand.swift
//  md
//
//  Created by Adam Wulf on 4/12/26.
//

import ArgumentParser
import Foundation
import MarkdownKit

struct FormatCommand: AsyncParsableCommand {

    static var configuration = CommandConfiguration(
        commandName: "format",
        abstract: "Normalize markdown formatting, preserving frontmatter",
        discussion: """
            Re-renders the markdown through cmark-gfm to produce consistent \
            formatting. If frontmatter is present (YAML with ---, TOML with +++, \
            or JSON with ;;;), it is preserved as-is. Empty frontmatter is stripped.

            Use --frontmatter <yaml|toml|json> to convert non-empty frontmatter \
            to a different format while normalizing the body.

            Output is written to stdout.

              $ md format --file README.md
              $ cat README.md | md format --stdin
              $ md format --frontmatter json --file README.md
            """
    )

    @Option(name: .long, help: "Convert frontmatter to the given format (yaml, toml, or json)")
    var frontmatter: FrontmatterFormat?

    @OptionGroup var input: InputOptions

    func run() async throws {
        let content = try input.readContent()
        print(FormatCommand.format(content: content, targetFrontmatter: frontmatter), terminator: "")
    }

    /// Format markdown content. If the source has non-empty frontmatter and
    /// `targetFrontmatter` is supplied, the frontmatter is re-serialized to that
    /// format. Empty frontmatter is stripped, and content without frontmatter is
    /// emitted with only the body normalized — `targetFrontmatter` is ignored in
    /// those cases.
    static func format(content: String, targetFrontmatter: FrontmatterFormat? = nil) -> String {
        let parser = MarkdownParser()

        guard let parsed = Frontmatter.parse(content) else {
            let blocks = parser.parse(content)
            return BlockFormatter.format(blocks)
        }

        let blocks = parser.parse(parsed.body)
        let formattedBody = BlockFormatter.format(blocks)

        if parsed.data.isEmpty {
            return formattedBody
        }

        if let targetFrontmatter, targetFrontmatter != parsed.format {
            var converted = parsed
            converted.format = targetFrontmatter
            if let serialized = try? converted.serializeData() {
                let delimiter = delimiter(for: targetFrontmatter)
                return "\(delimiter)\n\(serialized)\(delimiter)\n\(formattedBody)"
            }
            // Serialization failed — fall through to verbatim emission of the
            // source frontmatter, using the source's original delimiters.
        }

        let delimiter = delimiter(for: parsed.format)
        return "\(delimiter)\n\(parsed.rawContent)\n\(delimiter)\n\(formattedBody)"
    }

    private static func delimiter(for format: FrontmatterFormat) -> String {
        switch format {
        case .yaml: return "---"
        case .toml: return "+++"
        case .json: return ";;;"
        }
    }
}
