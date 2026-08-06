//
//  MarkdownParser.swift
//  md
//
//  Created by Adam Wulf on 4/12/26.
//

import Foundation
import cmark_gfm
import cmark_gfm_extensions

/// The checkbox that opens a task list item, such as `- [ ]` or `- [x]`.
///
/// The box is a marker on the item rather than part of its text, so it never
/// appears in `ListItem.text`.
public enum TaskState: Sendable, Equatable {
    case unchecked
    case checked
}

/// Represents a single item in a markdown list, with support for nested lists via indent levels
public struct ListItem: Sendable, Equatable {
    /// The markdown of the item, without its marker or checkbox.
    ///
    /// An item may hold more than one paragraph. Paragraphs are separated by a
    /// blank line, so `"a\n\nb"` is two paragraphs while `"a\nb"` is one
    /// paragraph that was soft wrapped.
    public let text: String
    public let indentLevel: Int
    public let ordered: Bool
    /// The checkbox this item opens with, or `nil` for an item that has none.
    public let task: TaskState?
    /// Whether the list holding this item is tight, meaning its items are not
    /// separated by blank lines. Like `ordered`, this describes the list the
    /// item belongs to, so a nested list can differ from its parent.
    public let tight: Bool
    /// Whether this entry continues the item before it rather than starting an
    /// item of its own.
    ///
    /// The array is flat, so an item cannot hold "text, a nested list, then
    /// more text": the nested items have to sit between the two paragraphs.
    /// The text after the nested list is therefore carried as its own entry,
    /// and this flag says that the author wrote no marker for it. It is
    /// written at the content indent of the item it continues, and whatever
    /// counts the items the author wrote skips it.
    ///
    /// Without the flag a continuation paragraph is indistinguishable from an
    /// item, so the document gains a bullet nobody wrote — a numbered STEP on
    /// an ordered list — and every edit by index lands one item out.
    public let continuation: Bool

    public init(
        text: String,
        indentLevel: Int,
        ordered: Bool,
        task: TaskState? = nil,
        tight: Bool = true,
        continuation: Bool = false
    ) {
        self.text = text
        self.indentLevel = indentLevel
        self.ordered = ordered
        self.task = task
        self.tight = tight
        self.continuation = continuation
    }
}

public extension Array where Element == ListItem {
    /// How many items the author wrote.
    ///
    /// Not `count`. The array also holds the continuations that a nested list
    /// split off, and those carry no marker of their own. Counting them tells
    /// the reader a list is longer than it is, and it makes every edit by
    /// index land one item out.
    var authoredCount: Int {
        lazy.filter { !$0.continuation }.count
    }
}

/// Represents a parsed block-level markdown element
public enum MarkdownBlock: Sendable {
    case heading(level: Int, text: String, charRange: NSRange, byteRange: NSRange, lineRange: ClosedRange<Int>)
    case paragraph(text: String, charRange: NSRange, byteRange: NSRange, lineRange: ClosedRange<Int>)
    case codeBlock(language: String?, code: String, charRange: NSRange, byteRange: NSRange, lineRange: ClosedRange<Int>)
    case list(items: [ListItem], ordered: Bool, charRange: NSRange, byteRange: NSRange, lineRange: ClosedRange<Int>)
    case blockquote(text: String, charRange: NSRange, byteRange: NSRange, lineRange: ClosedRange<Int>)
    case thematicBreak(charRange: NSRange, byteRange: NSRange, lineRange: ClosedRange<Int>)
    case table(rows: [[String]], charRange: NSRange, byteRange: NSRange, lineRange: ClosedRange<Int>)
    case htmlBlock(literal: String, charRange: NSRange, byteRange: NSRange, lineRange: ClosedRange<Int>)

