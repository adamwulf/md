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
            for (index, item) in items.enumerated() {
                // A loose list has a blank line between its items. Tightness
                // travels on the item, so a loose sublist does not loosen the
                // parent it sits in.
                if !item.tight && index > 0 {
                    output += "\n"
                }
                // `String(repeating:count:)` traps on a negative count, so a
                // malformed item must not be able to bring the process down.
                let indent = String(repeating: "    ", count: max(0, item.indentLevel))
                let marker = item.ordered ? "1." : "-"
                let checkbox = Self.checkboxPrefix(for: item.task)
                // Continuation lines line up under the item content, which
                // begins after the marker and its one space. The checkbox
                // stands inside that content and so moves nothing: counting
                // its width would put a continuation four columns past the
                // content start, where it becomes an indented code block.
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

    /// The checkbox that opens a task list item, followed by the space that
    /// separates it from the item text. An item with no checkbox contributes
    /// the empty string, so nothing is written and no separator is added.
    ///
    /// The trailing space is part of the box as cmark reads it: `- [ ]` with
    /// nothing after it is not a task item at all, so an item that is only a
    /// box needs the space to survive a round trip.
    private static func checkboxPrefix(for task: TaskState?) -> String {
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
