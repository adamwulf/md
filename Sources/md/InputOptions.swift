//
//  InputOptions.swift
//  md
//
//  Created by Adam Wulf on 4/12/26.
//

import ArgumentParser
import Foundation
import MarkdownKit

struct InputOptions: ParsableArguments {
    @Option(name: .shortAndLong, help: "Path to the markdown file")
    var file: String?

    @Flag(name: .long, help: "Read from stdin")
    var stdin: Bool = false

    func validate() throws {
        if file != nil && stdin {
            throw ValidationError("Cannot specify both --file and --stdin")
        }
        if file == nil && !stdin {
            throw ValidationError("Must specify either --file or --stdin")
        }
    }

    func readContent() throws -> String {
        try readSource().content
    }

    func readSource() throws -> InputReader.Source {
        if let file = file {
            return try InputReader.readSource(from: file)
        } else {
            return InputReader.readSourceFromStdin()
        }
    }

    /// The block count of the document, for range checks in `validate()`,
    /// where a thrown error still names the subcommand in its usage. Returns
    /// nil on the stdin path — reading stdin here would consume the stream
    /// before `run()` reads it — and nil for a file that cannot be read, so
    /// `run()` reports that failure itself.
    func validationBlockCount() -> Int? {
        guard let file = file,
              let source = try? InputReader.readSource(from: file) else {
            return nil
        }
        return MarkdownParser().parseDocument(source.content).count
    }
}