    /// Character offset range (for text extraction and display)
    public var charRange: NSRange {
        switch self {
        case .heading(_, _, let charRange, _, _): return charRange
        case .paragraph(_, let charRange, _, _): return charRange
        case .codeBlock(_, _, let charRange, _, _): return charRange
        case .list(_, _, let charRange, _, _): return charRange
        case .blockquote(_, let charRange, _, _): return charRange
        case .thematicBreak(let charRange, _, _): return charRange
        case .table(_, let charRange, _, _): return charRange
        case .htmlBlock(_, let charRange, _, _): return charRange
        }
    }

    /// Byte offset range (for byte-based operations)
    public var byteRange: NSRange {
        switch self {
        case .heading(_, _, _, let byteRange, _): return byteRange
        case .paragraph(_, _, let byteRange, _): return byteRange
        case .codeBlock(_, _, _, let byteRange, _): return byteRange
        case .list(_, _, _, let byteRange, _): return byteRange
        case .blockquote(_, _, let byteRange, _): return byteRange
        case .thematicBreak(_, let byteRange, _): return byteRange
        case .table(_, _, let byteRange, _): return byteRange
        case .htmlBlock(_, _, let byteRange, _): return byteRange
        }
    }

    /// 1-based line range in the source document
    public var lineRange: ClosedRange<Int> {
        switch self {
        case .heading(_, _, _, _, let lineRange): return lineRange
        case .paragraph(_, _, _, let lineRange): return lineRange
        case .codeBlock(_, _, _, _, let lineRange): return lineRange
        case .list(_, _, _, _, let lineRange): return lineRange
        case .blockquote(_, _, _, let lineRange): return lineRange
        case .thematicBreak(_, _, let lineRange): return lineRange
        case .table(_, _, _, let lineRange): return lineRange
        case .htmlBlock(_, _, _, let lineRange): return lineRange
        }
    }
}

public struct MarkdownParser {
    public init() {}

    // MARK: - ASCII byte constants
    private static let newlineByte = UInt8(ascii: "\n")
    private static let crByte = UInt8(ascii: "\r")
    private static let spaceByte = UInt8(ascii: " ")
    private static let tabByte = UInt8(ascii: "\t")

    /// Pre-computed line information for efficient range calculations
    private struct LineInfo {
        let utf16Offset: Int
        let byteOffset: Int
        let content: String
        let isASCII: Bool
    }

    private struct RangePair {
        let charRange: NSRange
        let byteRange: NSRange
        let lineRange: ClosedRange<Int>
    }

    /// Parse markdown using cmark-gfm with extensions
    public func parse(_ markdown: String) -> [MarkdownBlock] {
        var blocks: [MarkdownBlock] = []
        let lineTable = buildLineTable(for: markdown)

        cmark_gfm_core_extensions_ensure_registered()

        let parser = cmark_parser_new(CMARK_OPT_DEFAULT)
        defer { cmark_parser_free(parser) }

        if let tableExt = cmark_find_syntax_extension("table") {
            cmark_parser_attach_syntax_extension(parser, tableExt)
        }
        if let strikethroughExt = cmark_find_syntax_extension("strikethrough") {
            cmark_parser_attach_syntax_extension(parser, strikethroughExt)
        }
        // Without this, cmark reads `- [ ] text` as an item whose text opens
        // with a bracket. Escaping that bracket is right for text and wrong
        // for a checkbox, so every task list would come back as `- \[ \]`.
        if let tasklistExt = cmark_find_syntax_extension("tasklist") {
            cmark_parser_attach_syntax_extension(parser, tasklistExt)
        }

        cmark_parser_feed(parser, markdown, markdown.utf8.count)
        let doc = cmark_parser_finish(parser)
        defer { cmark_node_free(doc) }

        var node = cmark_node_first_child(doc)
        while node != nil {
            if let block = parseNode(node, lineTable: lineTable) {
                blocks.append(block)
            }
            node = cmark_node_next(node)
        }

        return blocks
    }

