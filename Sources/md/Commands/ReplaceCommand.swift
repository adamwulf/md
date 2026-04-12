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
        abstract: "Replace one or more blocks with new markdown content"
    )

    @Flag(name: .shortAndLong, help: "Edit the file in place")
    var inPlace: Bool = false

    @Argument(help: "Start block index (1-based)")
    var start: Int

    @Argument(help: "End block index (inclusive) or markdown content")
    var secondArg: String

    @Argument(help: "Markdown content (when replacing a range) and file path")
    var remaining: [String] = []

    func run() async throws {
        let end: Int
        let newContent: String
        let file: String?

        if let e = Int(secondArg) {
            // md replace <start> <end> "content" [file]
            guard remaining.count >= 1 else {
                throw ValidationError("Expected: md replace <start> <end> \"content\" [file]")
            }
            end = e
            if remaining.count >= 2 {
                newContent = remaining[remaining.count - 2]
                file = remaining[remaining.count - 1]
            } else {
                newContent = remaining[0]
                file = nil
            }
        } else {
            // md replace <start> "content" [file]
            end = start
            newContent = secondArg
            if !remaining.isEmpty {
                file = remaining[remaining.count - 1]
            } else {
                file = nil
            }
        }

        let parser = MarkdownParser()
        let fileContent = try InputReader.read(from: file)
        let blocks = parser.parse(fileContent)

        guard start >= 1, end >= start, end <= blocks.count else {
            throw ValidationError("Block indices must be in range 1...\(blocks.count), got \(start)...\(end)")
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
            guard let file = file else {
                throw ValidationError("Cannot use --in-place with stdin")
            }
            try InputReader.write(result, to: file)
        } else {
            print(result, terminator: "")
        }
    }
}
