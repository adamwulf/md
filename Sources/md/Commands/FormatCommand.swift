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
        let source = try input.readSource()
        switch Frontmatter.parseResult(source.content) {
        case .malformed(let error) where frontmatter != nil:
            // An explicit conversion request cannot be honored without
            // reading the source fence. Refuse it rather than silently
            // returning unchanged content while reporting success.
            throw error
        case .valid(let parsed):
            switch frontmatter {
            case .json:
                try parsed.validateForJSON()
            case .toml:
                try parsed.validateForTOML()
            case .yaml, .none:
                break
            }
        case .absent, .malformed:
            break
        }
        try InputReader.writeToStdout(
            FormatCommand.format(
                content: source.content,
                targetFrontmatter: frontmatter
            ),
            includeByteOrderMark: source.hasUTF8ByteOrderMark
        )
    }

    /// Format markdown content. If the source has non-empty frontmatter and
    /// `targetFrontmatter` is supplied, the frontmatter is re-serialized to that
    /// format. Empty frontmatter is stripped, and content without frontmatter is
    /// emitted with only the body normalized — `targetFrontmatter` is ignored in
    /// those cases. A document with malformed or non-mapping frontmatter is
    /// returned byte-for-byte unchanged so formatting cannot discard its data.
    static func format(content: String, targetFrontmatter: FrontmatterFormat? = nil) -> String {
        let parser = MarkdownParser()

        let parsed: Frontmatter
        switch Frontmatter.parseResult(content) {
        case .absent:
            let blocks = parser.parse(content)
            return BlockFormatter.format(blocks)
        case .malformed:
            // Formatting or converting an unreadable fence risks silently
            // deleting data. Preserve the complete document byte-for-byte.
            return content
        case .valid(let frontmatter):
            parsed = frontmatter
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
            // The command-line entry point validates before calling this API.
            // Static callers still fall through to verbatim source frontmatter
            // if conversion cannot be represented.
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
