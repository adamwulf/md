//
//  MarkdownSourceEditor.swift
//  md
//
//  Created by Codex on 7/29/26.
//

import MarkdownKit

enum MarkdownSourceEditor {

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

        var result = source
        result.insert(contentsOf: insertion, at: insertionIndex)
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
