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
    /// The marker value that starts this ordered list, or `nil` when this
    /// entry continues a list that has already started.
    ///
    /// List items are flattened across nesting levels, so keeping the start
    /// on the first item of each list preserves both top-level and nested
    /// starts without requiring a separate nested-list model.
    public let orderedListStart: Int?
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
        self.init(
            text: text,
            indentLevel: indentLevel,
            ordered: ordered,
            orderedListStart: nil,
            task: task,
            tight: tight,
            continuation: continuation
        )
    }

    public init(
        text: String,
        indentLevel: Int,
        ordered: Bool,
        orderedListStart: Int?,
        task: TaskState? = nil,
        tight: Bool = true,
        continuation: Bool = false
    ) {
        self.text = text
        self.indentLevel = indentLevel
        self.ordered = ordered
        self.orderedListStart = orderedListStart
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
    /// A link reference definition such as `[ref]: /url`, or a run of adjacent
    /// ones, recovered from the source text. cmark consumes a definition into
    /// the document's reference map and leaves no node in the tree, so the
    /// parser reads it back out of the lines no other block covers.
    case linkReferenceDefinition(text: String, charRange: NSRange, byteRange: NSRange, lineRange: ClosedRange<Int>)

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
        case .linkReferenceDefinition(_, let charRange, _, _): return charRange
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
        case .linkReferenceDefinition(_, _, let byteRange, _): return byteRange
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
        case .linkReferenceDefinition(_, _, _, let lineRange): return lineRange
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

        // cmark consumes each link reference definition into the document's
        // reference map and leaves no node, so the definitions have to come
        // back out of the source before the tree is walked. It also resolves
        // each link that used one, so those links are pinned to their authored
        // spelling before the resolved URL can be pasted inline.
        let definitions = consumedLinkReferenceDefinitions(in: doc, lineTable: lineTable)
        restoreReferenceStyleLinks(in: doc, labels: definitions.labels, lineTable: lineTable)

        var node = cmark_node_first_child(doc)
        while node != nil {
            if let block = parseNode(node, lineTable: lineTable, itemDefinitions: definitions.byItem) {
                blocks.append(block)
            }
            node = cmark_node_next(node)
        }

        return merged(blocks, with: definitions.topLevel)
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

    private func parseNode(
        _ node: UnsafeMutablePointer<cmark_node>?,
        lineTable: [LineInfo],
        itemDefinitions: [UInt: [ItemDefinition]] = [:]
    ) -> MarkdownBlock? {
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
            let items = collectListItems(
                from: node,
                indentLevel: 0,
                ordered: ordered,
                lineTable: lineTable,
                itemDefinitions: itemDefinitions
            )
            return .list(items: items, ordered: ordered, charRange: ranges.charRange, byteRange: ranges.byteRange, lineRange: ranges.lineRange)

        case CMARK_NODE_BLOCK_QUOTE:
            let text = getBlockquoteText(
                lineRange: ranges.lineRange,
                lineTable: lineTable
            )
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
        lineTable: [LineInfo],
        itemDefinitions: [UInt: [ItemDefinition]] = [:]
    ) -> [ListItem] {
        var items: [ListItem] = []
        // cmark decides tightness for the whole list, counting both blank
        // lines between items and blank lines inside one item.
        let tight = cmark_node_get_list_tight(listNode) != 0 &&
            !formattingRequiresLooseList(listNode)
        let orderedListStart = ordered ? Int(cmark_node_get_list_start(listNode)) : nil
        var isFirstItem = true
        var itemNode = cmark_node_first_child(listNode)

        while itemNode != nil {
            let itemOrderedListStart = isFirstItem ? orderedListStart : nil
            // A nested list splits its item into the piece before it and the
            // piece after it. The checkbox belongs to the piece holding the
            // item's first paragraph and to no other.
            var pendingTask = itemNode.flatMap { taskState(of: $0, lineTable: lineTable) }
            let itemStartLine = itemNode.map { Int(cmark_node_get_start_line($0)) } ?? 0
            var paragraphs: [String] = []
            // The definitions cmark consumed out of this item, in line order.
            // Each goes back among the item's paragraphs where it was written.
            var pendingDefinitions = itemNode
                .flatMap { itemDefinitions[UInt(bitPattern: $0)] } ?? []
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
            func flushGatheredText(preservingEmptyParentMarker: Bool = false) {
                // Each child is its own paragraph, so they are joined by a
                // blank line. Running them together would weld the last word
                // of one onto the first word of the next. The one exception is
                // a checkbox-only paragraph followed immediately by another
                // block. cmark removes the checkbox from that empty paragraph,
                // but its line still has to survive so the following block is
                // not pulled onto the checkbox line.
                let text: String
                if pendingTask != nil, paragraphs.first?.isEmpty == true {
                    let followingBlocks = paragraphs.dropFirst()
                    text = followingBlocks.isEmpty
                        ? ""
                        : "\n" + followingBlocks.joined(separator: "\n\n")
                } else {
                    text = paragraphs.joined(separator: "\n\n")
                }
                let task = pendingTask
                // The box is spent here whether or not this piece emits: once
                // the first content position has passed it has had its turn.
                paragraphs = []
                pendingTask = nil
                // An empty piece is dropped, with three exceptions.
                //
                // A checkbox is state and is content in its own right, so an
                // item that is nothing but a box still has to survive.
                // Dropping it loses the box, and it orphans any nested list at
                // an indent that reads back as a code block.
                //
                // An item the author wrote empty is still an item. Dropping it
                // takes a bullet out of the list, and `format` writes the file,
                // so the line is gone for good after one run.
                //
                // A parent whose first child is itself a list also has no text
                // to gather, but its marker owns that nested list. Preserve the
                // empty parent before flattening its children or they are
                // promoted one level and both list starts change meaning.
                guard !text.isEmpty
                    || task != nil
                    || itemIsEmpty
                    || preservingEmptyParentMarker
                else { return }
                items.append(ListItem(
                    text: text,
                    indentLevel: indentLevel,
                    ordered: ordered,
                    orderedListStart: markerIsSpent ? nil : itemOrderedListStart,
                    task: task,
                    tight: tight,
                    continuation: markerIsSpent
                ))
                // Spent by the piece that EMITS, not by the first flush. A
                // flush that emits nothing has written no marker, so the
                // marker is still the next piece's to use.
                markerIsSpent = true
            }

            /// Put back each consumed definition that the author wrote above
            /// `line`, or all of them when no more children follow.
            func appendDefinitions(before line: Int?) {
                while let definition = pendingDefinitions.first,
                      line.map({ definition.startLine < $0 }) ?? true {
                    paragraphs.append(definition.text)
                    pendingDefinitions.removeFirst()
                }
            }

            while let currentChild = child {
                let childType = cmark_node_get_type(currentChild)
                appendDefinitions(before: Int(cmark_node_get_start_line(currentChild)))

                if childType == CMARK_NODE_LIST {
                    let nestedOrdered = cmark_node_get_list_type(currentChild) == CMARK_ORDERED_LIST
                    let nestedItems = collectListItems(
                        from: currentChild,
                        indentLevel: indentLevel + 1,
                        ordered: nestedOrdered,
                        lineTable: lineTable,
                        itemDefinitions: itemDefinitions
                    )
                    flushGatheredText(preservingEmptyParentMarker: !markerIsSpent)
                    items.append(contentsOf: nestedItems)
                } else {
                    // The children of a list item are whole blocks, thus each one
                    // comes back through the CommonMark writer with its backslashes.
                    // Blockquotes are the exception: cmark's writer loses blank
                    // quote lines and invents separators before raw HTML. Recover
                    // their authored structure the same way as a top-level quote,
                    // then put back the one marker that belongs inside the list.
                    if pendingTask != nil,
                       paragraphs.isEmpty,
                       Int(cmark_node_get_start_line(currentChild)) > itemStartLine {
                        paragraphs.append("")
                    }
                    let text: String
                    if childType == CMARK_NODE_BLOCK_QUOTE {
                        let quoteRanges = calculateRanges(
                            for: currentChild,
                            lineTable: lineTable
                        )
                        let innerText = getBlockquoteText(
                            lineRange: quoteRanges.lineRange,
                            lineTable: lineTable,
                            nestedInList: true
                        )
                        text = blockquoteSource(from: innerText)
                    } else if childType == CMARK_NODE_THEMATIC_BREAK {
                        // cmark renders this as five dashes. Once the list
                        // formatter adds its own dash marker, `- -----`
                        // reparses as one outer thematic break instead of a
                        // list item containing a break. Asterisks retain the
                        // child block unambiguously at every list depth.
                        text = "***"
                    } else if childType == CMARK_NODE_HEADING,
                              pendingTask != nil,
                              cmark_node_get_heading_level(currentChild) <= 2 {
                        // An ATX marker placed after a task checkbox is ordinary
                        // item text (`- [x] # title`), not a heading. A level-one
                        // or level-two task-item heading can round-trip in setext
                        // form while leaving the checkbox where the task-list
                        // extension requires it.
                        text = taskListHeadingSource(currentChild)
                    } else {
                        text = getNodeText(currentChild, context: .paragraph)
                    }
                    let trimmedText = text
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmedText.isEmpty {
                        paragraphs.append(trimmedText)
                    } else if childType == CMARK_NODE_PARAGRAPH,
                              pendingTask != nil,
                              paragraphs.isEmpty {
                        paragraphs.append("")
                    }
                }

                child = cmark_node_next(currentChild)
            }

            appendDefinitions(before: nil)
            flushGatheredText()

            isFirstItem = false
            itemNode = cmark_node_next(itemNode)
        }

        return items
    }

    private func taskListHeadingSource(_ node: UnsafeMutablePointer<cmark_node>) -> String {
        let level = Int(cmark_node_get_heading_level(node))
        let text = getChildrenText(node, context: .heading)
            .replacingOccurrences(of: "\n", with: " ")
        // Setext headings require content. The preserved checkbox-only line
        // already keeps this child on its own continuation line, where an
        // empty ATX marker remains an empty heading on every parse.
        if text.isEmpty {
            return String(repeating: "#", count: level)
        }
        let underline = level == 1 ? "===" : "-"
        return "\(text)\n\(underline)"
    }

    /// Formatting two adjacent non-list child blocks, or a continuation block
    /// after a nested list, requires a blank line so the blocks do not merge.
    /// That blank makes the containing list loose on the next parse, even when
    /// the original source omitted it. Mark the list loose now so the first
    /// format pass already emits the same inter-item gaps as later passes.
    private func formattingRequiresLooseList(
        _ listNode: UnsafeMutablePointer<cmark_node>
    ) -> Bool {
        var itemNode = cmark_node_first_child(listNode)
        while let item = itemNode {
            var consecutiveNonListBlocks = 0
            var sawNestedList = false
            var child = cmark_node_first_child(item)
            while let currentChild = child {
                if cmark_node_get_type(currentChild) == CMARK_NODE_LIST {
                    sawNestedList = true
                    consecutiveNonListBlocks = 0
                } else {
                    if sawNestedList {
                        return true
                    }
                    consecutiveNonListBlocks += 1
                    if consecutiveNonListBlocks > 1 {
                        return true
                    }
                }
                child = cmark_node_next(currentChild)
            }
            itemNode = cmark_node_next(item)
        }
        return false
    }

    // MARK: - Link reference definitions

    /// One link reference definition put back inside the list item that held
    /// it, at the line the author wrote it on.
    private struct ItemDefinition {
        let startLine: Int
        let text: String
    }

    /// Every link reference definition cmark consumed while parsing, read
    /// back out of the source.
    private struct ConsumedDefinitions {
        /// Definitions at the top level of the document, as finished blocks
        /// in line order.
        let topLevel: [MarkdownBlock]
        /// Definitions that sat inside a list item, keyed by the item node's
        /// address.
        let byItem: [UInt: [ItemDefinition]]
        /// The normalized label of every definition found, for deciding which
        /// links were written in reference style.
        let labels: Set<String>
    }

    /// Find the definitions by what they leave behind: a definition is the
    /// only block construct that puts no node in the tree, so every nonblank
    /// source line that no node covers belongs to one. A blockquote or table
    /// covers its whole range, because its text is recovered from source; a
    /// list covers only what its items' children cover, so a definition
    /// inside an item is found the same way as one at the top level.
    private func consumedLinkReferenceDefinitions(
        in doc: UnsafeMutablePointer<cmark_node>?,
        lineTable: [LineInfo]
    ) -> ConsumedDefinitions {
        var covered = [Bool](repeating: false, count: lineTable.count)
        markContentLines(of: doc, lineTable: lineTable, covered: &covered)

        var spans: [ClosedRange<Int>] = []
        var line = 1
        while line <= lineTable.count {
            if covered[line - 1] || isCommonMarkBlankLine(lineTable[line - 1].content) {
                line += 1
                continue
            }
            var end = line
            while end < lineTable.count,
                  !covered[end],
                  !isCommonMarkBlankLine(lineTable[end].content) {
                end += 1
            }
            spans.append(line...end)
            line = end + 1
        }

        var itemRanges: [(key: UInt, range: ClosedRange<Int>)] = []
        collectItemRanges(of: doc, into: &itemRanges)

        var topLevel: [MarkdownBlock] = []
        var byItem: [UInt: [ItemDefinition]] = [:]
        var labels: Set<String> = []
        for span in spans {
            // The innermost item holding the whole span owns it. Item ranges
            // nest or stand apart, so the shortest containing range is the
            // deepest.
            let owner = itemRanges
                .filter { $0.range.contains(span.lowerBound) && $0.range.contains(span.upperBound) }
                .min { $0.range.count < $1.range.count }
            if let owner {
                guard let text = itemDefinitionText(
                    for: span,
                    itemStartLine: owner.range.lowerBound,
                    lineTable: lineTable
                ), isDefinitionShaped(text) else { continue }
                byItem[owner.key, default: []].append(ItemDefinition(startLine: span.lowerBound, text: text))
                labels.formUnion(definitionLabels(in: text))
            } else {
                let text = span.map { lineTable[$0 - 1].content }.joined(separator: "\n")
                guard isDefinitionShaped(text) else { continue }
                let startInfo = lineTable[span.lowerBound - 1]
                let endInfo = lineTable[span.upperBound - 1]
                topLevel.append(.linkReferenceDefinition(
                    text: text,
                    charRange: NSRange(
                        location: startInfo.utf16Offset,
                        length: endInfo.utf16Offset + endInfo.content.utf16.count - startInfo.utf16Offset
                    ),
                    byteRange: NSRange(
                        location: startInfo.byteOffset,
                        length: endInfo.byteOffset + endInfo.content.utf8.count - startInfo.byteOffset
                    ),
                    lineRange: span
                ))
                labels.formUnion(definitionLabels(in: text))
            }
        }
        return ConsumedDefinitions(topLevel: topLevel, byItem: byItem, labels: labels)
    }

    /// Mark the lines whose bytes some node in the tree carries. Lists and
    /// items are containers, so only their children cover lines: what an item
    /// spans beyond its children is exactly what a consumed definition left
    /// behind.
    private func markContentLines(
        of node: UnsafeMutablePointer<cmark_node>?,
        lineTable: [LineInfo],
        covered: inout [Bool]
    ) {
        var child = cmark_node_first_child(node)
        while let current = child {
            let type = cmark_node_get_type(current)
            if type == CMARK_NODE_LIST || type == CMARK_NODE_ITEM {
                markContentLines(of: current, lineTable: lineTable, covered: &covered)
            } else {
                let startLine = Int(cmark_node_get_start_line(current))
                var endLine = Int(cmark_node_get_end_line(current))
                if type == CMARK_NODE_HTML_BLOCK {
                    // cmark reports delimiter-terminated raw HTML short of its
                    // closing line; repair it the way calculateRanges does.
                    let literal = cmark_node_get_literal(current).map { String(cString: $0) } ?? ""
                    endLine = Swift.max(endLine, startLine + Swift.max(1, sourceLineCount(literal)) - 1)
                }
                if startLine >= 1, startLine <= lineTable.count {
                    for line in startLine...Swift.min(Swift.max(endLine, startLine), lineTable.count) {
                        covered[line - 1] = true
                    }
                }
            }
            child = cmark_node_next(current)
        }
    }

    private func collectItemRanges(
        of node: UnsafeMutablePointer<cmark_node>?,
        into itemRanges: inout [(key: UInt, range: ClosedRange<Int>)]
    ) {
        var child = cmark_node_first_child(node)
        while let current = child {
            if cmark_node_get_type(current) == CMARK_NODE_ITEM {
                let startLine = Int(cmark_node_get_start_line(current))
                let endLine = Int(cmark_node_get_end_line(current))
                if startLine >= 1, endLine >= startLine {
                    itemRanges.append((key: UInt(bitPattern: current), range: startLine...endLine))
                }
            }
            collectItemRanges(of: current, into: &itemRanges)
            child = cmark_node_next(current)
        }
    }

    /// The source text of a definition inside an item, with the item's
    /// container syntax taken off. On the item's own first line the marker
    /// stands before the definition, so the text starts at the bracket.
    /// Continuation lines drop the content indent while keeping any extra
    /// indent the author gave them.
    private func itemDefinitionText(
        for span: ClosedRange<Int>,
        itemStartLine: Int,
        lineTable: [LineInfo]
    ) -> String? {
        let firstLine = lineTable[span.lowerBound - 1].content
        let stripWidth: Int
        var lines: [String] = []
        if span.lowerBound == itemStartLine {
            let firstBytes = Array(firstLine.utf8)
            guard let bracket = firstBytes.firstIndex(of: UInt8(ascii: "[")) else { return nil }
            stripWidth = bracket
            lines.append(String(decoding: firstBytes[bracket...], as: UTF8.self))
        } else {
            stripWidth = span.map { leadingSpaceCount(lineTable[$0 - 1].content) }.min() ?? 0
            lines.append(droppingLeadingSpaces(firstLine, upTo: stripWidth))
        }
        for line in span.dropFirst() {
            lines.append(droppingLeadingSpaces(lineTable[line - 1].content, upTo: stripWidth))
        }
        return lines.joined(separator: "\n")
    }

    private func leadingSpaceCount(_ line: String) -> Int {
        var count = 0
        for byte in line.utf8 {
            guard byte == Self.spaceByte else { break }
            count += 1
        }
        return count
    }

    private func droppingLeadingSpaces(_ line: String, upTo width: Int) -> String {
        let bytes = Array(line.utf8)
        let strip = Swift.min(width, leadingSpaceCount(line))
        return String(decoding: bytes[strip...], as: UTF8.self)
    }

    /// True when the recovered text opens with a definition. The lines no
    /// node covers are definitions by elimination, but a container can also
    /// drop source for another reason — the checkbox cmark takes off a task
    /// item leaves its line uncovered too — so only text that opens with a
    /// labelled colon is put back.
    private func isDefinitionShaped(_ text: String) -> Bool {
        guard let firstLine = text.split(separator: "\n", omittingEmptySubsequences: false).first else {
            return false
        }
        return definitionLabel(inLine: firstLine) != nil
    }

    /// The labels defined in a recovered span. Each definition begins a line:
    /// up to three spaces, a bracketed label, then a colon.
    private func definitionLabels(in text: String) -> [String] {
        text.split(separator: "\n", omittingEmptySubsequences: true)
            .compactMap { definitionLabel(inLine: $0) }
    }

    private func definitionLabel(inLine line: Substring) -> String? {
        let bytes = Array(line.utf8)
        var index = 0
        while index < bytes.count, index < 3, bytes[index] == Self.spaceByte {
            index += 1
        }
        guard index < bytes.count, bytes[index] == UInt8(ascii: "["),
              let close = matchingCloseBracket(in: bytes, opening: index),
              close + 1 < bytes.count,
              bytes[close + 1] == UInt8(ascii: ":") else { return nil }
        let label = normalizedLabel(String(decoding: bytes[(index + 1)..<close], as: UTF8.self))
        return label.isEmpty ? nil : label
    }

    /// Labels match case-insensitively with runs of whitespace collapsed, so
    /// `[REF]` finds `[ref]: /url`.
    private func normalizedLabel(_ label: String) -> String {
        label.lowercased()
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
    }

    /// The index of the `]` that closes the `[` at `opening`, skipping
    /// escaped brackets and balanced inner pairs.
    private func matchingCloseBracket(in bytes: [UInt8], opening: Int) -> Int? {
        var depth = 0
        var index = opening
        while index < bytes.count {
            switch bytes[index] {
            case UInt8(ascii: "\\"):
                index += 1
            case UInt8(ascii: "["):
                depth += 1
            case UInt8(ascii: "]"):
                depth -= 1
                if depth == 0 { return index }
            default:
                break
            }
            index += 1
        }
        return nil
    }

    /// Pin each link and image the author wrote in reference style to its
    /// authored spelling. cmark resolves such a node to hold the URL inline,
    /// and its writer would paste that URL into the text as `[ref](url)`. The
    /// node's source position still points at the authored bytes, so a node
    /// whose source reads as a reference to a recovered definition becomes a
    /// custom inline holding those bytes, which every writer emits verbatim.
    /// A node whose position cannot be trusted keeps today's inline form,
    /// which loses the spelling but never the URL.
    private func restoreReferenceStyleLinks(
        in doc: UnsafeMutablePointer<cmark_node>?,
        labels: Set<String>,
        lineTable: [LineInfo]
    ) {
        guard !labels.isEmpty, let doc else { return }
        // Gather first: replacing nodes mid-iteration breaks the iterator.
        var references: [UnsafeMutablePointer<cmark_node>] = []
        let iterator = cmark_iter_new(doc)
        defer { cmark_iter_free(iterator) }
        while true {
            let event = cmark_iter_next(iterator)
            if event == CMARK_EVENT_DONE { break }
            guard event == CMARK_EVENT_ENTER, let node = cmark_iter_get_node(iterator) else { continue }
            let type = cmark_node_get_type(node)
            if type == CMARK_NODE_LINK || type == CMARK_NODE_IMAGE {
                references.append(node)
            }
        }
        // A replaced node frees its whole subtree, and a link can hold a
        // reference-style image (or another link's bytes) inside it. The
        // pre-order gather puts every descendant after its ancestor, so the
        // walk runs backwards: each descendant is decided while its ancestor
        // still owns live memory, and never read after that ancestor is freed.
        for node in references.reversed() {
            guard let source = singleLineSource(of: node, lineTable: lineTable),
                  let label = referenceLabel(inLinkSource: source),
                  labels.contains(label),
                  let replacement = cmark_node_new(CMARK_NODE_CUSTOM_INLINE) else { continue }
            cmark_node_set_on_enter(replacement, source)
            guard cmark_node_insert_before(node, replacement) == 1 else {
                cmark_node_free(replacement)
                continue
            }
            cmark_node_unlink(node)
            cmark_node_free(node)
        }
    }

    /// The authored bytes of an inline node that sits on one source line, or
    /// nil when the reported position cannot be trusted to slice with.
    private func singleLineSource(
        of node: UnsafeMutablePointer<cmark_node>,
        lineTable: [LineInfo]
    ) -> String? {
        let startLine = Int(cmark_node_get_start_line(node))
        let endLine = Int(cmark_node_get_end_line(node))
        let startColumn = Int(cmark_node_get_start_column(node))
        let endColumn = Int(cmark_node_get_end_column(node))
        guard startLine == endLine, startLine >= 1, startLine <= lineTable.count else { return nil }
        let bytes = Array(lineTable[startLine - 1].content.utf8)
        guard startColumn >= 1, startColumn <= endColumn, endColumn <= bytes.count else { return nil }
        return String(decoding: bytes[(startColumn - 1)...(endColumn - 1)], as: UTF8.self)
    }

    /// The label a reference-style link or image points at, or nil for any
    /// other spelling. `[ref]` and `[ref][]` use their own text; `[text][ref]`
    /// names the label second. An inline `[text](url)` ends with a paren and
    /// matches none of these.
    private func referenceLabel(inLinkSource source: String) -> String? {
        var bytes = Array(source.utf8)
        if bytes.first == UInt8(ascii: "!") {
            bytes.removeFirst()
        }
        guard bytes.first == UInt8(ascii: "["),
              let firstClose = matchingCloseBracket(in: bytes, opening: 0) else { return nil }
        let firstLabel = String(decoding: bytes[1..<firstClose], as: UTF8.self)
        if firstClose == bytes.count - 1 {
            let label = normalizedLabel(firstLabel)
            return label.isEmpty ? nil : label
        }
        guard bytes[firstClose + 1] == UInt8(ascii: "["),
              let secondClose = matchingCloseBracket(in: bytes, opening: firstClose + 1),
              secondClose == bytes.count - 1 else { return nil }
        let secondLabel = String(decoding: bytes[(firstClose + 2)..<secondClose], as: UTF8.self)
        let label = normalizedLabel(secondLabel.isEmpty ? firstLabel : secondLabel)
        return label.isEmpty ? nil : label
    }

    /// Interleave the recovered top-level definitions with the parsed blocks
    /// by their position in the source.
    private func merged(_ blocks: [MarkdownBlock], with definitions: [MarkdownBlock]) -> [MarkdownBlock] {
        guard !definitions.isEmpty else { return blocks }
        var result: [MarkdownBlock] = []
        result.reserveCapacity(blocks.count + definitions.count)
        var remaining = definitions[...]
        for block in blocks {
            while let definition = remaining.first,
                  definition.lineRange.lowerBound < block.lineRange.lowerBound {
                result.append(definition)
                remaining.removeFirst()
            }
            result.append(block)
        }
        result.append(contentsOf: remaining)
        return result
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

    /// Recover a blockquote's authored inner Markdown by removing exactly one
    /// outer marker from each marked source line. Rendering the AST back to
    /// CommonMark is not safe here: nested list items beginning with raw HTML or
    /// thematic breaks acquire ambiguous indentation, and renderer-only blank
    /// markers appear before some first-child blocks. Source text already has the
    /// sibling structure and escaping needed to parse the same way again.
    private func getBlockquoteText(
        lineRange: ClosedRange<Int>,
        lineTable: [LineInfo],
        nestedInList: Bool = false
    ) -> String {
        guard lineRange.lowerBound > 0,
              lineRange.upperBound <= lineTable.count else { return "" }

        let lines = lineRange.map { lineTable[$0 - 1].content }
        let firstMarker = nestedInList
            ? firstBlockquoteMarker(in: lines[0])
            : nil
        let maximumMarkerColumn = nestedInList
            ? (firstMarker?.visualColumn ?? 0) + 3
            : 3

        return lines.enumerated().map { offset, line in
            stripOuterBlockquoteMarker(
                from: line,
                exactMarker: offset == 0 ? firstMarker : nil,
                maximumMarkerColumn: maximumMarkerColumn
            )
        }
        .joined(separator: "\n")
    }

    private func blockquoteSource(from innerText: String) -> String {
        innerText
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.isEmpty ? ">" : "> \($0)" }
            .joined(separator: "\n")
    }

    private typealias BlockquoteMarker = (byteIndex: Int, visualColumn: Int)

    /// The first line of a quote nested in a list can still contain the list
    /// marker (`- > quote`). The quote marker is the first `>` on that node's
    /// first source line; everything before it is enclosing container syntax.
    private func firstBlockquoteMarker(in line: String) -> BlockquoteMarker? {
        let bytes = Array(line.utf8)
        guard let byteIndex = bytes.firstIndex(of: 0x3E) else { return nil }
        return (byteIndex, visualColumn(in: bytes, before: byteIndex))
    }

    /// A CommonMark blockquote marker may have leading container indentation,
    /// then `>`, then one optional padding column. A following tab expands to
    /// the next four-column stop; only its first column is marker padding, so
    /// the residual columns remain authored indentation. Lazy continuation
    /// lines have no marker and therefore pass through byte-for-byte.
    private func stripOuterBlockquoteMarker(
        from line: String,
        exactMarker: BlockquoteMarker?,
        maximumMarkerColumn: Int
    ) -> String {
        let bytes = Array(line.utf8)
        let marker: BlockquoteMarker
        if let exactMarker {
            marker = exactMarker
        } else {
            var index = 0
            var column = 0
            while index < bytes.count {
                if bytes[index] == Self.spaceByte {
                    column += 1
                    index += 1
                } else if bytes[index] == Self.tabByte {
                    column += 4 - (column % 4)
                    index += 1
                } else {
                    break
                }
            }
            guard index < bytes.count,
                  bytes[index] == 0x3E,
                  column <= maximumMarkerColumn else { return line }
            marker = (index, column)
        }

        var index = marker.byteIndex + 1
        var columnAfterMarker = marker.visualColumn + 1

        var residualTabIndent = 0
        if index < bytes.count && bytes[index] == Self.spaceByte {
            index += 1
            columnAfterMarker += 1
        } else if index < bytes.count && bytes[index] == Self.tabByte {
            let tabWidth = 4 - (columnAfterMarker % 4)
            residualTabIndent = Swift.max(0, tabWidth - 1)
            index += 1
        }
        return String(repeating: " ", count: residualTabIndent) +
            String(decoding: bytes[index...], as: UTF8.self)
    }

    private func visualColumn(in bytes: [UInt8], before endIndex: Int) -> Int {
        var column = 0
        for byte in bytes[..<endIndex] {
            if byte == Self.tabByte {
                column += 4 - (column % 4)
            } else {
                column += 1
            }
        }
        return column
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
            let nextType = cmark_node_get_type(next)
            return MarkdownEscaper.escape(
                text,
                context: context,
                startsLine: beginsLine(node),
                endsBlock: next == nil,
                // A custom inline is a reference-style link kept in its
                // authored spelling, so it opens with a bracket the same way
                // a link does.
                isFollowedByLink: nextType == CMARK_NODE_LINK || nextType == CMARK_NODE_CUSTOM_INLINE
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
        // cmark's start column points at the marker after up to three legal
        // indentation spaces. Public block ranges address authored source, so
        // those leading bytes belong to the block and must survive slicing and
        // editing along with its marker.
        let startUTF16Index = startLineInfo.utf16Offset
        let startByteIndex = startLineInfo.byteOffset

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
