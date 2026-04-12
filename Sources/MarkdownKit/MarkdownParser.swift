//
//  MarkdownParser.swift
//  md
//
//  Created by Adam Wulf on 4/12/26.
//

import Foundation
import cmark_gfm
import cmark_gfm_extensions

/// Represents a single item in a markdown list, with support for nested lists via indent levels
public struct ListItem: Sendable, Equatable {
    public let text: String
    public let indentLevel: Int
    public let ordered: Bool

    public init(text: String, indentLevel: Int, ordered: Bool) {
        self.text = text
        self.indentLevel = indentLevel
        self.ordered = ordered
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
        }
    }
}

public struct MarkdownParser {
    public init() {}

    // MARK: - ASCII byte constants
    private static let newlineByte = UInt8(ascii: "\n")
    private static let crByte = UInt8(ascii: "\r")

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
                currentUTF16Offset += 1
                currentByteOffset += 1
                byteIdx += 1
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
        let ranges = calculateRanges(for: node, lineTable: lineTable)

        switch type {
        case CMARK_NODE_HEADING:
            let level = Int(cmark_node_get_heading_level(node))
            let text = getChildrenText(node)
            return .heading(level: level, text: text, charRange: ranges.charRange, byteRange: ranges.byteRange, lineRange: ranges.lineRange)

        case CMARK_NODE_PARAGRAPH:
            let text = getChildrenText(node)
            return .paragraph(text: text, charRange: ranges.charRange, byteRange: ranges.byteRange, lineRange: ranges.lineRange)

        case CMARK_NODE_CODE_BLOCK:
            let literal = cmark_node_get_literal(node)
            let code = literal.map { String(cString: $0) } ?? ""
            let fenceInfo = cmark_node_get_fence_info(node)
            let language = fenceInfo.map { String(cString: $0) }
            return .codeBlock(language: language, code: code, charRange: ranges.charRange, byteRange: ranges.byteRange, lineRange: ranges.lineRange)

        case CMARK_NODE_LIST:
            let ordered = cmark_node_get_list_type(node) == CMARK_ORDERED_LIST
            let items = collectListItems(from: node, indentLevel: 0, ordered: ordered)
            return .list(items: items, ordered: ordered, charRange: ranges.charRange, byteRange: ranges.byteRange, lineRange: ranges.lineRange)

        case CMARK_NODE_BLOCK_QUOTE:
            let text = getChildrenText(node)
            return .blockquote(text: text, charRange: ranges.charRange, byteRange: ranges.byteRange, lineRange: ranges.lineRange)

        case CMARK_NODE_THEMATIC_BREAK:
            return .thematicBreak(charRange: ranges.charRange, byteRange: ranges.byteRange, lineRange: ranges.lineRange)

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
                    cellContent += getNodeText(child)
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

    private func collectListItems(
        from listNode: UnsafeMutablePointer<cmark_node>,
        indentLevel: Int,
        ordered: Bool
    ) -> [ListItem] {
        var items: [ListItem] = []
        var itemNode = cmark_node_first_child(listNode)

        while itemNode != nil {
            var itemText = ""
            var child = cmark_node_first_child(itemNode)

            while child != nil {
                let childType = cmark_node_get_type(child)

                if childType == CMARK_NODE_LIST {
                    let nestedOrdered = cmark_node_get_list_type(child) == CMARK_ORDERED_LIST
                    guard let child = child else { continue }
                    let nestedItems = collectListItems(from: child, indentLevel: indentLevel + 1, ordered: nestedOrdered)
                    if !itemText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        items.append(ListItem(
                            text: itemText.trimmingCharacters(in: .whitespacesAndNewlines),
                            indentLevel: indentLevel,
                            ordered: ordered
                        ))
                        itemText = ""
                    }
                    items.append(contentsOf: nestedItems)
                } else {
                    itemText += getNodeText(child)
                }

                child = cmark_node_next(child)
            }

            let trimmedText = itemText.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmedText.isEmpty {
                items.append(ListItem(
                    text: trimmedText,
                    indentLevel: indentLevel,
                    ordered: ordered
                ))
            }

            itemNode = cmark_node_next(itemNode)
        }

        return items
    }

    private func getChildrenText(_ node: UnsafeMutablePointer<cmark_node>?) -> String {
        guard let node = node else { return "" }
        var text = ""
        var child = cmark_node_first_child(node)
        while child != nil {
            text += getNodeText(child)
            child = cmark_node_next(child)
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func getNodeText(_ node: UnsafeMutablePointer<cmark_node>?) -> String {
        guard let node = node else { return "" }

        let type = cmark_node_get_type(node)
        if type == CMARK_NODE_TEXT {
            let literal = cmark_node_get_literal(node)
            return literal.map { String(cString: $0) } ?? ""
        }

        let rendered = cmark_render_commonmark(node, 0, 0)
        defer { free(rendered) }

        if let rendered = rendered {
            return String(cString: rendered).trimmingCharacters(in: .whitespacesAndNewlines)
        }

        return ""
    }

    private func calculateRanges(for node: UnsafeMutablePointer<cmark_node>, lineTable: [LineInfo]) -> RangePair {
        let startLine = Int(cmark_node_get_start_line(node))
        let startColumn = Int(cmark_node_get_start_column(node))
        let endLine = Int(cmark_node_get_end_line(node))
        let endColumn = Int(cmark_node_get_end_column(node))

        guard startLine > 0 && startLine <= lineTable.count &&
              endLine > 0 && endLine <= lineTable.count else {
            return RangePair(charRange: NSRange(location: 0, length: 0), byteRange: NSRange(location: 0, length: 0), lineRange: 1...1)
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
