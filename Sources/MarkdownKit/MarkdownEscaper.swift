//
//  MarkdownEscaper.swift
//  md
//
//  Created by Adam Wulf on 8/4/26.
//

import Foundation

/// Where a run of literal text sits. This decides which characters can begin markdown
/// where they are, thus which of them need a backslash.
enum InlineTextContext {
    /// The text of a paragraph.
    case paragraph

    /// The text of a heading. A run of `#` at the end of the line is the closing
    /// sequence of the heading, and a reader takes it off.
    case heading

    /// The text of one cell of a table. A `|` divides one cell from the next, and no
    /// line begins inside a cell.
    case tableCell
}

/// Puts back the backslashes that `cmark` takes off the literal of a text node.
///
/// `cmark_node_get_literal` gives the text after a reader removes each backslash, thus
/// `\#` comes back as `#`. The text of a block goes back into a file, thus a marker
/// with no backslash becomes live markdown and the block divides, or changes its type.
///
/// A character gets a backslash only when it can begin markdown where it is. Text that
/// reads well must stay text that reads well: `a < b`, `snake_case_name` and
/// `issue #42` keep no backslash.
///
/// Where a character needs a second character to make markup, and that second
/// character can sit in another node of the same block, this always adds the
/// backslash. A backslash that a character does not need is safe, because a reader
/// shows `\*` as `*`. A pair that keeps no backslash is not safe, because it changes
/// what the text means. `MarkdownEscapeTests` holds each of those decisions.
enum MarkdownEscaper {

    /// Escape one literal from a text node.
    ///
    /// - Parameters:
    ///   - literal: the text of the node, with no backslashes in it.
    ///   - context: where the run of text sits.
    ///   - startsLine: true when the run of text begins a line of the block, thus a
    ///     block marker at its start is live.
    ///   - endsBlock: true when no other node follows in the block.
    ///   - isFollowedByLink: true when the next node in the block is a link, thus a
    ///     `!` at the end of this run would make an image.
    static func escape(
        _ literal: String,
        context: InlineTextContext,
        startsLine: Bool = false,
        endsBlock: Bool = false,
        isFollowedByLink: Bool = false
    ) -> String {
        let characters = Array(literal)
        guard !characters.isEmpty else { return literal }

        // Two rules look at a position and not at a character. They go into a set
        // first, thus one character never gets two backslashes.
        var byPosition: Set<Int> = []
        if startsLine, context != .tableCell, let index = blockMarkerIndex(in: characters) {
            byPosition.insert(index)
        }
        if context == .heading, endsBlock, let index = closingHashIndex(in: characters) {
            byPosition.insert(index)
        }

        var output = ""
        output.reserveCapacity(characters.count + 8)
        for (index, character) in characters.enumerated() {
            if byPosition.contains(index) || needsBackslash(
                at: index,
                in: characters,
                context: context,
                isFollowedByLink: isFollowedByLink
            ) {
                output.append("\\")
            }
            output.append(character)
        }
        return output
    }

    // MARK: - Rules for one character

    /// True when the character at `index` can begin markup in any part of a line.
    private static func needsBackslash(
        at index: Int,
        in characters: [Character],
        context: InlineTextContext,
        isFollowedByLink: Bool
    ) -> Bool {
        let character = characters[index]
        let next: Character? = index + 1 < characters.count ? characters[index + 1] : nil

        switch character {
        case "\\", "`", "*", "~", "[":
            // A backslash makes every other escape. The other four open a code span,
            // emphasis, strikethrough, or a link, and each one can do that between two
            // letters as well. The character that closes the pair can sit in another
            // node, thus these four always get a backslash.
            return true

        case "_":
            // An underscore between two letters or numbers makes no emphasis, thus
            // `snake_case_name` stays as it is. A neighbour outside this run of text
            // is not known, thus it counts as not a letter.
            let previous: Character? = index > 0 ? characters[index - 1] : nil
            return !(isWordCharacter(previous) && isWordCharacter(next))

        case "!":
            // A `!` before a `[` makes an image. The `[` can be the first character of
            // the next node.
            return next == "[" || (next == nil && isFollowedByLink)

        case "<":
            // A `<` can open an autolink, an email address, or an HTML tag. Before a
            // space or an operator it opens nothing, thus `a < b` stays as it is.
            return opensAngleMarkup(at: index, in: characters)

        case "&":
            // `&amp;`, `&#35;` and `&#x263A;` are character entities, and a reader
            // changes each one into the character it names.
            return beginsEntity(at: index, in: characters)

        case "|":
            // Only a table gives a `|` a meaning.
            return context == .tableCell

        default:
            return false
        }
    }

