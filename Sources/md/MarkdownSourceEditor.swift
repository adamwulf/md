//
//  MarkdownSourceEditor.swift
//  md
//
//  Created by Codex on 7/29/26.
//

import Foundation
import MarkdownKit

enum MarkdownSourceEditor {

    /// Replaces a zero-based range of parsed blocks without reformatting any
    /// source outside that range.
    ///
    /// The edit consumes the separators around the selected blocks and writes
    /// back one blank line between the replacement and each neighbouring body
    /// block. This retains the editing commands' established layout while
    /// preserving every unrelated source byte. A replacement at the end also
    /// keeps whether the original document had a final line ending.
    static func replacing(
        blocks blockRange: ClosedRange<Int>,
        in blocks: [MarkdownBlock],
        with replacement: String,
        within source: String
    ) -> String? {
        guard blockRange.lowerBound >= blocks.startIndex,
              blockRange.upperBound < blocks.endIndex else {
            return nil
        }

        let firstBlock = blocks[blockRange.lowerBound]
        guard let firstBlockStart = lineStartIndex(
            firstBlock.lineRange.lowerBound,
            in: source
        ) else {
            return nil
        }

        let previousBlock = blockRange.lowerBound > blocks.startIndex
            ? blocks[blockRange.lowerBound - 1]
            : nil
        let replacementStart: String.Index
        if previousBlock != nil {
            replacementStart = indexBeforeBlankLines(
                endingAt: firstBlockStart,
                in: source
            )
        } else {
            replacementStart = firstBlockStart
        }

        let lastBlock = blocks[blockRange.upperBound]
        guard let lastBlockEnd = indexAfterLineEnding(
            following: lastBlock.byteRange,
            in: source
        ) else {
            return nil
        }
        let replacementEnd = indexAfterBlankLines(
            startingAt: lastBlockEnd,
            in: source
        )

        guard replacementStart <= replacementEnd else {
            return nil
        }
        let hasFollowingSource = replacementEnd < source.endIndex

        let lineEnding = lineEnding(before: firstBlockStart, in: source)
            ?? firstLineEnding(in: source)
            ?? "\n"
        let normalizedReplacement = normalizeLineEndings(
            in: replacement,
            to: lineEnding
        ).trimmingTrailingLineEndings()

        var inserted = ""
        if normalizedReplacement.isEmpty {
            if previousBlock != nil && hasFollowingSource {
                inserted = lineEnding
            }
        } else {
            if previousBlock != nil {
                inserted += lineEnding
            }
            inserted += normalizedReplacement
            if hasFollowingSource {
                inserted += lineEnding + lineEnding
            } else if source.last?.isNewline == true {
                inserted += lineEnding
            }
        }

        var result = source
        result.replaceSubrange(replacementStart..<replacementEnd, with: inserted)
        return result
    }

    /// Inserts text at the beginning of the source line containing `block`.
    ///
    /// Block ranges come from the original source, so editing at that location
    /// preserves every byte outside the inserted text. Moving to the beginning
    /// of the line prevents leading indentation from becoming part of the new
    /// block.
    static func inserting(
        _ insertion: String,
        before block: MarkdownBlock,
        in source: String
    ) -> String? {
        guard let insertionIndex = lineStartIndex(
            block.lineRange.lowerBound,
            in: source
        ) else {
            return nil
        }

        let lineEnding = lineEnding(before: insertionIndex, in: source)
            ?? firstLineEnding(in: source)
            ?? "\n"
        let normalizedInsertion = normalizeLineEndings(
            in: insertion,
            to: lineEnding
        )

        var result = source
        result.insert(contentsOf: normalizedInsertion, at: insertionIndex)
        return result
    }

    /// Inserts after a parsed block, consuming only adjacent blank lines.
    /// Nonblank source that cmark does not model, such as raw HTML or a link
    /// reference definition, stays on the far side of the insertion.
    static func inserting(
        _ insertion: String,
        after block: MarkdownBlock,
        in source: String
    ) -> String? {
        guard let insertionStart = indexAfterLineEnding(
            following: block.byteRange,
            in: source
        ) else {
            return nil
        }
        let insertionEnd = indexAfterBlankLines(
            startingAt: insertionStart,
            in: source
        )

        let lineEnding = lineEnding(before: insertionStart, in: source)
            ?? firstLineEnding(in: source)
            ?? "\n"
        let normalizedInsertion = normalizeLineEndings(
            in: insertion,
            to: lineEnding
        ).trimmingTrailingLineEndings()
        guard !normalizedInsertion.isEmpty else {
            return source
        }

        let hasFollowingSource = insertionEnd < source.endIndex
        let hadFinalLineEnding = !hasFollowingSource
            && source.last?.isNewline == true
        var result = source
        let inserted: String
        if hasFollowingSource {
            inserted = lineEnding
                + normalizedInsertion
                + lineEnding
                + lineEnding
        } else {
            inserted = (hadFinalLineEnding
                ? lineEnding
                : lineEnding + lineEnding)
                + normalizedInsertion
                + (hadFinalLineEnding ? lineEnding : "")
        }
        result.replaceSubrange(insertionStart..<insertionEnd, with: inserted)
        return result
    }

