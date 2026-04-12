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
        abstract: "Insert markdown content before a block"
    )

    @Argument(help: "Block index (1-based) to insert before")
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

        // Build output: blocks before + new content + target block + blocks after
        var result = ""
        for (i, block) in blocks.enumerated() {
            if i + 1 == blockIndex {
                if i > 0 {
                    result += "\n"
                }
                result += formattedNew + "\n"
                result += BlockFormatter.format(block)
            } else {
                if i > 0 {
                    result += "\n"
                }
                result += BlockFormatter.format(block)
            }
        }

        print(result, terminator: "")
    }
}
