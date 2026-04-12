//
//  BlockFormatter.swift
//  md
//
//  Created by Adam Wulf on 4/12/26.
//

import Foundation
import MarkdownKit

enum BlockFormatter {
    /// Format a single MarkdownBlock back into normalized markdown text.
    static func format(_ block: MarkdownBlock) -> String {
        var output = ""

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

            output += "| \(header.joined(separator: " | ")) |\n"
            output += "| \(colWidths.map { String(repeating: "-", count: max($0, 3)) }.joined(separator: " | ")) |\n"
            for row in rows.dropFirst() {
                output += "| \(row.joined(separator: " | ")) |\n"
            }
        }

        return output
    }

    /// Format an array of MarkdownBlocks into normalized markdown text.
    static func format(_ blocks: [MarkdownBlock]) -> String {
        var output = ""
        for (index, block) in blocks.enumerated() {
            if index > 0 {
                output += "\n"
            }
            output += format(block)
        }
        return output
    }
}
