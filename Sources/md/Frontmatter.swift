//
//  Frontmatter.swift
//  md
//
//  Created by Adam Wulf on 4/12/26.
//

import Foundation
import TOMLKit
import Yams

enum FrontmatterFormat: String, Equatable, CaseIterable {
    case yaml
    case toml
    case json
}

enum FrontmatterSerializationError: LocalizedError {
    case nonFiniteJSONNumber(keyPath: String)
    case nullNotRepresentableInTOML(keyPath: String)
    case invalidJSONObject

    var errorDescription: String? {
        switch self {
        case .nonFiniteJSONNumber(let keyPath):
            return "JSON cannot represent the non-finite number at key path \(keyPath)"
        case .nullNotRepresentableInTOML(let keyPath):
            return "TOML cannot represent the null value at key path \(keyPath)"
        case .invalidJSONObject:
            return "Frontmatter contains a value that JSON cannot represent"
        }
    }
}

struct Frontmatter {
    private struct SourceLine {
        let contentRange: Range<String.Index>
        let fullRange: Range<String.Index>
    }

    var format: FrontmatterFormat
    var data: [String: Any]
    let rawContent: String

    /// The body of the markdown file after the frontmatter.
    let body: String

    /// The full original file content.
    let originalContent: String

    // MARK: - Extraction

    /// Parse frontmatter from markdown content. Returns nil if no frontmatter found.
    /// Auto-detects format by delimiter: `---` (YAML), `+++` (TOML), `;;;` (JSON).
    static func parse(_ content: String) -> Frontmatter? {
        if let result = parseFenced(content, delimiter: "---", format: .yaml) {
            return result
        }
        if let result = parseFenced(content, delimiter: "+++", format: .toml) {
            return result
        }
        if let result = parseFenced(content, delimiter: ";;;", format: .json) {
            return result
        }
        return nil
    }

    /// Generic fenced frontmatter parser. Splits on delimiter lines.
    private static func parseFenced(_ content: String, delimiter: String, format: FrontmatterFormat) -> Frontmatter? {
        let lines = sourceLines(in: content)
        guard let firstLine = lines.first,
              content[firstLine.contentRange].trimmingCharacters(in: .whitespaces) == delimiter else {
            return nil
        }

        // Find closing delimiter (skip line 0)
        var closerIndex: Int?
        for i in 1..<lines.count {
            if content[lines[i].contentRange].trimmingCharacters(in: .whitespaces) == delimiter {
                closerIndex = i
                break
            }
        }

        guard let closer = closerIndex else {
            return nil
        }

        let rawStart = lines[0].fullRange.upperBound
        let rawEnd = closer > 1
            ? lines[closer - 1].contentRange.upperBound
            : rawStart
        let rawString = String(content[rawStart..<rawEnd])
        let bodyStart = lines[closer].fullRange.upperBound
        let body = String(content[bodyStart...])

        let data: [String: Any]
        switch format {
        case .yaml:
            data = (try? Yams.load(yaml: rawString) as? [String: Any]) ?? [:]
        case .json:
            if let jsonData = rawString.data(using: .utf8),
               let parsed = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] {
                data = (Frontmatter.unbridgeNSNumber(parsed) as? [String: Any]) ?? [:]
            } else {
                data = [:]
            }
        case .toml:
            if let table = try? TOMLTable(string: rawString) {
                data = Frontmatter.tomlTableToDict(table)
            } else {
                data = [:]
            }
        }

