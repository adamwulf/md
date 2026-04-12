//
//  FmtCommand.swift
//  md
//
//  Created by Adam Wulf on 4/12/26.
//

import ArgumentParser
import Foundation
import MarkdownKit

struct FormatCommand: AsyncParsableCommand {

    static var configuration = CommandConfiguration(
        commandName: "format",
        abstract: "Parse and normalize a markdown file"
    )

    @Argument(help: "Path to the markdown file (reads stdin if omitted)")
    var file: String?

    func run() async throws {
        let content = try InputReader.read(from: file)
        let parser = MarkdownParser()
        let blocks = parser.parse(content)
        print(BlockFormatter.format(blocks), terminator: "")
    }
}
