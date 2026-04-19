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
            Walks each directory and prints the frontmatter of each .md file it \
            finds. Only the .md extension is recognized.

            Output modes:

              plain  — block per file, prefixed with "== <path> =="; files with \
                       no frontmatter show "(no frontmatter)". With --key, each \
                       line is "<path>\\t<value>".
              json   — single JSON array of {path, format, frontmatter} objects.
              ndjson — one JSON object per line (streaming-friendly).

            Frontmatter is converted to the format given by --format (yaml by \
            default). Use --key or --keys to project a single value or subset \
            of keys. --missing controls how files without frontmatter are \
            handled.

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

    @Flag(name: .long, help: "Follow symbolic links while walking directories")
    var followSymlinks: Bool = false

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
        let entries = try collectEntries()
        let rendered: String
        switch output {
        case .plain:
            rendered = renderPlain(entries)
        case .json:
            rendered = try renderJSON(entries)
        case .ndjson:
            rendered = try renderNDJSON(entries)
        }
        if !rendered.isEmpty {
            print(rendered, terminator: rendered.hasSuffix("\n") ? "" : "\n")
        }
    }

    // MARK: - Entry collection

    struct Entry {
        let path: String
        let mtime: Date?
        let frontmatter: Frontmatter?
    }

    func collectEntries() throws -> [Entry] {
        var entries: [Entry] = []
        for dir in directories {
            let files = try walkDirectory(dir)
            for file in files {
                let entry = loadEntry(path: file)
                entries.append(entry)
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
            FileHandle.standardError.write(Data("md list: \(path): \(error.localizedDescription)\n".utf8))
            return Entry(path: path, mtime: mtime, frontmatter: nil)
        }

        guard var fm = Frontmatter.parse(content) else {
            return Entry(path: path, mtime: mtime, frontmatter: nil)
        }
        fm.format = format
        return Entry(path: path, mtime: mtime, frontmatter: fm)
    }

    // MARK: - Directory walking

    private func walkDirectory(_ path: String) throws -> [String] {
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDir), isDir.boolValue else {
            FileHandle.standardError.write(Data("md list: not a directory: \(path)\n".utf8))
            return []
        }

        let root = URL(fileURLWithPath: path)
        var results: [String] = []

        var options: FileManager.DirectoryEnumerationOptions = [.skipsHiddenFiles, .skipsPackageDescendants]
        if !followSymlinks {
            // FileManager already doesn't follow symlinks by default for enumerator,
            // but we still need to skip them when recursing to avoid cycles.
        }
        if !recursive {
            options.insert(.skipsSubdirectoryDescendants)
        }

        let resourceKeys: [URLResourceKey] = [.isRegularFileKey, .isSymbolicLinkKey, .nameKey]
        guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: resourceKeys, options: options) else {
            return []
        }

        for case let url as URL in enumerator {
            let values = try? url.resourceValues(forKeys: Set(resourceKeys))
            let isSymlink = values?.isSymbolicLink ?? false
            if isSymlink && !followSymlinks {
                continue
            }
            let isRegular = values?.isRegularFile ?? false
            guard isRegular else { continue }
            guard url.pathExtension.lowercased() == "md" else { continue }
            results.append(url.relativePath)
        }

        return results
    }

    // MARK: - Emitters

    func renderPlain(_ entries: [Entry]) -> String {
        var out = ""
        if let key = key {
            for entry in entries {
                guard let fm = entry.frontmatter, let value = fm.get(key) else { continue }
                out += "\(entry.path)\t\(formatScalarValue(value))\n"
            }
            return out
        }

        for (idx, entry) in entries.enumerated() {
            if idx > 0 { out += "\n" }
            out += "== \(entry.path) ==\n"
            guard let fm = entry.frontmatter else {
                out += "(no frontmatter)\n"
                continue
            }
            let projected = projectedFrontmatter(from: fm)
            do {
                let body = try projected.serializeData()
                if body.isEmpty {
                    out += "(empty frontmatter)\n"
                } else {
                    out += body
                    if !body.hasSuffix("\n") { out += "\n" }
                }
            } catch {
                FileHandle.standardError.write(Data("md list: \(entry.path): \(error.localizedDescription)\n".utf8))
            }
        }
        return out
    }

    func renderJSON(_ entries: [Entry]) throws -> String {
        var array: [[String: Any]] = []
        for entry in entries {
            array.append(jsonRecord(for: entry))
        }
        let data = try JSONSerialization.data(withJSONObject: array, options: [.prettyPrinted, .sortedKeys])
        return String(data: data, encoding: .utf8) ?? ""
    }

    func renderNDJSON(_ entries: [Entry]) throws -> String {
        var out = ""
        for entry in entries {
            let record = jsonRecord(for: entry)
            let data = try JSONSerialization.data(withJSONObject: record, options: [.sortedKeys])
            if let str = String(data: data, encoding: .utf8) {
                out += str + "\n"
            }
        }
        return out
    }

    // MARK: - Projection

    private func projectedFrontmatter(from fm: Frontmatter) -> Frontmatter {
        guard let keys = parseKeysOption() else { return fm }
        var projected: [String: Any] = [:]
        for path in keys {
            guard let value = fm.get(path) else { continue }
            // Reassemble nested shape from dot path
            var next = projected
            setNested(&next, keys: path.split(separator: ".").map(String.init), value: value)
            projected = next
        }
        return Frontmatter(format: fm.format, data: projected, rawContent: fm.rawContent, body: fm.body, originalContent: fm.originalContent)
    }

    private func setNested(_ dict: inout [String: Any], keys: [String], value: Any) {
        guard let first = keys.first else { return }
        if keys.count == 1 {
            dict[first] = value
            return
        }
        var nested = (dict[first] as? [String: Any]) ?? [:]
        let rest = Array(keys.dropFirst())
        setNested(&nested, keys: rest, value: value)
        dict[first] = nested
    }

    private func parseKeysOption() -> [String]? {
        guard let raw = keys else { return nil }
        let list = raw.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        return list.isEmpty ? nil : list
    }

    // MARK: - JSON record

    private func jsonRecord(for entry: Entry) -> [String: Any] {
        var record: [String: Any] = [
            "path": entry.path
        ]
        if let fm = entry.frontmatter {
            record["format"] = fm.format.rawValue
            if let key = key {
                if let value = fm.get(key) {
                    record["frontmatter"] = Frontmatter.normalizeForJSON(["\(key)": value])
                } else {
                    record["frontmatter"] = NSNull()
                }
            } else {
                let projected = projectedFrontmatter(from: fm)
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
        if let array = value as? [Any] {
            return array.map { "\($0)" }.joined(separator: ",")
        }
        return "\(value)"
    }
}