    private func buildLineTable(for markdown: String) -> [LineInfo] {
        var table: [LineInfo] = []
        var currentUTF16Offset = 0
        var currentByteOffset = 0

        let bytes = Array(markdown.utf8)
        var byteIdx = 0
        let byteCount = bytes.count

        while byteIdx < byteCount {
            let lineStart = byteIdx
            var isASCII = true

            while byteIdx < byteCount && bytes[byteIdx] != Self.newlineByte && bytes[byteIdx] != Self.crByte {
                if bytes[byteIdx] >= 128 {
                    isASCII = false
                }
                byteIdx += 1
            }

            let lineBytes = Array(bytes[lineStart..<byteIdx])
            let lineContent = String(decoding: lineBytes, as: UTF8.self)
            table.append(LineInfo(utf16Offset: currentUTF16Offset, byteOffset: currentByteOffset, content: lineContent, isASCII: isASCII))

            let lineBytesCount = byteIdx - lineStart
            currentUTF16Offset += lineContent.utf16.count
            currentByteOffset += lineBytesCount
            if byteIdx < byteCount {
                let lineEndingLength: Int
                if bytes[byteIdx] == Self.crByte,
                   byteIdx + 1 < byteCount,
                   bytes[byteIdx + 1] == Self.newlineByte {
                    lineEndingLength = 2
                } else {
                    lineEndingLength = 1
                }
                currentUTF16Offset += lineEndingLength
                currentByteOffset += lineEndingLength
                byteIdx += lineEndingLength
            }
        }

        if table.isEmpty || (markdown.last?.isNewline == true) {
            table.append(LineInfo(utf16Offset: currentUTF16Offset, byteOffset: currentByteOffset, content: "", isASCII: true))
        }

        return table
    }

    private func parseNode(_ node: UnsafeMutablePointer<cmark_node>?, lineTable: [LineInfo]) -> MarkdownBlock? {
        guard let node = node else { return nil }

        let type = cmark_node_get_type(node)
        let htmlLiteral: String? = if type == CMARK_NODE_HTML_BLOCK {
            cmark_node_get_literal(node).map { String(cString: $0) } ?? ""
        } else {
            nil
        }
        let ranges = calculateRanges(
            for: node,
            lineTable: lineTable,
            trimTrailingBlankLines: type == CMARK_NODE_LIST,
            sourceLineCount: htmlLiteral.map(sourceLineCount)
        )

        switch type {
        case CMARK_NODE_HEADING:
            let level = Int(cmark_node_get_heading_level(node))
            // A heading is always one line, but a setext heading can use more than one
            // source line. Thus its lines join with a space.
            let text = getChildrenText(node, context: .heading).replacingOccurrences(of: "\n", with: " ")
            return .heading(level: level, text: text, charRange: ranges.charRange, byteRange: ranges.byteRange, lineRange: ranges.lineRange)

        case CMARK_NODE_PARAGRAPH:
            let text = getChildrenText(node, context: .paragraph)
            return .paragraph(text: text, charRange: ranges.charRange, byteRange: ranges.byteRange, lineRange: ranges.lineRange)

        case CMARK_NODE_CODE_BLOCK:
            let literal = cmark_node_get_literal(node)
            let code = literal.map { String(cString: $0) } ?? ""
            let fenceInfo = cmark_node_get_fence_info(node)
            let language = fenceInfo.map { String(cString: $0) }
            return .codeBlock(language: language, code: code, charRange: ranges.charRange, byteRange: ranges.byteRange, lineRange: ranges.lineRange)

        case CMARK_NODE_LIST:
            let ordered = cmark_node_get_list_type(node) == CMARK_ORDERED_LIST
            let items = collectListItems(from: node, indentLevel: 0, ordered: ordered, lineTable: lineTable)
            return .list(items: items, ordered: ordered, charRange: ranges.charRange, byteRange: ranges.byteRange, lineRange: ranges.lineRange)

        case CMARK_NODE_BLOCK_QUOTE:
            let text = getBlockquoteText(node)
            return .blockquote(text: text, charRange: ranges.charRange, byteRange: ranges.byteRange, lineRange: ranges.lineRange)

        case CMARK_NODE_THEMATIC_BREAK:
            return .thematicBreak(charRange: ranges.charRange, byteRange: ranges.byteRange, lineRange: ranges.lineRange)

        case CMARK_NODE_HTML_BLOCK:
            return .htmlBlock(
                literal: htmlLiteral ?? "",
                charRange: ranges.charRange,
                byteRange: ranges.byteRange,
                lineRange: ranges.lineRange
            )

        default:
            let typeName = String(cString: cmark_node_get_type_string(node))
            if typeName == "table" {
                return parseTable(node, ranges: ranges)
            }
            return nil
        }
    }

