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
            let fence = fence(enclosing: code)
            output += "\(fence)\(lang)\n"
            output += code
            if !code.hasSuffix("\n") {
                output += "\n"
            }
            output += "\(fence)\n"

        case .list(let items, _, _, _, _):
            // The items are one flat array across every level of nesting, so
            // the level of the item before decides what a gap means.
            var previousLevel = -1
            var previousTight = true
            for (index, item) in items.enumerated() {
                // An item may not stand more than one level deeper than the
                // item before it. A wider jump writes an indent that reads
                // back as an indented code block instead of a nested list.
                // Clamping only ever pulls an item outwards, so the chain of
                // levels stays unbroken. `max(0,)` also keeps the count out of
                // negative territory, where `String(repeating:count:)` traps.
                let level = min(max(0, item.indentLevel), previousLevel + 1)

                if index > 0 {
                    // A loose list has a blank line between its items, and the
                    // gap belongs to the SHALLOWER of the two items around it.
                    // When this item is the deeper one the gap falls between a
                    // parent and its own sublist, so the parent's list decides.
                    // Asking the deeper item there would put a blank line
                    // inside the parent item and make the parent list loose,
                    // which gains a level of indent on every pass.
                    //
                    // A continuation always takes the blank line. It follows
                    // the nested list that split its item, and without the gap
                    // it reads back as one more line of that list.
                    let gapIsTight = item.continuation
                        ? false
                        : (level > previousLevel ? previousTight : item.tight)
                    if !gapIsTight {
                        output += "\n"
                    }
                }
                previousLevel = level
                previousTight = item.tight

                let indent = String(repeating: "    ", count: level)
                let marker = item.ordered ? "1." : "-"
                let checkbox = Self.checkboxPrefix(for: item.task)
                // Content begins after the marker and its one space, and every
                // line but the first lines up there. The checkbox stands
                // INSIDE that content and so moves nothing: counting its width
                // would put a line four columns past the content start, where
                // it becomes an indented code block.
                let contentIndent = String(repeating: " ", count: indent.count + marker.count + 1)
                let lines = item.text.split(separator: "\n", omittingEmptySubsequences: false)
                for (lineIndex, line) in lines.enumerated() {
                    if lineIndex == 0 && !item.continuation {
                        // The author wrote one marker for the item, and it goes
                        // here. A continuation has none, so all of its lines
                        // land at the content indent below.
                        //
                        // The space after the marker SEPARATES it from the
                        // content, so an item with no content at all does not
                        // get one: it would be trailing whitespace on a line
                        // with nothing to separate. A lone checkbox is content,
                        // and keeps both the space and the box's own.
                        let content = "\(checkbox)\(line)"
                        output += content.isEmpty
                            ? "\(indent)\(marker)\n"
                            : "\(indent)\(marker) \(content)\n"
                    } else if line.isEmpty {
                        // A blank line carries no indent, or it would be
                        // trailing whitespace.
                        output += "\n"
                    } else {
                        output += "\(contentIndent)\(line)\n"
                    }
                }
            }

        case .blockquote(let text, _, _, _):
            let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
            for line in lines {
                output += line.isEmpty ? ">\n" : "> \(line)\n"
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

        case .htmlBlock(let literal, _, _, _):
            output += literal
            if !literal.hasSuffix("\n") {
                output += "\n"
            }
        }

        return output
    }

    /// The fence that encloses code without being closed by it.
    ///
    /// A fenced code block ends at the first line holding a run of backticks
    /// at least as long as the opening fence, so a three backtick fence around
    /// code that itself holds three backticks closes early. The block then
    /// reads back as an empty code block, a paragraph, and a second empty code
    /// block: one block becomes three, and the code becomes prose.
    ///
    /// Counting every run, and not only the runs that begin a line, costs one
    /// backtick in a rare case and cannot be wrong.
    private static func fence(enclosing code: String) -> String {
        var longestRun = 0
        var currentRun = 0
        for character in code {
            if character == "`" {
                currentRun += 1
                longestRun = max(longestRun, currentRun)
            } else {
                currentRun = 0
            }
        }
        return String(repeating: "`", count: max(3, longestRun + 1))
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
