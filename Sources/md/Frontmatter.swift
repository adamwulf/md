//
//  Frontmatter.swift
//  md
//
//  Created by Adam Wulf on 4/12/26.
//

import Foundation
import Yams

enum FrontmatterFormat: Equatable {
    case yaml
    case toml
    case json
}

struct Frontmatter {
    let format: FrontmatterFormat
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

        let yamlLines = lines[1..<closer]
        let yamlString = yamlLines.joined(separator: "\n")
        let bodyLines = lines[(closer + 1)...]
        let body = bodyLines.joined(separator: "\n")

        let data: [String: Any]
        switch format {
        case .yaml:
            data = (try? Yams.load(yaml: yamlString) as? [String: Any]) ?? [:]
        case .json:
            if let jsonData = yamlString.data(using: .utf8),
               let parsed = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] {
                data = parsed
            } else {
                data = [:]
            }
        case .toml:
            data = [:]
        }

        return Frontmatter(format: format, data: data, rawContent: yamlString, body: body, originalContent: content)
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
        let yaml = try Yams.dump(object: data, sortKeys: true)
        return yaml
    }

    private func serializeTOML() -> String {
        // Placeholder — will be implemented with TOML support
        return rawContent + "\n"
    }

    private func serializeJSON() throws -> String {
        guard !data.isEmpty else { return "" }
        let jsonData = try JSONSerialization.data(withJSONObject: data, options: [.prettyPrinted, .sortedKeys])
        guard let jsonString = String(data: jsonData, encoding: .utf8) else {
            return ""
        }
        return jsonString + "\n"
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
