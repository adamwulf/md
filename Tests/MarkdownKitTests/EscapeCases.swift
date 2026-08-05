//
//  EscapeCases.swift
//  md
//
//  Created by Adam Wulf on 8/4/26.
//

import Foundation
@testable import MarkdownKit

/// The sources that the backslash escape bug covers.
///
/// A test target cannot use the code of another test target, thus `CLITests` holds a
/// copy of this file. Change the two together.
enum EscapeCases {
    /// Each source is a single line, thus none of them depends on how a soft line
    /// break is kept.
    static let all: [String] = [
        "\\# not a heading",
        "\\- not a list",
        "\\* not emphasis \\*",
        "\\> not a quote",
        "\\+ not a list",
        "1\\. not a list",
        "1\\) not a list",
        "\\--- not a break",
        "C:\\\\path\\\\file",
        "\\[not a link\\]",
        "a \\_b\\_ c",
        "\\`not code\\`",
        "100\\% \\& more",
        "&amp;amp; literal",
        "\\~\\~not strike\\~\\~",
        "\\<https://example.com\\>",
        "\\!\\[not an image\\](url)",
        "\\![link](url)",
        "a *b* c",
        "a `code` c",
        "a [link](url) c",
        "a ~~strike~~ c",
        "snake_case_name here",
        "a < b and x <= y",
        "text with | pipe",
        "issue #42 is open",
    ]

    /// The text of every block, joined. Enough to show any change of the text, of the
    /// type of a block, or of the number of blocks.
    static func describe(_ blocks: [MarkdownBlock]) -> String {
        return blocks.map { block -> String in
            switch block {
            case .heading(let level, let text, _, _, _):
                return "h\(level):\(text)"
            case .paragraph(let text, _, _, _):
                return "p:\(text)"
            case .codeBlock(let language, let code, _, _, _):
                return "code(\(language ?? "")):\(code)"
            case .list(let items, _, _, _, _):
                return "list:" + items.map { "\($0.indentLevel)/\($0.text)" }.joined(separator: "|")
            case .blockquote(let text, _, _, _):
                return "quote:\(text)"
            case .thematicBreak:
                return "hr"
            case .table(let rows, _, _, _):
                return "table:" + rows.map { $0.joined(separator: "!") }.joined(separator: "|")
            }
        }.joined(separator: "\n")
    }
}
