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

    @Argument(help: "Block index or range (start end) followed by optional file path (reads stdin if omitted)")
    var input: [String] = []

    func run() async throws {
        let parsed = InputReader.parsePassthrough(input)
        let content = try InputReader.read(from: parsed.file)
        let indices = parsed.indices

        guard !indices.isEmpty else {
            throw ValidationError("Must specify at least a block index")
        }

        let start = indices[0]
        let end = indices.count > 1 ? indices[1] : start

        let parser = MarkdownParser()
        let blocks = parser.parse(content)

        guard start >= 1, end >= start, end <= blocks.count else {
            throw ValidationError("Block indices must be in range 1...\(blocks.count), got \(start)...\(end)")
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
            guard let file = parsed.file else {
                throw ValidationError("Cannot use --in-place with stdin")
            }
            try InputReader.write(result, to: file)
        } else {
            print(result, terminator: "")
        }
    }
}