        return Frontmatter(format: format, data: data, rawContent: rawString, body: body, originalContent: content)
    }

    /// Splits source into logical lines while retaining each original line
    /// ending in `fullRange`. Swift treats CRLF as one newline character, so
    /// this supports LF, CRLF, and lone CR without normalizing source bytes.
    private static func sourceLines(in content: String) -> [SourceLine] {
        var lines: [SourceLine] = []
        var lineStart = content.startIndex
        var index = lineStart

        while index < content.endIndex {
            let character = content[index]
            if character == "\n" || character == "\r" || character == "\r\n" {
                let nextIndex = content.index(after: index)
                lines.append(
                    SourceLine(
                        contentRange: lineStart..<index,
                        fullRange: lineStart..<nextIndex
                    )
                )
                lineStart = nextIndex
                index = nextIndex
            } else {
                index = content.index(after: index)
            }
        }

        lines.append(
            SourceLine(
                contentRange: lineStart..<content.endIndex,
                fullRange: lineStart..<content.endIndex
            )
        )
        return lines
    }

    // MARK: - Key Access (dot syntax)

    /// Get a value by dot-separated key path.
    func get(_ keyPath: String) -> Any? {
        let keys = keyPath.split(separator: ".").map(String.init)
        var current: Any = data
        for key in keys {
            guard let dict = current as? [String: Any], let next = dict[key] else {
                return nil
            }
            current = next
        }
        return current
    }

    /// Set a value by dot-separated key path. Creates intermediate dictionaries as needed.
    mutating func set(_ keyPath: String, value: Any) {
        let keys = keyPath.split(separator: ".").map(String.init)
        data = setNested(in: data, keys: keys, value: value)
    }

    /// Remove a value by dot-separated key path.
    mutating func removeKey(_ keyPath: String) {
        let keys = keyPath.split(separator: ".").map(String.init)
        data = removeNested(in: data, keys: keys)
    }

    private func setNested(in dict: [String: Any], keys: [String], value: Any) -> [String: Any] {
        guard let first = keys.first else { return dict }
        var result = dict
        if keys.count == 1 {
            result[first] = value
        } else {
            let nested = (dict[first] as? [String: Any]) ?? [:]
            result[first] = setNested(in: nested, keys: Array(keys.dropFirst()), value: value)
        }
        return result
    }

    private func removeNested(in dict: [String: Any], keys: [String]) -> [String: Any] {
        guard let first = keys.first else { return dict }
        var result = dict
        if keys.count == 1 {
            result.removeValue(forKey: first)
        } else if var nested = dict[first] as? [String: Any] {
            nested = removeNested(in: nested, keys: Array(keys.dropFirst()))
            result[first] = nested
        }
        return result
    }

    // MARK: - Serialization

    /// Serialize the frontmatter back to a string with delimiters and body.
    func serialize() throws -> String {
        let serialized = try serializeData()
        switch format {
        case .yaml:
            return "---\n\(serialized)---\n\(body)"
        case .toml:
            return "+++\n\(serialized)+++\n\(body)"
        case .json:
            return ";;;\n\(serialized);;;\n\(body)"
        }
    }

    /// Serialize just the data portion (without delimiters).
    func serializeData() throws -> String {
        switch format {
        case .yaml:
            return try serializeYAML()
        case .toml:
            return try serializeTOML()
        case .json:
            return try serializeJSON()
        }
    }

    private func serializeYAML() throws -> String {
        guard !data.isEmpty else { return "" }
        let normalized = Frontmatter.normalizeForYAML(data)
        let yaml = try Yams.dump(object: normalized, allowUnicode: true, sortKeys: true)
        return yaml
    }

    private func serializeTOML() throws -> String {
        guard !data.isEmpty else { return "" }
        let table = try Frontmatter.dictToTOMLTable(data)
        return table.convert(to: .toml) + "\n"
    }

    private func serializeJSON() throws -> String {
        guard !data.isEmpty else { return "" }
        try validateForJSON()
        let normalized = Frontmatter.normalizeForJSON(data)
        guard JSONSerialization.isValidJSONObject(normalized) else {
            throw FrontmatterSerializationError.invalidJSONObject
        }
        let jsonData = try JSONSerialization.data(withJSONObject: normalized, options: [.prettyPrinted, .sortedKeys])
        guard let jsonString = String(data: jsonData, encoding: .utf8) else {
            return ""
        }
        return jsonString + "\n"
    }

    // MARK: - Normalization

    /// Recursively convert `NSNumber` values inside a JSON-parsed structure to
    /// their native Swift counterparts (`Bool`, `Int`, or `Double`). Necessary
    /// because `JSONSerialization` returns numeric values as `NSNumber`, and
    /// `NSNumber` bridges to Swift such that `as? Bool` matches every non-zero
    /// number — silently turning integers like `1` into `true` downstream.
    static func unbridgeNSNumber(_ value: Any) -> Any {
        if let dict = value as? [String: Any] {
            return dict.mapValues { unbridgeNSNumber($0) }
        }
        if let array = value as? [Any] {
            return array.map { unbridgeNSNumber($0) }
        }
        if let num = value as? NSNumber {
            if CFGetTypeID(num) == CFBooleanGetTypeID() {
                return num.boolValue
            }
            let objCType = String(cString: num.objCType)
            // Floating-point types: 'f' (float), 'd' (double).
            if objCType == "f" || objCType == "d" {
                return num.doubleValue
            }
            return num.intValue
        }
        return value
    }

    private static let jsonDateFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    /// Normalize values into JSON-serializable types. Dates become ISO-8601 strings;
    /// unsupported types fall back to their String description.
    static func normalizeForJSON(_ value: Any) -> Any {
        if let dict = value as? [String: Any] {
            return dict.mapValues { normalizeForJSON($0) }
        }
        if let array = value as? [Any] {
            return array.map { normalizeForJSON($0) }
        }
        if let date = value as? Date {
            return jsonDateFormatter.string(from: date)
        }
        if let b = value as? Bool {
            return b
        }
        if let i = value as? Int {
            return i
        }
        if let d = value as? Double {
            return d.isFinite ? d : NSNull()
        }
        if let f = value as? Float {
            return f.isFinite ? Double(f) : NSNull()
        }
        if let s = value as? String {
            return s
        }
        if value is NSNull {
            return NSNull()
        }
        return "\(value)"
    }

    /// Reject values JSON cannot spell before Foundation sees them. Foundation's
    /// serializer raises an Objective-C exception for non-finite numbers instead
    /// of throwing a Swift error, so checking after the call is too late.
    func validateForJSON() throws {
        if let keyPath = Frontmatter.firstNonFiniteJSONNumber(in: data) {
            throw FrontmatterSerializationError.nonFiniteJSONNumber(keyPath: keyPath)
        }
    }

    /// Reject null before TOMLKit sees it. TOML has no null value, so silently
    /// converting Foundation's NSNull description into text changes its type.
    func validateForTOML() throws {
        _ = try Frontmatter.dictToTOMLTable(data)
    }

    private static func firstNonFiniteJSONNumber(
        in value: Any,
        keyPath: String = ""
    ) -> String? {
        if let dict = value as? [String: Any] {
            for key in dict.keys.sorted() {
                guard let child = dict[key] else { continue }
                let childPath = appendingJSONPathKey(key, to: keyPath)
                if let invalidPath = firstNonFiniteJSONNumber(
                    in: child,
                    keyPath: childPath
                ) {
                    return invalidPath
                }
            }
            return nil
        }
        if let array = value as? [Any] {
            for (index, element) in array.enumerated() {
                let childPath = "\(keyPath)[\(index)]"
                if let invalidPath = firstNonFiniteJSONNumber(
                    in: element,
                    keyPath: childPath
                ) {
                    return invalidPath
                }
            }
            return nil
        }
        if let number = value as? Double, !number.isFinite {
            return keyPath
        }
        if let number = value as? Float, !number.isFinite {
            return keyPath
        }
        return nil
    }

    private static func appendingJSONPathKey(
        _ key: String,
        to keyPath: String
    ) -> String {
        if !key.isEmpty,
           key.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "_" }) {
            return keyPath.isEmpty ? key : "\(keyPath).\(key)"
        }

        let encoded = try? JSONSerialization.data(
            withJSONObject: key,
            options: [.fragmentsAllowed]
        )
        let quotedKey = encoded.flatMap { String(data: $0, encoding: .utf8) }
            ?? "\"\(key)\""
        return "\(keyPath)[\(quotedKey)]"
    }

    /// Normalize Foundation types (NSString, NSNumber) to Swift native types for Yams compatibility.
    static func normalizeForYAML(_ value: Any) -> Any {
        if let dict = value as? [String: Any] {
            return dict.mapValues { normalizeForYAML($0) }
        }
        if let array = value as? [Any] {
            return array.map { normalizeForYAML($0) }
        }
        if let b = value as? Bool {
            return b
        }
        if let i = value as? Int {
            return i
        }
        if let d = value as? Double {
            return d
        }
        if let s = value as? String {
            return s
        }
        if value is NSNull {
            return NSNull()
        }
        return "\(value)"
    }

    // MARK: - TOML Conversion

    /// Convert a TOMLTable to a [String: Any] dictionary.
    static func tomlTableToDict(_ table: TOMLTable) -> [String: Any] {
        var result: [String: Any] = [:]
        for (key, value) in table {
            result[key] = tomlValueToAny(value)
        }
        return result
    }

    /// Convert a TOMLValueConvertible to a Swift Any value.
    private static func tomlValueToAny(_ value: TOMLValueConvertible) -> Any {
        switch value.type {
        case .string:
            return value.string ?? ""
        case .int:
            return value.int ?? 0
        case .double:
            return value.double ?? 0.0
        case .bool:
            return value.bool ?? false
        case .table:
            if let table = value.table {
                return tomlTableToDict(table)
            }
            return [String: Any]()
        case .array:
            if let array = value.array {
                return array.map { tomlValueToAny($0) }
            }
            return [Any]()
        case .date:
            return value.date?.debugDescription ?? ""
        case .time:
            return value.time?.debugDescription ?? ""
        case .dateTime:
            return value.dateTime?.debugDescription ?? ""
        }
    }

    /// Convert a [String: Any] dictionary to a TOMLTable.
    static func dictToTOMLTable(
        _ dict: [String: Any],
        keyPath: String = ""
    ) throws -> TOMLTable {
        let table = TOMLTable()
        for key in dict.keys.sorted() {
            guard let value = dict[key] else { continue }
            let childPath = appendingJSONPathKey(key, to: keyPath)
            table[key] = try anyToTOMLValue(value, keyPath: childPath)
        }
        return table
    }

    /// Serialize a collection used as one item of a projected array. Flow
    /// style keeps the collection on one line, so an array of arrays retains
    /// its shape while still using the requested frontmatter syntax.
    static func serializeInlineCollection(
        _ value: Any,
        format: FrontmatterFormat
    ) throws -> String {
        switch format {
        case .yaml:
            let blockYAML = try Yams.dump(
                object: normalizeForYAML(value),
                allowUnicode: true,
                sortKeys: true
            )
            guard let node = try Yams.compose(yaml: blockYAML) else {
                return ""
            }
            return try Yams.serialize(
                node: yamlFlowNode(node),
                allowUnicode: true,
                sortKeys: true
            ).trimmingCharacters(in: .newlines)
        case .json:
            let wrapper = Frontmatter(
                format: .json,
                data: ["value": value],
                rawContent: "",
                body: "",
                originalContent: ""
            )
            try wrapper.validateForJSON()
            let normalized = normalizeForJSON(value)
            guard JSONSerialization.isValidJSONObject(normalized) else {
                throw FrontmatterSerializationError.invalidJSONObject
            }
            let bytes = try JSONSerialization.data(
                withJSONObject: normalized,
                options: [.sortedKeys, .fragmentsAllowed]
            )
            return String(data: bytes, encoding: .utf8) ?? ""
        case .toml:
            let table = try dictToTOMLTable(["value": value])
            let assignment = table.convert(to: .toml)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let prefix = "value = "
            guard assignment.hasPrefix(prefix) else { return assignment }
            return String(assignment.dropFirst(prefix.count))
        }
    }

    private static func yamlFlowNode(_ node: Node) -> Node {
        var result = node
        if var sequence = node.sequence {
            sequence.style = .flow
            for index in sequence.indices {
                sequence[index] = yamlFlowNode(sequence[index])
            }
            result.sequence = sequence
        } else if var mapping = node.mapping {
            mapping.style = .flow
            for index in mapping.indices {
                let pair = mapping[index]
                mapping[index] = (
                    key: yamlFlowNode(pair.key),
                    value: yamlFlowNode(pair.value)
                )
            }
            result.mapping = mapping
        }
        return result
    }

    /// Convert a Swift Any value to a TOMLValueConvertible.
    private static func anyToTOMLValue(
        _ value: Any,
        keyPath: String
    ) throws -> TOMLValueConvertible {
        switch value {
        case let b as Bool:
            return b
        case let i as Int:
            return i
        case let d as Double:
            return d
        case let s as String:
            return s
        case let dict as [String: Any]:
            return try dictToTOMLTable(dict, keyPath: keyPath)
        case let arr as [Any]:
            return TOMLArray(try arr.enumerated().map { index, element in
                try anyToTOMLValue(
                    element,
                    keyPath: "\(keyPath)[\(index)]"
                )
            })
        case is NSNull:
            throw FrontmatterSerializationError.nullNotRepresentableInTOML(
                keyPath: keyPath
            )
        default:
            return String(describing: value)
        }
    }

    // MARK: - Value Parsing

    /// Parse a string value into the most appropriate type.
    static func parseValue(_ string: String) -> Any {
        let lower = string.lowercased()
        if lower == "null" { return NSNull() }

        // Boolean
        if lower == "true" { return true }
        if lower == "false" { return false }

        // Integer
        if let intVal = Int(string) { return intVal }

        // Double
        if let doubleVal = Double(string), string.contains(".") { return doubleVal }

        // YAML array syntax: [a, b, c]
        if string.hasPrefix("[") && string.hasSuffix("]") {
            let inner = String(string.dropFirst().dropLast())
            let items = inner.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            if items.contains(where: { $0.lowercased() == "null" }) {
                return items.map { item -> Any in
                    item.lowercased() == "null" ? NSNull() : item
                }
            }
            return items
        }

        // String
        return string
    }
}
