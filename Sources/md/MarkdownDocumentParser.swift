//
//  MarkdownDocumentParser.swift
//  md
//
//  Created by Adam Wulf on 5/3/26.
//

import Foundation
import MarkdownKit

extension MarkdownParser {

    /// Parse markdown content as a "document" — i.e., skip any leading
    /// frontmatter (YAML `---`, TOML `+++`, JSON `;;;`) before block parsing.
    ///
    /// Without this, cmark-gfm sees `---` as a thematic break and the YAML
    /// body that follows as a setext heading; `+++` and `;;;` similarly fold
    /// into spurious paragraphs. Returned blocks have `lineRange`, `byteRange`,
    /// and `charRange` adjusted so they refer to positions in the original
    /// (unstripped) `content`.
    func parseDocument(_ content: String) -> [MarkdownBlock] {
        guard let frontmatter = Frontmatter.parse(content) else {
            return parse(content)
        }
        let bodyBlocks = parse(frontmatter.body)
        let byteOffset = content.utf8.count - frontmatter.body.utf8.count
        let charOffset = content.utf16.count - frontmatter.body.utf16.count
        let lineOffset = content.components(separatedBy: "\n").count
            - frontmatter.body.components(separatedBy: "\n").count
        return bodyBlocks.map { block in
            block.shifted(byteOffset: byteOffset, charOffset: charOffset, lineOffset: lineOffset)
        }
    }
}

private extension MarkdownBlock {
    func shifted(byteOffset: Int, charOffset: Int, lineOffset: Int) -> MarkdownBlock {
        let newByte = NSRange(location: byteRange.location + byteOffset, length: byteRange.length)
        let newChar = NSRange(location: charRange.location + charOffset, length: charRange.length)
        let newLines = (lineRange.lowerBound + lineOffset)...(lineRange.upperBound + lineOffset)
        switch self {
        case .heading(let level, let text, _, _, _):
            return .heading(level: level, text: text, charRange: newChar, byteRange: newByte, lineRange: newLines)
        case .paragraph(let text, _, _, _):
            return .paragraph(text: text, charRange: newChar, byteRange: newByte, lineRange: newLines)
        case .codeBlock(let language, let code, _, _, _):
            return .codeBlock(language: language, code: code, charRange: newChar, byteRange: newByte, lineRange: newLines)
        case .list(let items, let ordered, _, _, _):
            return .list(items: items, ordered: ordered, charRange: newChar, byteRange: newByte, lineRange: newLines)
        case .blockquote(let text, _, _, _):
            return .blockquote(text: text, charRange: newChar, byteRange: newByte, lineRange: newLines)
        case .thematicBreak:
            return .thematicBreak(charRange: newChar, byteRange: newByte, lineRange: newLines)
        case .table(let rows, _, _, _):
            return .table(rows: rows, charRange: newChar, byteRange: newByte, lineRange: newLines)
        }
    }
}
