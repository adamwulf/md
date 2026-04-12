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

            Output is written to stdout.

              $ md format --file README.md
              $ cat README.md | md format --stdin
            """
    )

    @OptionGroup var input: InputOptions

    func run() async throws {
        let content = try input.readContent()
        let parser = MarkdownParser()

        if let frontmatter = Frontmatter.parse(content) {
            // Format only the body, preserve frontmatter
            let blocks = parser.parse(frontmatter.body)
            let formattedBody = BlockFormatter.format(blocks)

            if frontmatter.data.isEmpty {
                // Strip empty frontmatter
                print(formattedBody, terminator: "")
            } else {
                let serialized = try frontmatter.serializeData()
                let delimiter: String
                switch frontmatter.format {
                case .yaml: delimiter = "---"
                case .toml: delimiter = "+++"
                case .json: delimiter = ";;;"
                }
                print("\(delimiter)\n\(serialized)\(delimiter)\n\(formattedBody)", terminator: "")
            }
        } else {
            let blocks = parser.parse(content)
            print(BlockFormatter.format(blocks), terminator: "")
        }
    }
}
