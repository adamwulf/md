//
//  TocCommand.swift
//  md
//
//  Created by Adam Wulf on 4/12/26.
//

import ArgumentParser
import Foundation
import MarkdownKit

struct TocCommand: AsyncParsableCommand {

    static var configuration = CommandConfiguration(
        commandName: "toc",
        abstract: "Print a table of contents with line numbers"
    )

    @Flag(name: .long, help: "Show block numbers instead of line numbers")
    var blocks: Bool = false

    @Flag(name: .long, help: "Show line numbers (default)")
    var lines: Bool = false

    @Argument(help: "Path to the markdown file (reads stdin if omitted)")
    var file: String?

    func validate() throws {
        if blocks && lines {
            throw ValidationError("Cannot specify both --blocks and --lines")
        }
    }

    func run() async throws {
        let content = try InputReader.read(from: file)
        let parser = MarkdownParser()
        let parsedBlocks = parser.parse(content)

        let useBlocks = blocks

        let totalLines = content.components(separatedBy: "\n").count
        let totalBlockCount = parsedBlocks.count
        let numberWidth = useBlocks ? String(totalBlockCount).count : String(totalLines).count

        for (i, block) in parsedBlocks.enumerated() {
            if case .heading(let level, let text, _, _, let lineRange) = block {
                let indent = String(repeating: "  ", count: level - 1)
                let prefix = "\(indent)\(text) "
                let number = useBlocks ? i + 1 : lineRange.lowerBound
                let suffix = " \(String(number).leftPadded(toLength: numberWidth))"
                let fillLength = max(1, 60 - prefix.count - suffix.count)
                let dots = String(repeating: ".", count: fillLength)
                print("\(prefix)\(dots)\(suffix)")
            }
        }

        // EOF line
        let eofPrefix = "EOF "
        let eofNumber = useBlocks ? totalBlockCount : totalLines
        let eofSuffix = " \(String(eofNumber).leftPadded(toLength: numberWidth))"
        let eofFillLength = max(1, 60 - eofPrefix.count - eofSuffix.count)
        let eofDots = String(repeating: ".", count: eofFillLength)
        print("\(eofPrefix)\(eofDots)\(eofSuffix)")
    }
}

private extension String {
    func leftPadded(toLength length: Int) -> String {
        if count >= length { return self }
        return String(repeating: " ", count: length - count) + self
    }
}
