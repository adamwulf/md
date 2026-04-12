//
//  BlocksCommand.swift
//  md
//
//  Created by Adam Wulf on 4/12/26.
//

import ArgumentParser
import Foundation
import MarkdownKit

struct BlocksCommand: AsyncParsableCommand {

    static var configuration = CommandConfiguration(
        commandName: "blocks",
        abstract: "Print markdown blocks by index"
    )

    @Flag(name: .long, help: "Print the number of blocks")
    var count: Bool = false

    @Argument(help: "Block index or range (start end) followed by optional file path (reads stdin if omitted)")
    var input: [String] = []

    func run() async throws {
        let parsed = InputReader.parsePassthrough(input)
        let content = try InputReader.read(from: parsed.file)
        let parser = MarkdownParser()
        let blocks = parser.parse(content)

        if count {
            print(blocks.count)
            return
        }

        let indices = parsed.indices

        guard !indices.isEmpty else {
            // No index given, print all blocks with their indices (1-based)
            for (i, block) in blocks.enumerated() {
                print("[\(i + 1)] \(summary(of: block))")
            }
            return
        }

        let start = indices[0]
        let end = indices.count > 1 ? indices[1] : start

        guard start >= 1, end >= start, end <= blocks.count else {
            throw ValidationError("Block indices must be in range 1...\(blocks.count), got \(start)...\(end)")
        }

        let utf8 = Array(content.utf8)
        for i in start...end {
            if i > start {
                print()
            }
            let block = blocks[i - 1]
            let range = block.byteRange
            let startIdx = range.location
            let endIdx = min(range.location + range.length, utf8.count)
            let slice = Array(utf8[startIdx..<endIdx])
            let text = String(decoding: slice, as: UTF8.self)
            print(text)
        }
    }

    private func summary(of block: MarkdownBlock) -> String {
        switch block {
        case .heading(let level, let text, _, _, let lineRange):
            return "heading(\(level)) L\(lineRange.lowerBound): \(text)"
        case .paragraph(_, _, _, let lineRange):
            return "paragraph L\(lineRange.lowerBound)-\(lineRange.upperBound)"
        case .codeBlock(let language, _, _, _, let lineRange):
            let lang = language ?? "none"
            return "code(\(lang)) L\(lineRange.lowerBound)-\(lineRange.upperBound)"
        case .list(let items, let ordered, _, _, let lineRange):
            let type = ordered ? "ordered" : "unordered"
            return "\(type) list(\(items.count) items) L\(lineRange.lowerBound)-\(lineRange.upperBound)"
        case .blockquote(_, _, _, let lineRange):
            return "blockquote L\(lineRange.lowerBound)-\(lineRange.upperBound)"
        case .thematicBreak(_, _, let lineRange):
            return "thematic_break L\(lineRange.lowerBound)"
        case .table(let rows, _, _, let lineRange):
            return "table(\(rows.count) rows) L\(lineRange.lowerBound)-\(lineRange.upperBound)"
        }
    }
}
