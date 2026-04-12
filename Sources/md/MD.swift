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
        version: "0.1.0",
        subcommands: [FormatCommand.self, TocCommand.self, BlocksCommand.self, LinesCommand.self, InsertAfterCommand.self, InsertBeforeCommand.self]
    )
}
