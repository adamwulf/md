//
//  ListCommand.swift
//  md
//
//  Created by Adam Wulf on 4/12/26.
//

import ArgumentParser
import Foundation

enum ListOutputFormat: String, ExpressibleByArgument, CaseIterable {
    case plain
    case json
    case ndjson
}

enum ListMissingMode: String, ExpressibleByArgument, CaseIterable {
    case include
    case skip
    case only
}

enum ListSortOrder: String, ExpressibleByArgument, CaseIterable {
    case path
    case mtime
    case name
}

struct ListCommand: AsyncParsableCommand {

    static var configuration = CommandConfiguration(
        commandName: "list",
        abstract: "List frontmatter for every .md file in one or more directories",
        discussion: """
            Walks each directory and prints the frontmatter of each .md file \
            it finds. Only the .md extension is recognized. Symlinked \
            directories are not descended into.

            --output plain  prints a block per file prefixed with "== <path> ==". \
            --output json   prints a single JSON array. \
            --output ndjson prints one JSON object per line.

            Frontmatter is converted to the format given by --format (yaml by \
            default). Use --key or --keys to project a single value or subset \
            of keys. --missing controls files without frontmatter.

              $ md list ./notes
              $ md list -r ./notes --format json
              $ md list ./notes --key title
              $ md list -r . --output ndjson --missing skip
            """
    )

    @Argument(help: "One or more directories to scan")
    var directories: [String]

    @Flag(name: .shortAndLong, help: "Recurse into subdirectories")
    var recursive: Bool = false

    @Option(name: .long, help: "Output format for each file's frontmatter (yaml, json, or toml)")
    var format: FrontmatterFormat = .yaml

    @Option(name: .long, help: "Envelope format: plain, json, or ndjson")
    var output: ListOutputFormat = .plain

    @Option(name: .long, help: "Print only this key's value per file (dot syntax supported)")
    var key: String?

    @Option(name: .long, help: "Comma-separated list of keys to project (dot syntax supported)")
    var keys: String?

    @Option(name: .long, help: "How to handle files without frontmatter: include, skip, only")
    var missing: ListMissingMode = .include

    @Option(name: .long, help: "Sort order: path, mtime, or name")
    var sort: ListSortOrder = .path

    func validate() throws {
        if directories.isEmpty {
            throw ValidationError("md list: expected at least one directory")
        }
        if key != nil && keys != nil {
            throw ValidationError("Specify at most one of --key or --keys")
        }
    }

    // MARK: - Run

    func run() async throws {
        let entries = collectEntries()
        let text = try render(entries)
        print(text, terminator: "")
    }

    func render(_ entries: [Entry]) throws -> String {
        switch output {
        case .plain:
            return renderPlain(entries)
        case .json:
            return try renderJSON(entries) + "\n"
        case .ndjson:
            return try renderNDJSON(entries)
        }
    }

    // MARK: - Entry

    struct Entry {
        let path: String
        let mtime: Date?
        let frontmatter: Frontmatter?
    }

    // MARK: - Entry collection

    func collectEntries() -> [Entry] {
        var seen = Set<String>()
        var entries: [Entry] = []
        for dir in directories {
            let files = walkDirectory(dir)
            for file in files where seen.insert(file).inserted {
                entries.append(loadEntry(path: file))
            }
        }

        switch sort {
        case .path:
            entries.sort { $0.path < $1.path }
        case .name:
            entries.sort { ($0.path as NSString).lastPathComponent < ($1.path as NSString).lastPathComponent }
        case .mtime:
            entries.sort {
                let a = $0.mtime ?? .distantPast
                let b = $1.mtime ?? .distantPast
                return a < b
            }
        }

        switch missing {
        case .include:
            return entries
        case .skip:
            return entries.filter { $0.frontmatter != nil }
        case .only:
            return entries.filter { $0.frontmatter == nil }
        }
    }

    private func loadEntry(path: String) -> Entry {
        let url = URL(fileURLWithPath: path)
        let mtime = (try? FileManager.default.attributesOfItem(atPath: path)[.modificationDate]) as? Date

        let content: String
        do {
            content = try String(contentsOf: url, encoding: .utf8)
        } catch {
            writeStderr("md list: \(path): \(error.localizedDescription)")
            return Entry(path: path, mtime: mtime, frontmatter: nil)
        }

        guard var fm = Frontmatter.parse(content) else {
            return Entry(path: path, mtime: mtime, frontmatter: nil)
        }
        fm.format = format
        return Entry(path: path, mtime: mtime, frontmatter: fm)
    }

    // MARK: - Directory walking

    private func walkDirectory(_ path: String) -> [String] {
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDir), isDir.boolValue else {
            writeStderr("md list: not a directory: \(path)")
            return []
        }