    private static func lineEnding(
        before index: String.Index,
        in source: String
    ) -> String? {
        guard index > source.startIndex else {
            return nil
        }

        let previousIndex = source.index(before: index)
        let character = source[previousIndex]
        return character.isNewline ? String(character) : nil
    }

    private static func firstLineEnding(in source: String) -> String? {
        let bytes = source.utf8
        var index = bytes.startIndex

        while index < bytes.endIndex {
            if bytes[index] == 0x0A {
                return "\n"
            }
            if bytes[index] == 0x0D {
                let nextIndex = bytes.index(after: index)
                if nextIndex < bytes.endIndex && bytes[nextIndex] == 0x0A {
                    return "\r\n"
                }
                return "\r"
            }
            index = bytes.index(after: index)
        }

        return nil
    }

    /// Returns the source index directly after the line ending that follows a
    /// block. cmark ranges stop at the last content byte for most blocks, but
    /// for a list may already stop at the beginning of the following blank
    /// line. In the latter case the byte immediately before the range end is a
    /// newline, so the index is already the boundary wanted here.
    private static func indexAfterLineEnding(
        following byteRange: NSRange,
        in source: String
    ) -> String.Index? {
        let endOffset = NSMaxRange(byteRange)
        let bytes = source.utf8
        guard endOffset >= 0, endOffset <= bytes.count else {
            return nil
        }

        var index = bytes.index(bytes.startIndex, offsetBy: endOffset)
        if index > bytes.startIndex {
            let previous = bytes[bytes.index(before: index)]
            if previous == 0x0A || previous == 0x0D {
                return String.Index(index, within: source)
            }
        }

        if index < bytes.endIndex {
            if bytes[index] == 0x0D {
                index = bytes.index(after: index)
                if index < bytes.endIndex && bytes[index] == 0x0A {
                    index = bytes.index(after: index)
                }
            } else if bytes[index] == 0x0A {
                index = bytes.index(after: index)
            }
        }
        return String.Index(index, within: source)
    }

    /// Moves backward over blank lines immediately before a block, stopping
    /// at the first line that contains a non-whitespace character.
    private static func indexBeforeBlankLines(
        endingAt index: String.Index,
        in source: String
    ) -> String.Index {
        var boundary = index

        while boundary > source.startIndex {
            let endingIndex = source.index(before: boundary)
            guard source[endingIndex].isNewline else {
                break
            }

            var lineStart = endingIndex
            while lineStart > source.startIndex {
                let previous = source.index(before: lineStart)
                if source[previous].isNewline {
                    break
                }
                lineStart = previous
            }

            guard source[lineStart..<endingIndex].allSatisfy(\.isWhitespace) else {
                break
            }
            boundary = lineStart
        }

        return boundary
    }

    /// Moves forward over blank lines immediately after a block, stopping
    /// before any source that contains a non-whitespace character.
    private static func indexAfterBlankLines(
        startingAt index: String.Index,
        in source: String
    ) -> String.Index {
        var lineStart = index

        while lineStart < source.endIndex {
            var cursor = lineStart
            while cursor < source.endIndex {
                let character = source[cursor]
                if character.isNewline {
                    cursor = source.index(after: cursor)
                    break
                }
                guard character.isWhitespace else {
                    return lineStart
                }
                cursor = source.index(after: cursor)
            }
            lineStart = cursor
        }

        return lineStart
    }

    private static func normalizeLineEndings(
        in text: String,
        to lineEnding: String
    ) -> String {
        text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .replacingOccurrences(of: "\n", with: lineEnding)
    }

    /// Finds a 1-based line start without relying on parser character offsets.
    /// Scanning UTF-8 directly keeps CRLF pairs together and also supports
    /// documents that use lone CR or LF line endings.
    private static func lineStartIndex(
        _ lineNumber: Int,
        in source: String
    ) -> String.Index? {
        guard lineNumber >= 1 else {
            return nil
        }
        guard lineNumber > 1 else {
            return source.startIndex
        }

        let bytes = source.utf8
        var index = bytes.startIndex
        var currentLine = 1

        while index < bytes.endIndex {
            let byte = bytes[index]
            if byte == 0x0A {
                index = bytes.index(after: index)
                currentLine += 1
            } else if byte == 0x0D {
                index = bytes.index(after: index)
                if index < bytes.endIndex && bytes[index] == 0x0A {
                    index = bytes.index(after: index)
                }
                currentLine += 1
            } else {
                index = bytes.index(after: index)
                continue
            }

            if currentLine == lineNumber {
                return String.Index(index, within: source)
            }
        }

        return nil
    }
}

private extension String {
    func trimmingTrailingLineEndings() -> String {
        var result = self
        while result.last?.isNewline == true {
            result.removeLast()
        }
        return result
    }
}
