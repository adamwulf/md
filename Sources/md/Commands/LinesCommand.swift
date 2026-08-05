//
//  LinesCommand.swift
//  md
//
//  Created by Adam Wulf on 4/12/26.
//

import ArgumentParser
import Foundation

struct LinesCommand: AsyncParsableCommand {

    static var configuration = CommandConfiguration(
        commandName: "lines",
        abstract: "List, count, or print raw lines by number (1-based)",
        discussion: """
            Three modes of operation:

              No arguments — lists all lines with left-padded line numbers.
              --count     — prints the total number of lines.
              START [END] — prints lines START through END (inclusive). END \
            defaults to START.

              $ md lines --file README.md
              $ md lines --count --file README.md
              $ md lines 10 --file README.md
              $ md lines 10 20 --file README.md
            """
    )

    @Flag(name: .long, help: "Print the number of lines")
    var count: Bool = false

    @Argument(help: "Start line number (1-based)")
    var start: Int?

    @Argument(help: "End line number (inclusive, defaults to start)")
    var end: Int?

    @OptionGroup var input: InputOptions

    func validate() throws {
        if end != nil && start == nil {
            throw ValidationError("Cannot specify end without start")
        }
    }

    func run() async throws {
        let content = try input.readContent()
        let lines = LinesCommand.sourceLines(in: content)

        if count {
            print(lines.count)
            return
        }

        guard let start = start else {
            // No line number given, print all lines with numbers
            let width = String(lines.count).count
            for (i, line) in lines.enumerated() {
                let num = String(i + 1).leftPadded(toLength: width)
                print("\(num)  \(line)")
            }
            return
        }

        let end = end ?? start

        guard start >= 1, end >= start, end <= lines.count else {
            throw ValidationError("Line numbers must be in range 1...\(lines.count), got \(start)...\(end)")
        }

        for i in start...end {
            print(lines[i - 1])
        }
    }

    /// Split logical source lines without inventing an empty line after a final
    /// line ending. A retained carriage return keeps printed CRLF and lone-CR
    /// source bytes observable, matching this command's raw-line contract.
    private static func sourceLines(in content: String) -> [String] {
        guard !content.isEmpty else { return [] }

        var lines: [String] = []
        var current = ""
        for character in content {
            switch character {
            case "\n":
                lines.append(current)
                current = ""
            case "\r":
                current.append("\r")
                lines.append(current)
                current = ""
            case "\r\n":
                current.append("\r")
                lines.append(current)
                current = ""
            default:
                current.append(character)
            }
        }
        if !current.isEmpty {
            lines.append(current)
        }
        return lines
    }
}

private extension String {
    func leftPadded(toLength length: Int) -> String {
        if count >= length { return self }
        return String(repeating: " ", count: length - count) + self
    }
}
