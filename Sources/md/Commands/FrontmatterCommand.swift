//
//  FrontmatterCommand.swift
//  md
//
//  Created by Adam Wulf on 4/12/26.
//

import ArgumentParser
import Foundation

extension FrontmatterFormat: ExpressibleByArgument {}

struct FrontmatterCommand: AsyncParsableCommand {

    static var configuration = CommandConfiguration(
        commandName: "frontmatter",
        abstract: "Read, set, or remove frontmatter key/value pairs",
        discussion: """
            Supported frontmatter formats: YAML (--- delimiters), TOML \
            (+++ delimiters), and JSON (;;; delimiters).

            Modes of operation:

              No flags       — prints the frontmatter data only (no delimiters).
              --key KEY      — prints the value of KEY.
              --set KEY=VAL  — sets KEY to VAL. Creates frontmatter if none exists.
              --remove-key K — removes the key K.

            Keys support dot syntax for nested access (e.g. "author.name"). \
            --format converts output to the specified format (yaml, json, toml). \
            When --set creates new frontmatter, the format defaults to YAML \
            unless --format is specified.

            Use -i/--in-place with --set or --remove-key to edit the file directly.

              $ md frontmatter --file doc.md
              $ md frontmatter --key title --file doc.md
              $ md frontmatter --set "title=My Doc" --file doc.md -i
              $ md frontmatter --set "author.name=Jane" --file doc.md -i
              $ md frontmatter --remove-key draft --file doc.md -i
              $ md frontmatter --format json --file doc.md
            """
    )

    @Flag(name: .shortAndLong, help: "Edit the file in place")
    var inPlace: Bool = false

    @Option(name: .long, help: "Get a frontmatter value by key (supports dot syntax for nested keys)")
    var key: String?

    @Option(name: .long, help: "Set a frontmatter key=value (supports dot syntax for nested keys)")
    var set: String?

    @Option(name: .long, help: "Remove a frontmatter key (supports dot syntax for nested keys)")
    var removeKey: String?

    @Option(name: .long, help: "Output format for frontmatter (yaml, json, or toml)")
    var format: FrontmatterFormat?

    @OptionGroup var input: InputOptions

    func validate() throws {
        if inPlace && input.file == nil {
            throw ValidationError("Cannot use --in-place with --stdin")
        }
        // At most one action
        let actions = [key != nil, `set` != nil, removeKey != nil]
        let actionCount = actions.filter { $0 }.count
        if actionCount > 1 {
            throw ValidationError("Specify at most one of --key, --set, or --remove-key")
        }
        // --in-place only makes sense with --set or --remove-key
        if inPlace && `set` == nil && removeKey == nil {
            throw ValidationError("--in-place requires --set or --remove-key")
        }
    }

    func run() async throws {
        let content = try input.readContent()

        guard var frontmatter = Frontmatter.parse(content) else {
            if `set` != nil {
                // Create new frontmatter if setting a value
                let outputFormat = format ?? .yaml
                var fm = Frontmatter(format: outputFormat, data: [:], rawContent: "", body: content, originalContent: content)
                try applySet(&fm)
                let result = try fm.serialize()
                try output(result)
            } else if key != nil {
                // No frontmatter, nothing to get
                return
            } else if removeKey != nil {
                // No frontmatter, nothing to remove — output as-is
                print(content, terminator: "")
            } else {
                // No frontmatter found
                return
            }
            return
        }

        if let outputFormat = format {
            frontmatter.format = outputFormat
        }

        if let keyPath = key {
            // Get mode
            if let value = frontmatter.get(keyPath) {
                print(formatValue(value))
            }
        } else if `set` != nil {
            // Set mode
            try applySet(&frontmatter)
            let result = try frontmatter.serialize()
            try output(result)
        } else if let keyPath = removeKey {
            // Remove mode
            frontmatter.removeKey(keyPath)
            let result = try frontmatter.serialize()
            try output(result)
        } else {
            // Print all frontmatter (or full document if --format is specified)
            if format != nil {
                let result = try frontmatter.serialize()
                try output(result)
            } else {
                let serialized = try frontmatter.serializeData()
                print(serialized, terminator: "")
            }
        }
    }

    private func applySet(_ frontmatter: inout Frontmatter) throws {
        guard let setValue = `set` else { return }
        guard let equalsIndex = setValue.firstIndex(of: "=") else {
            throw ValidationError("--set value must be in key=value format")
        }
        let keyPath = String(setValue[setValue.startIndex..<equalsIndex])
        let valueStr = String(setValue[setValue.index(after: equalsIndex)...])
        let value = Frontmatter.parseValue(valueStr)
        frontmatter.set(keyPath, value: value)
    }

    private func output(_ content: String) throws {
        if inPlace, let file = input.file {
            try InputReader.write(content, to: file)
        } else {
            print(content, terminator: "")
        }
    }

    private func formatValue(_ value: Any) -> String {
        if let array = value as? [Any] {
            return array.map { "\($0)" }.joined(separator: "\n")
        }
        return "\(value)"
    }
}