    private func parseTable(_ node: UnsafeMutablePointer<cmark_node>, ranges: RangePair) -> MarkdownBlock? {
        var rows: [[String]] = []
        var rowNode = cmark_node_first_child(node)
        while rowNode != nil {
            var row: [String] = []
            var cellNode = cmark_node_first_child(rowNode)
            while cellNode != nil {
                var cellContent = ""
                var child = cmark_node_first_child(cellNode)
                while child != nil {
                    cellContent += getNodeText(child, context: .tableCell)
                    child = cmark_node_next(child)
                }
                row.append(cellContent.trimmingCharacters(in: .whitespacesAndNewlines))
                cellNode = cmark_node_next(cellNode)
            }
            rows.append(row)
            rowNode = cmark_node_next(rowNode)
        }
        return .table(rows: rows, charRange: ranges.charRange, byteRange: ranges.byteRange, lineRange: ranges.lineRange)
    }

    /// The checkbox an item opens with, or `nil` for an item that has none.
    ///
    /// Whether the item HAS a box comes from cmark: the tasklist extension
    /// marks the item node and reports itself through the node type string,
    /// so a bracket that is merely text is never mistaken for a box.
    ///
    /// Whether the box is CHECKED is read from the source instead, because
    /// cmark gets it wrong. Upstream `tasklist.c` sets the flag with
    /// `strstr(input, "[x]")` over the whole line, so `- [ ] Ship it [x]
    /// today` is reported as checked and a task nobody finished comes back
    /// finished. The box opens the item content, so the first bracket pair on
    /// the item's own line is the box and anything later is text.
    private func taskState(of itemNode: UnsafeMutablePointer<cmark_node>, lineTable: [LineInfo]) -> TaskState? {
        guard let typeString = cmark_node_get_type_string(itemNode) else { return nil }
        guard String(cString: typeString) == "tasklist" else { return nil }

        let startLine = Int(cmark_node_get_start_line(itemNode))
        if startLine > 0, startLine <= lineTable.count,
           let box = firstCheckbox(in: lineTable[startLine - 1].content) {
            return box
        }
        // Defensive only. cmark gives every task item a start line inside the
        // source, and the box is on it, so neither guard above is expected to
        // fail. Keeping cmark's answer here loses the strstr fix rather than
        // the box itself, which is the better of the two ways to be wrong.
        return cmark_gfm_extensions_get_tasklist_item_checked(itemNode) ? .checked : .unchecked
    }

    /// The first `[ ]`, `[x]` or `[X]` on a line. Brackets holding anything
    /// else are ordinary text and are stepped over.
    private func firstCheckbox(in line: String) -> TaskState? {
        let characters = Array(line)
        guard characters.count >= 3 else { return nil }
        for index in 0...(characters.count - 3) where characters[index] == "[" && characters[index + 2] == "]" {
            switch characters[index + 1] {
            case " ": return .unchecked
            case "x", "X": return .checked
            default: continue
            }
        }
        return nil
    }

