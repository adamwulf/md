//
//  InputOptions.swift
//  md
//
//  Created by Adam Wulf on 4/12/26.
//

import ArgumentParser
import Foundation

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
        if let file = file {
            return try InputReader.read(from: file)
        } else {
            return InputReader.readFromStdin()
        }
    }
}
