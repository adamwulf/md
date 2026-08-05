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
            // An item holding more than one paragraph makes the whole list
            // loose, and a loose list puts a blank line between every item.
            // Writing them back to back would close the gap the author left.
            let loose = items.contains { $0.text.contains("\n\n") }
            for (index, item) in items.enumerated() {
                if loose && index > 0 {
                    output += "\n"
                }
                let indent = String(repeating: "    ", count: item.indentLevel)
                let marker = item.ordered ? "1." : "-"
                let checkbox = Self.checkbox(for: item.task)
                // Continuation lines line up under the item CONTENT, which
                // begins after the marker and the one space that follows it.
                // The checkbox stands INSIDE that content, so it moves
                // nothing: counting its width too would push a continuation
                // four columns past the content start, where it stops being a
                // paragraph and becomes an indented code block.
                let continuation = String(repeating: " ", count: indent.count + marker.count + 1)
                let lines = item.text.split(separator: "\n", omittingEmptySubsequences: false)
                for (lineIndex, line) in lines.enumerated() {
                    if lineIndex == 0 {
                        output += "\(indent)\(marker) \(checkbox)\(line)\n"
                    } else if line.isEmpty {
                        // A blank line carries no indent, or it would be
                        // trailing whitespace.
                        output += "\n"
                    } else {
                        output += "\(continuation)\(line)\n"
                    }
                }
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

    /// The checkbox that opens a task list item, written so that it reads back
    /// as the same checkbox. An item with no checkbox contributes nothing, so
    /// a plain item is untouched by task list support.
    private static func checkbox(for task: TaskState?) -> String {
        switch task {
        case .none: return ""
        case .unchecked: return "[ ] "
        case .checked: return "[x] "
        }
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
