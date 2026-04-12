//
//  FmtCommand.swift
//  md
//
//  Created by Adam Wulf on 4/12/26.
//

import ArgumentParser
import Foundation
import MarkdownKit

struct FormatCommand: AsyncParsableCommand {

    static var configuration = CommandConfiguration(
        commandName: "format",
        abstract: "Parse and normalize a markdown file"
    )

    @Argument(help: "Path to the markdown file to format")
    var file: String

    func run() async throws {
        let url = URL(fileURLWithPath: file)
        let content = try String(contentsOf: url, encoding: .utf8)
        let parser = MarkdownParser()
        let blocks = parser.parse(content)

        var output = ""

        for (index, block) in blocks.enumerated() {
            if index > 0 {
                output += "\n"
            }

            switch block {
            case .heading(let level, let text, _, _, _):
                let prefix = String(repeating: "#", count: level)
                output += "\(prefix) \(text)\n"

            case .paragraph(let text, _, _, _):
                output += "\(text)\n"

            case .codeBlock(let language, let code, _, _, _):
                let lang = language ?? ""
                output += "```\(lang)\n"
                output += code
                if !code.hasSuffix("\n") {
                    output += "\n"
                }
                output += "```\n"

            case .list(let items, _, _, _, _):
                for item in items {
                    let indent = String(repeating: "    ", count: item.indentLevel)
                    let marker = item.ordered ? "1." : "-"
                    output += "\(indent)\(marker) \(item.text)\n"
                }

            case .blockquote(let text, _, _, _):
                let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
                for line in lines {
                    output += "> \(line)\n"
                }

            case .thematicBreak(_, _, _):
                output += "---\n"

            case .table(let rows, _, _, _):
                guard let header = rows.first else { break }
                let colWidths = header.map { $0.count }

                // Header row
                output += "| \(header.joined(separator: " | ")) |\n"
                // Separator row
                output += "| \(colWidths.map { String(repeating: "-", count: max($0, 3)) }.joined(separator: " | ")) |\n"
                // Data rows
                for row in rows.dropFirst() {
                    output += "| \(row.joined(separator: " | ")) |\n"
                }
            }
        }

        print(output, terminator: "")
    }
}
