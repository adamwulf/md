//
//  ReplaceCommand.swift
//  md
//
//  Created by Adam Wulf on 4/12/26.
//

import ArgumentParser
import Foundation
import MarkdownKit

struct ReplaceCommand: AsyncParsableCommand {

    static var configuration = CommandConfiguration(
        commandName: "replace",
        abstract: "Replace one or more blocks with new markdown content",
        discussion: """
            Two calling conventions:

              md replace START "content" --file <path>
                Replace a single block at START with "content".

              md replace START END "content" --file <path>
                Replace blocks START through END (inclusive) with "content".

            The second argument is interpreted as an end index if it parses as \
            an integer, otherwise it is treated as the replacement content. \
            Output is written to stdout unless -i/--in-place is used.

              $ md replace 1 "# New Title" --file README.md
              $ md replace 2 4 "Replacement." --file README.md
              $ md replace 1 "# New Title" --file README.md -i
            """
    )

    @Flag(name: .shortAndLong, help: "Edit the file in place")
    var inPlace: Bool = false

    @Argument(help: "Start block index (1-based)")
    var start: Int

    @Argument(help: "End block index (inclusive), or markdown content if replacing a single block")
    var endOrContent: String

    @Argument(help: "Markdown content (required when end index is provided)")
    var content: String?

    @OptionGroup var input: InputOptions

    func validate() throws {
        if inPlace && input.file == nil {
            throw ValidationError("Cannot use --in-place with --stdin")
        }
    }

    func run() async throws {
        let end: Int
        let newContent: String

        if let e = Int(endOrContent) {
            guard let content = content else {
                throw ValidationError("Expected: md replace <start> <end> \"content\" --file <file>")
            }
            end = e
            newContent = content
        } else {
            end = start
            newContent = endOrContent
        }

        let parser = MarkdownParser()
        let fileContent = try input.readContent()
        let blocks = parser.parse(fileContent)

        guard start >= 1 else {
            throw ValidationError("Start index must be >= 1, got \(start)")
        }
        guard end >= start else {
            throw ValidationError("End index must be >= start, got \(start)...\(end)")
        }
        guard end <= blocks.count else {
            throw ValidationError("End index must be <= \(blocks.count), got \(end)")
        }

        let newBlocks = parser.parse(newContent)

        var result = ""
        for (i, block) in blocks.enumerated() {
            let blockNum = i + 1

            if blockNum == start {
                if !result.isEmpty { result += "\n" }
                result += BlockFormatter.format(newBlocks)
            } else if blockNum > start && blockNum <= end {
                continue
            } else {
                if !result.isEmpty { result += "\n" }
                result += BlockFormatter.format(block)
            }
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
