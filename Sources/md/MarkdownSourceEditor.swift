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
            } else if source.last?.isMarkdownLineEnding == true {
                inserted += lineEnding
            }
        }

        let replacementBlocks = MarkdownParser().parse(normalizedReplacement)
        let expectedBlockCount = blocks.count
            - blockRange.count
            + replacementBlocks.count
        let followingBlock = blockRange.upperBound + 1 < blocks.endIndex
            ? blocks[blockRange.upperBound + 1]
            : nil
        return replacingSubrangeWithoutLosingBlocks(
            replacementStart..<replacementEnd,
            with: inserted,
            in: source,
            expectedBlockCount: expectedBlockCount,
            allowedBlockMerges: allowedBoundaryMerges(
                previous: previousBlock,
                inserted: replacementBlocks,
                following: followingBlock
            ),
            lineEnding: lineEnding,
            canAddLeadingSeparator: previousBlock != nil,
            canAddTrailingSeparator: hasFollowingSource
        )
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
            && source.last?.isMarkdownLineEnding == true
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
        let parser = MarkdownParser()
        let documentBlocks = parser.parseDocument(source)
        let insertionBlocks = parser.parse(normalizedInsertion)
        let selectedIndex = documentBlocks.firstIndex {
            $0.byteRange == block.byteRange
        }
        let followingBlock = selectedIndex.flatMap { index in
            let nextIndex = index + 1
            return nextIndex < documentBlocks.endIndex
                ? documentBlocks[nextIndex]
                : nil
        }
        let expectedBlockCount = documentBlocks.count + insertionBlocks.count
        return replacingSubrangeWithoutLosingBlocks(
            insertionStart..<insertionEnd,
            with: inserted,
            in: source,
            expectedBlockCount: expectedBlockCount,
            allowedBlockMerges: allowedBoundaryMerges(
                previous: block,
                inserted: insertionBlocks,
                following: followingBlock
            ),
            lineEnding: lineEnding,
            canAddLeadingSeparator: true,
            canAddTrailingSeparator: hasFollowingSource
        )
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
        return character.isMarkdownLineEnding ? String(character) : nil
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
    /// block. cmark ranges stop before trailing source syntax for some blocks,
    /// including spaces and closing hashes on an ATX heading, so scan to the
    /// physical end of the line before consuming its ending. For a list the
    /// range may already stop at the following blank line; when the preceding
    /// byte is a newline, the index is already the boundary wanted here.
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

        while index < bytes.endIndex,
              bytes[index] != 0x0D,
              bytes[index] != 0x0A {
            index = bytes.index(after: index)
        }
        if index < bytes.endIndex && bytes[index] == 0x0D {
            index = bytes.index(after: index)
            if index < bytes.endIndex && bytes[index] == 0x0A {
                index = bytes.index(after: index)
            }
        } else if index < bytes.endIndex && bytes[index] == 0x0A {
            index = bytes.index(after: index)
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
            guard source[endingIndex].isMarkdownLineEnding else {
                break
            }

            var lineStart = endingIndex
            while lineStart > source.startIndex {
                let previous = source.index(before: lineStart)
                if source[previous].isMarkdownLineEnding {
                    break
                }
                lineStart = previous
            }

            guard source[lineStart..<endingIndex].allSatisfy(
                \.isCommonMarkBlankWhitespace
            ) else {
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
                if character.isMarkdownLineEnding {
                    cursor = source.index(after: cursor)
                    break
                }
                guard character.isCommonMarkBlankWhitespace else {
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

    /// Applies an edit only if the document keeps the expected number of
    /// parsed blocks. Try an extra separator on either side before refusing
    /// an edit whose new boundaries would merge otherwise unrelated blocks.
    private static func replacingSubrangeWithoutLosingBlocks(
        _ range: Range<String.Index>,
        with inserted: String,
        in source: String,
        expectedBlockCount: Int,
        allowedBlockMerges: Int,
        lineEnding: String,
        canAddLeadingSeparator: Bool,
        canAddTrailingSeparator: Bool
    ) -> String? {
        var candidates = [inserted]
        if canAddTrailingSeparator {
            candidates.append(inserted + lineEnding)
        }
        if canAddLeadingSeparator {
            candidates.append(lineEnding + inserted)
        }
        if canAddLeadingSeparator && canAddTrailingSeparator {
            candidates.append(lineEnding + inserted + lineEnding)
        }

        let parser = MarkdownParser()
        for candidate in candidates {
            var result = source
            result.replaceSubrange(range, with: candidate)
            let resultBlockCount = parser.parseDocument(result).count
            let minimumBlockCount = expectedBlockCount - allowedBlockMerges
            if resultBlockCount >= minimumBlockCount,
               resultBlockCount <= expectedBlockCount {
                return result
            }
        }
        return nil
    }

    /// Deleting a separator can intentionally join two blocks of the same
    /// kind (for example, two lists). Those joins are valid; absorption across
    /// different block kinds is not.
    private static func allowedBoundaryMerges(
        previous: MarkdownBlock?,
        inserted: [MarkdownBlock],
        following: MarkdownBlock?
    ) -> Int {
        if inserted.isEmpty {
            guard let previous, let following else {
                return 0
            }
            return previous.kind == following.kind ? 1 : 0
        }

        var result = 0
        if let previous, previous.kind == inserted.first?.kind {
            result += 1
        }
        if let following, following.kind == inserted.last?.kind {
            result += 1
        }
        return result
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
        while result.last?.isMarkdownLineEnding == true {
            result.removeLast()
        }
        return result
    }
}

private extension Character {
    var isMarkdownLineEnding: Bool {
        self == "\n" || self == "\r" || self == "\r\n"
    }

    var isCommonMarkBlankWhitespace: Bool {
        self == " " || self == "\t"
    }
}

private enum MarkdownBlockKind: Equatable {
    case heading
    case paragraph
    case codeBlock
    case list(ordered: Bool)
    case blockquote
    case thematicBreak
    case table
}

private extension MarkdownBlock {
    var kind: MarkdownBlockKind {
        switch self {
        case .heading:
            return .heading
        case .paragraph:
            return .paragraph
        case .codeBlock:
            return .codeBlock
        case .list(_, let ordered, _, _, _):
            return .list(ordered: ordered)
        case .blockquote:
            return .blockquote
        case .thematicBreak:
            return .thematicBreak
        case .table:
            return .table
        }
    }
}