        let root = URL(fileURLWithPath: path)

        var options: FileManager.DirectoryEnumerationOptions = [.skipsHiddenFiles, .skipsPackageDescendants]
        if !recursive {
            options.insert(.skipsSubdirectoryDescendants)
        }

        let resourceKeys: [URLResourceKey] = [.isRegularFileKey, .isSymbolicLinkKey]
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: resourceKeys,
            options: options,
            errorHandler: { url, error in
                self.writeStderr("md list: \(url.path): \(error.localizedDescription)")
                return true
            }
        ) else {
            return []
        }

        var results: [String] = []
        for case let url as URL in enumerator {
            let values = try? url.resourceValues(forKeys: Set(resourceKeys))
            if values?.isSymbolicLink == true { continue }
            guard values?.isRegularFile == true else { continue }
            guard url.pathExtension.lowercased() == "md" else { continue }
            results.append(url.path)
        }
        return results
    }

    // MARK: - Emitters

    private func renderPlain(_ entries: [Entry]) -> String {
        var out = ""
        if let key = key {
            for entry in entries {
                guard let fm = entry.frontmatter, let value = fm.get(key) else { continue }
                out += "\(entry.path)\t\(formatScalarValue(value))\n"
            }
            return out
        }

        for (idx, entry) in entries.enumerated() {
            let body: String?
            if let fm = entry.frontmatter {
                let projected = projectedFrontmatter(from: fm)
                do {
                    body = try projected.serializeData()
                } catch {
                    writeStderr("md list: \(entry.path): \(error.localizedDescription)")
                    continue
                }
            } else {
                body = nil
            }

            if idx > 0 { out += "\n" }
            out += "== \(entry.path) ==\n"
            if let body = body {
                if body.isEmpty {
                    out += "(empty frontmatter)\n"
                } else {
                    out += body
                    if !body.hasSuffix("\n") { out += "\n" }
                }
            } else {
                out += "(no frontmatter)\n"
            }
        }
        return out
    }

    private func renderJSON(_ entries: [Entry]) throws -> String {
        let array = entries.map { jsonRecord(for: $0) }
        let data = try JSONSerialization.data(withJSONObject: array, options: [.prettyPrinted, .sortedKeys])
        return String(data: data, encoding: .utf8) ?? ""
    }

    private func renderNDJSON(_ entries: [Entry]) throws -> String {
        var out = ""
        for entry in entries {
            let data = try JSONSerialization.data(withJSONObject: jsonRecord(for: entry), options: [.sortedKeys])
            if let str = String(data: data, encoding: .utf8) {
                out += str + "\n"
            }
        }
        return out
    }

    // MARK: - Projection

    /// Paths to project. `--key` projects a single nested path; `--keys` projects
    /// a list. Returning nil means "no projection — include the whole object."
    private func projectionPaths() -> [String]? {
        if let key = key {
            return [key]
        }
        guard let raw = keys else { return nil }
        let list = raw
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        return list.isEmpty ? nil : list
    }

    private func projectedFrontmatter(from fm: Frontmatter) -> Frontmatter {
        guard let paths = projectionPaths() else { return fm }
        var projected = Frontmatter(format: fm.format, data: [:], rawContent: fm.rawContent, body: fm.body, originalContent: fm.originalContent)
        for path in paths {
            guard let value = fm.get(path) else { continue }
            projected.set(path, value: value)
        }
        return projected
    }

    // MARK: - JSON record

    private func jsonRecord(for entry: Entry) -> [String: Any] {
        var record: [String: Any] = ["path": entry.path]
        if let fm = entry.frontmatter {
            record["format"] = fm.format.rawValue
            let projected = projectedFrontmatter(from: fm)
            if projected.data.isEmpty {
                record["frontmatter"] = NSNull()
            } else {
                record["frontmatter"] = Frontmatter.normalizeForJSON(projected.data)
            }
        } else {
            record["format"] = NSNull()
            record["frontmatter"] = NSNull()
        }
        return record
    }

    // MARK: - Scalar formatting

    private func formatScalarValue(_ value: Any) -> String {
        // Normalize dates / nested structures into JSON-friendly shape first so
        // dates become ISO-8601 instead of Swift's Date debug description.
        let normalized = Frontmatter.normalizeForJSON(value)
        if let array = normalized as? [Any] {
            return array.map { "\($0)" }.joined(separator: ",")
        }
        if let dict = normalized as? [String: Any] {
            let data = try? JSONSerialization.data(withJSONObject: dict, options: [.sortedKeys])
            if let data = data, let str = String(data: data, encoding: .utf8) {
                return str
            }
        }
        return "\(normalized)"
    }

    // MARK: - Stderr

    private func writeStderr(_ message: String) {
        FileHandle.standardError.write(Data((message + "\n").utf8))
    }
}
