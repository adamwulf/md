//
//  RemoveCommand.swift
//  md
//
//  Created by Adam Wulf on 4/12/26.
//

import ArgumentParser
import Foundation
import MarkdownKit

struct RemoveCommand: AsyncParsableCommand {

    static var configuration = CommandConfiguration(
        commandName: "remove",
        abstract: "Remove one or more blocks from a markdown file"
    )

    @Flag(name: .shortAndLong, help: "Edit the file in place")
    var inPlace: Bool = false

    @Argument(help: "Start block index (1-based)")
    var start: Int

    @Argument(help: "End block index (inclusive, defaults to start)")
    var end: Int?

    @OptionGroup var input: InputOptions

    func validate() throws {
        if inPlace && input.file == nil {
            throw ValidationError("Cannot use --in-place with --stdin")
        }
    }

    func run() async throws {
        let content = try input.readContent()
        let end = end ?? start

        let parser = MarkdownParser()
        let blocks = parser.parse(content)

        guard start >= 1 else {
            throw ValidationError("Start index must be >= 1, got \(start)")
        }
        guard end >= start else {
            throw ValidationError("End index must be >= start, got \(start)...\(end)")
        }
        guard end <= blocks.count else {
            throw ValidationError("End index must be <= \(blocks.count), got \(end)")
        }

        var remaining: [MarkdownBlock] = []
        for (i, block) in blocks.enumerated() {
            let blockNum = i + 1
            if blockNum >= start && blockNum <= end {
                continue
            }
            remaining.append(block)
        }

        let result = BlockFormatter.format(remaining)
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