    // MARK: - Lookahead rules

    /// True when the `<` at `index` can open an autolink, an HTML tag, or an email
    /// address.
    ///
    /// The scheme of an autolink and the name of an HTML tag both begin with a letter,
    /// thus a number after the `<` is safe. The local part of an email address can
    /// begin with a number, thus a number is safe only when no `@` follows it in the
    /// same word.
    private static func opensAngleMarkup(at index: Int, in characters: [Character]) -> Bool {
        guard let next = index + 1 < characters.count ? characters[index + 1] : nil else { return false }

        if next.isASCIILetter || next == "/" || next == "!" || next == "?" {
            return true
        }
        guard next.isASCIIDigit else { return false }

        // An email address holds no space, and a `>` ends it.
        var scan = index + 1
        while scan < characters.count {
            let character = characters[scan]
            if character == "@" { return true }
            if character.isWhitespace || character == ">" || character == "<" { return false }
            scan += 1
        }
        return false
    }

    /// True when the `&` at `index` begins a character entity: a name, a decimal
    /// number, or a hexadecimal number, and then a `;`.
    ///
    /// A shape with no `;` is not an entity, thus `AT&T` and `&nbsp` stay as they are.
    /// This looks at the shape only, thus `&notaname;` gets a backslash that it does
    /// not need. That is safe, and it holds no list of every entity name.
    private static func beginsEntity(at index: Int, in characters: [Character]) -> Bool {
        var scan = index + 1
        guard scan < characters.count else { return false }

        let body: (Character) -> Bool
        if characters[scan] == "#" {
            scan += 1
            if scan < characters.count, characters[scan] == "x" || characters[scan] == "X" {
                scan += 1
                body = { $0.isASCIIHexDigit }
            } else {
                body = { $0.isASCIIDigit }
            }
        } else {
            body = { $0.isASCIIAlphanumeric }
        }

        // The longest name of an entity is 31 characters, thus this stops early on
        // text that holds no entity at all.
        let limit = min(characters.count, scan + 32)
        let start = scan
        while scan < limit, body(characters[scan]) {
            scan += 1
        }

        guard scan > start, scan < characters.count else { return false }
        return characters[scan] == ";"
    }

    // MARK: - Rules for a position

    /// The index of the character that would begin a new block if it kept no
    /// backslash: the `#` of a heading, the `-` or `+` of a bullet list, the `>` of a
    /// block quote, the `=` of a setext heading, or the `.` or `)` of an ordered list.
    ///
    /// A `*` can begin a bullet list as well, but it already gets a backslash
    /// everywhere.
    private static func blockMarkerIndex(in characters: [Character]) -> Int? {
        var index = 0
        while index < characters.count, characters[index] == " " || characters[index] == "\t" {
            index += 1
        }
        guard index < characters.count else { return nil }

        if "#>-+=".contains(characters[index]) {
            return index
        }

        // An ordered list marker is one or more numbers and then a `.` or a `)`.
        var scan = index
        while scan < characters.count, characters[scan].isASCIIDigit {
            scan += 1
        }
        if scan > index, scan < characters.count, characters[scan] == "." || characters[scan] == ")" {
            return scan
        }

        return nil
    }

    /// The index of the first `#` of a run of `#` that ends the text, with only spaces
    /// after it. A reader takes that run off the end of a heading line, thus the run
    /// needs a backslash to stay part of the heading.
    private static func closingHashIndex(in characters: [Character]) -> Int? {
        var end = characters.count
        while end > 0, characters[end - 1] == " " || characters[end - 1] == "\t" {
            end -= 1
        }

        var start = end
        while start > 0, characters[start - 1] == "#" {
            start -= 1
        }

        return start < end ? start : nil
    }

    // MARK: - Characters

    private static func isWordCharacter(_ character: Character?) -> Bool {
        guard let character else { return false }
        return character.isLetter || character.isNumber
    }
}

private extension Character {
    var isASCIIDigit: Bool { isASCII && isNumber }
    var isASCIILetter: Bool { isASCII && isLetter }
    var isASCIIAlphanumeric: Bool { isASCII && (isLetter || isNumber) }
    var isASCIIHexDigit: Bool { isASCII && isHexDigit }
}
