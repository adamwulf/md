//
//  MarkdownSourceEditor.swift
//  md
//
//  Created by Codex on 7/29/26.
//

import Foundation
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
        guard let blockRange = Range(block.charRange, in: source) else {
            return nil
        }

        var insertionIndex = blockRange.lowerBound
        while insertionIndex > source.startIndex {
            let previousIndex = source.index(before: insertionIndex)
            if source[previousIndex].isNewline {
                break
            }
            insertionIndex = previousIndex
        }

        var result = source
        result.insert(contentsOf: insertion, at: insertionIndex)
        return result
    }
}
