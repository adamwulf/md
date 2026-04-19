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

struct Frontmatter {
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
        let lines = content.components(separatedBy: "\n")
        guard let firstLine = lines.first, firstLine.trimmingCharacters(in: .whitespaces) == delimiter else {
            return nil
        }

        // Find closing delimiter (skip line 0)
        var closerIndex: Int?
        for i in 1..<lines.count {
            if lines[i].trimmingCharacters(in: .whitespaces) == delimiter {
                closerIndex = i
                break
            }
        }

        guard let closer = closerIndex else {
            return nil
        }

        let rawLines = lines[1..<closer]
        let rawString = rawLines.joined(separator: "\n")
        let bodyLines = lines[(closer + 1)...]
        let body = bodyLines.joined(separator: "\n")

        let data: [String: Any]
        switch format {
        case .yaml:
            data = (try? Yams.load(yaml: rawString) as? [String: Any]) ?? [:]
        case .json:
            if let jsonData = rawString.data(using: .utf8),
               let parsed = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] {
                data = parsed
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
            return serializeTOML()
        case .json:
            return try serializeJSON()
        }
    }

    private func serializeYAML() throws -> String {
        guard !data.isEmpty else { return "" }
        let normalized = Frontmatter.normalizeForYAML(data)
        let yaml = try Yams.dump(object: normalized, sortKeys: true)
        return yaml
    }

    private func serializeTOML() -> String {
        guard !data.isEmpty else { return "" }
        let table = Frontmatter.dictToTOMLTable(data)
        return table.convert(to: .toml) + "\n"
    }

    private func serializeJSON() throws -> String {
        guard !data.isEmpty else { return "" }
        let normalized = Frontmatter.normalizeForJSON(data)
        let jsonData = try JSONSerialization.data(withJSONObject: normalized, options: [.prettyPrinted, .sortedKeys])
        guard let jsonString = String(data: jsonData, encoding: .utf8) else {
            return ""
        }
        return jsonString + "\n"
    }

    // MARK: - Normalization

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
    static func dictToTOMLTable(_ dict: [String: Any]) -> TOMLTable {
        let table = TOMLTable()
        for (key, value) in dict {
            table[key] = anyToTOMLValue(value)
        }
        return table
    }

    /// Convert a Swift Any value to a TOMLValueConvertible.
    private static func anyToTOMLValue(_ value: Any) -> TOMLValueConvertible {
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
            return dictToTOMLTable(dict)
        case let arr as [Any]:
            return TOMLArray(arr.map { anyToTOMLValue($0) })
        default:
            return String(describing: value)
        }
    }

    // MARK: - Value Parsing

    /// Parse a string value into the most appropriate type.
    static func parseValue(_ string: String) -> Any {
        // Boolean
        let lower = string.lowercased()
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
            return items
        }

        // String
        return string
    }
}
