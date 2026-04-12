//
//  InsertAfterCommand.swift
//  md
//
//  Created by Adam Wulf on 4/12/26.
//

import ArgumentParser
import Foundation
import MarkdownKit

struct InsertAfterCommand: AsyncParsableCommand {

    static var configuration = CommandConfiguration(
        commandName: "insert-after",
        abstract: "Insert markdown content after a block"
    )

    @Argument(help: "Block index (1-based) to insert after")
    var blockIndex: Int

    @Argument(help: "Markdown content to insert")
    var content: String

    @Argument(help: "Path to the markdown file")
    var file: String

    func run() async throws {
        let parser = MarkdownParser()
        let fileContent = try InputReader.read(from: file)
        let blocks = parser.parse(fileContent)

        guard blockIndex >= 1, blockIndex <= blocks.count else {
            throw ValidationError("Block index must be in range 1...\(blocks.count), got \(blockIndex)")
        }

        // Parse and format the new content
        let newBlocks = parser.parse(content)
        let formattedNew = BlockFormatter.format(newBlocks)

        // Build output: blocks before + target block + new content + blocks after
        var result = ""
        for (i, block) in blocks.enumerated() {
            if i > 0 {
                result += "\n"
            }
            result += BlockFormatter.format(block)

            if i + 1 == blockIndex {
                result += "\n" + formattedNew
            }
        }

        print(result, terminator: "")
    }
}
