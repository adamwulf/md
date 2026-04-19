//
//  MD.swift
//  md
//
//  Created by Adam Wulf on 4/12/26.
//

import Foundation
import ArgumentParser
import MarkdownKit

@main
struct MD: AsyncParsableCommand {

    static var configuration = CommandConfiguration(
        commandName: "md",
        abstract: "A CLI tool for parsing and operating on Markdown files",
        discussion: """
            Blocks are structural markdown elements: headings, paragraphs, code \
            blocks, lists (ordered and unordered), blockquotes, tables, and \
            thematic breaks. All block indices are 1-based.

            Every command requires input via --file <path> or --stdin (but not both).
            """,
        version: "0.1.0",
        subcommands: [FormatCommand.self, TocCommand.self, BlocksCommand.self, LinesCommand.self, InsertAfterCommand.self, InsertBeforeCommand.self, RemoveCommand.self, ReplaceCommand.self, FrontmatterCommand.self, ListCommand.self]
    )
}
