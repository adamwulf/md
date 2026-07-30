//
//  InsertBeforeCommand.swift
//  md
//
//  Created by Adam Wulf on 4/12/26.
//

import ArgumentParser
import Foundation
import MarkdownKit

struct InsertBeforeCommand: AsyncParsableCommand {

    static var configuration = CommandConfiguration(
        commandName: "insert-before",
        abstract: "Insert markdown content before a block",
        discussion: """
            Inserts new markdown content immediately before the specified block. \
            The new content is parsed and re-formatted. Output is written to \
            stdout unless -i/--in-place is used.

              $ md insert-before 3 "## New Section" --file README.md
              $ md insert-before 1 "Intro paragraph." --file README.md -i
            """
    )

    @Flag(name: .shortAndLong, help: "Edit the file in place")
    var inPlace: Bool = false

    @Argument(help: "Block index (1-based) to insert before")
    var blockIndex: Int

    @Argument(help: "Markdown content to insert")
    var content: String

    @OptionGroup var input: InputOptions

    func validate() throws {
        if inPlace && input.file == nil {
            throw ValidationError("Cannot use --in-place with --stdin")
        }
    }

    func run() async throws {
        let parser = MarkdownParser()
        let fileContent = try input.readContent()
        let blocks = parser.parseDocument(fileContent)

        guard blockIndex >= 1, blockIndex <= blocks.count else {
            throw ValidationError("Block index must be in range 1...\(blocks.count), got \(blockIndex)")
        }

        // Parse and format the new content
        let newBlocks = parser.parse(content)
        let formattedNew = BlockFormatter.format(newBlocks)

        // Splice into the original source instead of re-formatting every block.
        // Re-formatting the full document loses syntax that MarkdownBlock does
        // not model, including frontmatter and footnote definitions.
        let targetBlock = blocks[blockIndex - 1]
        guard let result = MarkdownSourceEditor.inserting(
            formattedNew + "\n",
            before: targetBlock,
            in: fileContent
        ) else {
            throw ValidationError("Unable to locate block \(blockIndex) in the source")
        }

        if inPlace {
            guard let file = input.file else {
                throw ValidationError("Cannot use --in-place with --stdin")
            }
            try InputReader.write(result, to: file)
        } else {
            print(result, terminator: "")
        }
    }
}