    private func collectListItems(
        from listNode: UnsafeMutablePointer<cmark_node>,
        indentLevel: Int,
        ordered: Bool,
        lineTable: [LineInfo]
    ) -> [ListItem] {
        var items: [ListItem] = []
        // cmark decides tightness for the whole list, counting both blank
        // lines between items and blank lines inside one item.
        let tight = cmark_node_get_list_tight(listNode) != 0
        var itemNode = cmark_node_first_child(listNode)

        while itemNode != nil {
            // A nested list splits its item into the piece before it and the
            // piece after it. The checkbox belongs to the piece holding the
            // item's first paragraph and to no other.
            var pendingTask = itemNode.flatMap { taskState(of: $0, lineTable: lineTable) }
            var paragraphs: [String] = []
            var child = cmark_node_first_child(itemNode)
            // The author wrote ONE marker for this item, and the first piece
            // to emit spends it. Every later piece is text that ran on after a
            // nested list, so it continues the item rather than starting one.
            var markerIsSpent = false
            // An item with no children at all is one the author wrote empty.
            // It holds nothing to gather, so the only flush it ever gets would
            // otherwise fall through the guard below and take the bullet with
            // it. That is different from a flush mid-item that has nothing to
            // say, which really should emit nothing.
            let itemIsEmpty = cmark_node_first_child(itemNode) == nil

            /// Emit everything gathered since the last nested list as one item.
            func flushGatheredText() {
                // Each child is its own paragraph, so they are joined by a
                // blank line. Running them together would weld the last word
                // of one onto the first word of the next.
                let text = paragraphs.joined(separator: "\n\n")
                let task = pendingTask
                // The box is spent here whether or not this piece emits: once
                // the first content position has passed it has had its turn.
                paragraphs = []
                pendingTask = nil
                // An empty piece is dropped, with two exceptions.
                //
                // A checkbox is state and is content in its own right, so an
                // item that is nothing but a box still has to survive.
                // Dropping it loses the box, and it orphans any nested list at
                // an indent that reads back as a code block.
                //
                // An item the author wrote empty is still an item. Dropping it
                // takes a bullet out of the list, and `format` writes the file,
                // so the line is gone for good after one run.
                guard !text.isEmpty || task != nil || itemIsEmpty else { return }
                items.append(ListItem(
                    text: text,
                    indentLevel: indentLevel,
                    ordered: ordered,
                    task: task,
                    tight: tight,
                    continuation: markerIsSpent
                ))
                // Spent by the piece that EMITS, not by the first flush. A
                // flush that emits nothing has written no marker, so the
                // marker is still the next piece's to use.
                markerIsSpent = true
            }

            while let currentChild = child {
                let childType = cmark_node_get_type(currentChild)

                if childType == CMARK_NODE_LIST {
                    let nestedOrdered = cmark_node_get_list_type(currentChild) == CMARK_ORDERED_LIST
                    let nestedItems = collectListItems(
                        from: currentChild,
                        indentLevel: indentLevel + 1,
                        ordered: nestedOrdered,
                        lineTable: lineTable
                    )
                    flushGatheredText()
                    items.append(contentsOf: nestedItems)
                } else {
                    // The children of a list item are whole blocks, thus each one
                    // comes back through the CommonMark writer with its backslashes.
                    let text = getNodeText(currentChild, context: .paragraph)
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    if !text.isEmpty {
                        paragraphs.append(text)
                    }
                }

                child = cmark_node_next(currentChild)
            }

            flushGatheredText()

            itemNode = cmark_node_next(itemNode)
        }

        return items
    }

