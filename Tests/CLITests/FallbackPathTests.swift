//
//  FallbackPathTests.swift
//  md
//
//  The commands guard themselves a second time inside run(), and fall back to
//  a safe output when a value cannot be serialized. These tests reach those
//  paths — the in-place guard by clearing the file after parsing, and the
//  serialization failures with a YAML not-a-number, which JSON cannot hold.
//

import XCTest
@testable import md

final class FallbackPathTests: XCTestCase {

    private var scratch: ScratchDirectory!

    override func setUpWithError() throws {
        scratch = try ScratchDirectory()
    }

    override func tearDownWithError() throws {
        scratch = nil
    }

    // MARK: - The in-place guard inside run()

    // `validate()` already rejects --in-place without a file, so reaching the
    // guard inside `run()` means clearing the file after the command parsed.

    func testRemoveRefusesToWriteInPlaceWithoutAFile() async throws {
        let path = try scratch.write("# One\n\n# Two\n", to: "document.md")
        var command = try RemoveCommand.parse(["--in-place", "--file", path, "1"])
        let source = try scratch.read("document.md")
        command.input.file = nil

        await XCTAssertThrowsErrorMessage("Cannot use --in-place with --stdin") {
            try await StandardStream.withStandardInput(source) {
                try await command.run()
            }
        }
    }

    func testReplaceRefusesToWriteInPlaceWithoutAFile() async throws {
        let path = try scratch.write("# One\n\n# Two\n", to: "document.md")
        var command = try ReplaceCommand.parse(
            ["--in-place", "--file", path, "1", "# New"]
        )
        let source = try scratch.read("document.md")
        command.input.file = nil

        await XCTAssertThrowsErrorMessage("Cannot use --in-place with --stdin") {
            try await StandardStream.withStandardInput(source) {
                try await command.run()
            }
        }
    }

    func testInsertAfterRefusesToWriteInPlaceWithoutAFile() async throws {
        let path = try scratch.write("# One\n\n# Two\n", to: "document.md")
        var command = try InsertAfterCommand.parse(
            ["--in-place", "--file", path, "1", "New."]
        )
        let source = try scratch.read("document.md")
        command.input.file = nil

        await XCTAssertThrowsErrorMessage("Cannot use --in-place with --stdin") {
            try await StandardStream.withStandardInput(source) {
                try await command.run()
            }
        }
    }

    func testInsertBeforeRefusesToWriteInPlaceWithoutAFile() async throws {
        let path = try scratch.write("# One\n\n# Two\n", to: "document.md")
        var command = try InsertBeforeCommand.parse(
            ["--in-place", "--file", path, "1", "New."]
        )
        let source = try scratch.read("document.md")
        command.input.file = nil

        await XCTAssertThrowsErrorMessage("Cannot use --in-place with --stdin") {
            try await StandardStream.withStandardInput(source) {
                try await command.run()
            }
        }
    }

    // MARK: - A value JSON cannot hold

    /// YAML has a not-a-number literal; JSON does not, so JSONSerialization
    /// refuses it. That is the one realistic way to make serialization fail.
    func testYAMLNotANumberParsesAsADouble() throws {
        let frontmatter = try XCTUnwrap(
            Frontmatter.parse("---\nratio: .nan\n---\nBody\n")
        )
        let ratio = try XCTUnwrap(frontmatter.get("ratio") as? Double)
        XCTAssertTrue(ratio.isNaN, "expected a not-a-number, got \(ratio)")
    }

    /// The value handed to JSONSerialization must always be a valid JSON
    /// object. Non-finite values are normalized only after validation has
    /// produced the useful refusal that names their key.
    func testFrontmatterNormalizedForJSONIsAlwaysAValidJSONObject() throws {
        let frontmatter = try XCTUnwrap(
            Frontmatter.parse("---\nratio: .nan\n---\nBody\n")
        )
        let normalized = Frontmatter.normalizeForJSON(frontmatter.data)
        XCTAssertTrue(JSONSerialization.isValidJSONObject(normalized))
    }

    func testAnInfiniteFrontmatterValueAlsoNormalizesToValidJSON() throws {
        let frontmatter = try XCTUnwrap(
            Frontmatter.parse("---\nratio: .inf\n---\nBody\n")
        )
        let normalized = Frontmatter.normalizeForJSON(frontmatter.data)
        XCTAssertTrue(JSONSerialization.isValidJSONObject(normalized))
    }

    func testJSONSerializationRejectsANonFiniteValueAndNamesItsKey() throws {
        var frontmatter = try XCTUnwrap(
            Frontmatter.parse("---\nmeasurements:\n  ratio: .nan\n---\nBody\n")
        )
        frontmatter.format = .json

        XCTAssertThrowsError(try frontmatter.serializeData()) { error in
            XCTAssertEqual(
                error.localizedDescription,
                "JSON cannot represent the non-finite number at key path measurements.ratio"
            )
        }
    }

    func testJSONSerializationEscapesPunctuationInTheRejectedKeyPath() {
        let frontmatter = Frontmatter(
            format: .json,
            data: ["measurement.ratio\nraw": Double.infinity],
            rawContent: "",
            body: "",
            originalContent: ""
        )

        XCTAssertThrowsError(try frontmatter.serializeData()) { error in
            XCTAssertEqual(
                error.localizedDescription,
                "JSON cannot represent the non-finite number at key path " +
                    "[\"measurement.ratio\\nraw\"]"
            )
        }
    }

    func testAFiniteFrontmatterValueIsValidJSON() throws {
        let frontmatter = try XCTUnwrap(
            Frontmatter.parse("---\nratio: 1.5\n---\nBody\n")
        )
        XCTAssertTrue(
            JSONSerialization.isValidJSONObject(
                Frontmatter.normalizeForJSON(frontmatter.data)
            )
        )
    }

    func testFormatConvertsFrontmatterWhoseValuesJSONCanHold() {
        let output = FormatCommand.format(
            content: "---\nratio: 1.5\n---\n#    Heading\n",
            targetFrontmatter: .json
        )
        XCTAssertTrue(output.hasPrefix(";;;\n"), "got: \(output)")
        XCTAssertTrue(output.hasSuffix("# Heading\n"), "got: \(output)")
    }

    // MARK: - list: a projection list that is all separators

    func testAKeysListOfNothingButSeparatorsProjectsEverything() async throws {
        let url = scratch.url.appendingPathComponent("a.md")
        try Data("---\ntitle: A\nauthor: Jane\n---\n".utf8).write(to: url)

        let command = try ListCommand.parse(
            ["--keys", " , , ", scratch.url.path]
        )
        let output = try await StandardStream.capturingStandardOutput {
            try await command.run()
        }
        XCTAssertEqual(
            output,
            "== \(url.path) ==\nauthor: Jane\ntitle: A\n"
        )
    }
}