    private func getChildrenText(_ node: UnsafeMutablePointer<cmark_node>?, context: InlineTextContext) -> String {
        guard let node = node else { return "" }
        var text = ""
        var child = cmark_node_first_child(node)
        while child != nil {
            text += getNodeText(child, context: context)
            child = cmark_node_next(child)
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Render a blockquote as a complete container, then remove its outer marker.
    ///
    /// Rendering child blocks independently loses their container context. In
    /// particular, cmark indents every list item after the first when handed an
    /// attached list node on its own, and the indent grows on every format pass.
    /// Rendering the quote keeps sibling items siblings and preserves the blank lines
    /// between complete child blocks. Removing exactly one quote marker leaves nested
    /// quotes and every other inner block marker intact.
    private func getBlockquoteText(_ node: UnsafeMutablePointer<cmark_node>?) -> String {
        guard let node else { return "" }
        let rendered = cmark_render_commonmark(node, 0, 0)
        defer { free(rendered) }
        guard let rendered else { return "" }

        var lines = String(cString: rendered)
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { line -> String in
                guard line.first == ">" else { return String(line) }
                var content = line.dropFirst()
                if content.first == " " {
                    content = content.dropFirst()
                }
                return String(content)
            }

        // cmark's writer terminates its output with a newline. The model stores the
        // block content rather than that terminator; BlockFormatter supplies it later.
        if lines.last?.isEmpty == true {
            lines.removeLast()
        }

        // For block types that require blank separation in CommonMark output
        // (raw HTML, fenced code, thematic breaks), cmark's container renderer
        // puts marker-only lines before the first child. They are writer syntax,
        // not authored quote content. Keeping them makes every format pass invent
        // two leading quoted lines, so discard them before storing the content.
        while lines.first?.isEmpty == true {
            lines.removeFirst()
        }
        return lines.joined(separator: "\n")
    }

    private func getNodeText(_ node: UnsafeMutablePointer<cmark_node>?, context: InlineTextContext) -> String {
        guard let node = node else { return "" }

        let type = cmark_node_get_type(node)
        if type == CMARK_NODE_TEXT {
            let literal = cmark_node_get_literal(node)
            guard let text = literal.map({ String(cString: $0) }) else { return "" }
            // `cmark` gives this text with each backslash already taken off. The text
            // goes back into a file, thus each marker that is live where it sits needs
            // its backslash again.
            let next = cmark_node_next(node)
            return MarkdownEscaper.escape(
                text,
                context: context,
                startsLine: beginsLine(node),
                endsBlock: next == nil,
                isFollowedByLink: cmark_node_get_type(next) == CMARK_NODE_LINK
            )
        }

        // A soft break is a single newline inside a block. Keep it, so a paragraph
        // written on more than one line keeps its line structure.
        if type == CMARK_NODE_SOFTBREAK {
            return "\n"
        }

        // A hard break is a break that a reader SHOWS, and a soft break is one that a
        // reader turns into a space. Thus a bare newline here would lose what the break
        // means, the same way a lost backslash loses what a marker means.
        //
        // Of the two spellings of a hard break, this writes the backslash. Two spaces at
        // the end of a line are invisible, and any tool that takes off trailing space
        // takes the break away with it.
        //
        // A heading is one line, and no spelling of a hard break lives inside an ATX
        // heading. Thus a heading takes the space that its lines join with.
        if type == CMARK_NODE_LINEBREAK {
            return context == .heading ? " " : "\\\n"
        }

        // Every other kind of node comes back through the CommonMark writer, thus it
        // is markdown source already, with the backslashes that it needs.
        let rendered = cmark_render_commonmark(node, 0, 0)
        defer { free(rendered) }

        if let rendered = rendered {
            return String(cString: rendered).trimmingCharacters(in: .whitespacesAndNewlines)
        }

        return ""
    }

    /// True when this node begins a line of its block: it is the first node, or a line
    /// break comes before it. A block marker is live only at the start of a line.
    private func beginsLine(_ node: UnsafeMutablePointer<cmark_node>) -> Bool {
        guard let previous = cmark_node_previous(node) else { return true }
        let previousType = cmark_node_get_type(previous)
        return previousType == CMARK_NODE_SOFTBREAK || previousType == CMARK_NODE_LINEBREAK
    }

    private func calculateRanges(
        for node: UnsafeMutablePointer<cmark_node>,
        lineTable: [LineInfo],
        trimTrailingBlankLines: Bool = false,
        sourceLineCount: Int? = nil
    ) -> RangePair {
        let startLine = Int(cmark_node_get_start_line(node))
        let startColumn = Int(cmark_node_get_start_column(node))
        var endLine = Int(cmark_node_get_end_line(node))
        var endColumn = Int(cmark_node_get_end_column(node))

        // cmark reports the end position of delimiter-terminated raw HTML
        // forms 1-5 before their closing delimiter line. Its literal contains
        // the complete block, so use that line count to reach the real source
        // end. The final line ending in the literal terminates the block but is
        // not an additional content line.
        if let sourceLineCount {
            let literalEndLine = startLine + Swift.max(1, sourceLineCount) - 1
            if literalEndLine > endLine {
                endLine = literalEndLine
                if endLine <= lineTable.count {
                    endColumn = lineTable[endLine - 1].content.utf8.count
                }
            }
        }

        guard startLine > 0 && startLine <= lineTable.count &&
              endLine > 0 && endLine <= lineTable.count else {
            return RangePair(charRange: NSRange(location: 0, length: 0), byteRange: NSRange(location: 0, length: 0), lineRange: 1...1)
        }

        // cmark extends a list through every blank line immediately below it.
        // Those lines separate the list from the next block and belong to no block,
        // so keep all three public ranges on the list's last content line instead.
        if trimTrailingBlankLines {
            var trimmed = false
            while endLine > startLine,
                  isCommonMarkBlankLine(lineTable[endLine - 1].content) {
                endLine -= 1
                trimmed = true
            }
            if trimmed {
                endColumn = lineTable[endLine - 1].content.utf8.count
            }
        }

        let startLineInfo = lineTable[startLine - 1]
        let startByteColumnOffset = startColumn - 1
        let startUTF16ColumnOffset = byteToUTF16Offset(startByteColumnOffset, in: startLineInfo)
        let startUTF16Index = startLineInfo.utf16Offset + startUTF16ColumnOffset
        let startByteIndex = startLineInfo.byteOffset + startByteColumnOffset

        let endLineInfo = lineTable[endLine - 1]
        let endByteColumnOffset = endColumn
        let endUTF16ColumnOffset = byteToUTF16Offset(endByteColumnOffset, in: endLineInfo)
        let endUTF16Index = endLineInfo.utf16Offset + endUTF16ColumnOffset
        let endByteIndex = endLineInfo.byteOffset + endByteColumnOffset

        let charRange = NSRange(location: startUTF16Index, length: Swift.max(0, endUTF16Index - startUTF16Index))
        let byteRange = NSRange(location: startByteIndex, length: Swift.max(0, endByteIndex - startByteIndex))

        return RangePair(charRange: charRange, byteRange: byteRange, lineRange: startLine...endLine)
    }

    /// Counts the same source line endings as `buildLineTable`: LF, CR, and
    /// CRLF as one ending. Other Unicode newline scalars are literal content
    /// to cmark and must not move a block onto the following source line.
    private func sourceLineCount(_ source: String) -> Int {
        let bytes = Array(source.utf8)
        var count = 1
        var index = 0
        while index < bytes.count {
            if bytes[index] == Self.crByte {
                count += 1
                index += 1
                if index < bytes.count && bytes[index] == Self.newlineByte {
                    index += 1
                }
            } else if bytes[index] == Self.newlineByte {
                count += 1
                index += 1
            } else {
                index += 1
            }
        }
        if bytes.last == Self.crByte || bytes.last == Self.newlineByte {
            count -= 1
        }
        return Swift.max(1, count)
    }

    /// CommonMark blank lines contain only ASCII spaces and tabs. Foundation's
    /// `.whitespaces` also includes NBSP, EM SPACE, and other authored Unicode
    /// content that cmark keeps inside the list's reported source range.
    private func isCommonMarkBlankLine(_ line: String) -> Bool {
        line.utf8.allSatisfy { byte in
            byte == Self.spaceByte || byte == Self.tabByte
        }
    }

    private func byteToUTF16Offset(_ byteOffset: Int, in lineInfo: LineInfo) -> Int {
        guard byteOffset > 0 else { return 0 }

        if lineInfo.isASCII {
            return min(byteOffset, lineInfo.content.utf16.count)
        }

        let utf8 = lineInfo.content.utf8
        let clampedOffset = min(byteOffset, utf8.count)
        let targetIndex = utf8.index(utf8.startIndex, offsetBy: clampedOffset)
        return lineInfo.content.utf16.distance(from: lineInfo.content.utf16.startIndex, to: targetIndex)
    }
}
