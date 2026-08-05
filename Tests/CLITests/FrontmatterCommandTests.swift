//
//  FrontmatterCommandTests.swift
//  md
//
//  Exercises `md frontmatter` through its four modes — read, --key, --set and
//  --remove-key — against documents that have frontmatter and documents that
//  do not, plus every combination its validator rejects.
//

import XCTest
@testable import md

final class FrontmatterCommandTests: XCTestCase {

    private var scratch: ScratchDirectory!

    override func setUpWithError() throws {
        scratch = try ScratchDirectory()
    }

    override func tearDownWithError() throws {
        scratch = nil
    }

    // MARK: - Helpers

    private func runFrontmatter(
        _ arguments: [String],
        on content: String
    ) async throws -> String {
        let path = try scratch.write(content, to: "document.md")
        let command = try FrontmatterCommand.parse(arguments + ["--file", path])
        return try await StandardStream.capturingStandardOutput {
            try await command.run()
        }
    }

    /// Runs the command in place and returns the file's contents afterwards.
    private func runFrontmatterInPlace(
        _ arguments: [String],
        on content: String
    ) async throws -> String {
        let path = try scratch.write(content, to: "document.md")
        let command = try FrontmatterCommand.parse(
            arguments + ["--in-place", "--file", path]
        )
        try await command.run()
        return try scratch.read("document.md")
    }

    private func jsonObject(from text: String) throws -> [String: Any] {
        try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any]
        )
    }

    // MARK: - validate()

    func testInPlaceWithStdinIsRejected() {
        XCTAssertThrowsError(
            try FrontmatterCommand.parse(["--in-place", "--stdin", "--set", "a=b"])
        ) { error in
            XCTAssertEqual(
                FrontmatterCommand.message(for: error),
                "Cannot use --in-place with --stdin"
            )
        }
    }

    func testKeyCombinedWithSetIsRejected() throws {
        let path = try scratch.write("---\na: 1\n---\n", to: "document.md")
        XCTAssertThrowsError(
            try FrontmatterCommand.parse(
                ["--key", "a", "--set", "a=2", "--file", path]
            )
        ) { error in
            XCTAssertEqual(
                FrontmatterCommand.message(for: error),
                "Specify at most one of --key, --set, or --remove-key"
            )
        }
    }

    func testKeyCombinedWithRemoveKeyIsRejected() throws {
        let path = try scratch.write("---\na: 1\n---\n", to: "document.md")
        XCTAssertThrowsError(
            try FrontmatterCommand.parse(
                ["--key", "a", "--remove-key", "a", "--file", path]
            )
        ) { error in
            XCTAssertEqual(
                FrontmatterCommand.message(for: error),
                "Specify at most one of --key, --set, or --remove-key"
            )
        }
    }

    func testSetCombinedWithRemoveKeyIsRejected() throws {
        let path = try scratch.write("---\na: 1\n---\n", to: "document.md")
        XCTAssertThrowsError(
            try FrontmatterCommand.parse(
                ["--set", "a=2", "--remove-key", "b", "--file", path]
            )
        ) { error in
            XCTAssertEqual(
                FrontmatterCommand.message(for: error),
                "Specify at most one of --key, --set, or --remove-key"
            )
        }
    }

    func testInPlaceWithoutSetOrRemoveKeyIsRejected() throws {
        let path = try scratch.write("---\na: 1\n---\n", to: "document.md")
        XCTAssertThrowsError(
            try FrontmatterCommand.parse(["--in-place", "--file", path])
        ) { error in
            XCTAssertEqual(
                FrontmatterCommand.message(for: error),
                "--in-place requires --set or --remove-key"
            )
        }
    }

    func testInPlaceWithKeyIsRejected() throws {
        let path = try scratch.write("---\na: 1\n---\n", to: "document.md")
        XCTAssertThrowsError(
            try FrontmatterCommand.parse(
                ["--in-place", "--key", "a", "--file", path]
            )
        ) { error in
            XCTAssertEqual(
                FrontmatterCommand.message(for: error),
                "--in-place requires --set or --remove-key"
            )
        }
    }

    func testInPlaceWithSetIsAccepted() throws {
        let path = try scratch.write("---\na: 1\n---\n", to: "document.md")
        XCTAssertNoThrow(
            try FrontmatterCommand.parse(
                ["--in-place", "--set", "a=2", "--file", path]
            )
        )
    }

    func testInPlaceWithRemoveKeyIsAccepted() throws {
        let path = try scratch.write("---\na: 1\n---\n", to: "document.md")
        XCTAssertNoThrow(
            try FrontmatterCommand.parse(
                ["--in-place", "--remove-key", "a", "--file", path]
            )
        )
    }

    // MARK: - Read mode

    func testReadModePrintsTheDataWithoutDelimitersOrBody() async throws {
        let output = try await runFrontmatter(
            [],
            on: "---\ntitle: Hello\n---\n# Heading\n"
        )
        XCTAssertEqual(output, "title: Hello\n")
    }

    func testReadModeSortsKeys() async throws {
        let output = try await runFrontmatter(
            [],
            on: "---\ntitle: Hello\nauthor: Jane\n---\nBody\n"
        )
        XCTAssertEqual(output, "author: Jane\ntitle: Hello\n")
    }

    func testReadModePreservesANullValue() async throws {
        let output = try await runFrontmatter(
            [],
            on: "---\npublished: null\n---\nBody\n"
        )
        XCTAssertEqual(output, "published: null\n")
    }

    func testReadModeConvertsToTheRequestedFormat() async throws {
        let output = try await runFrontmatter(
            ["--format", "json"],
            on: "---\ntitle: Hello\n---\nBody\n"
        )
        XCTAssertFalse(output.contains(";;;"), "got: \(output)")
        XCTAssertEqual(
            try jsonObject(from: output)["title"] as? String,
            "Hello"
        )
    }

    func testReadModePrintsNothingWhenThereIsNoFrontmatter() async throws {
        let output = try await runFrontmatter([], on: "# Heading\n\nBody.\n")
        XCTAssertEqual(output, "")
    }

    func testReadModePrintsNothingForEmptyFrontmatter() async throws {
        let output = try await runFrontmatter([], on: "---\n---\nBody\n")
        XCTAssertEqual(output, "")
    }

    func testReadModeOutputIsEmptyForContentWithoutFrontmatter() throws {
        XCTAssertEqual(
            try FrontmatterCommand.readModeOutput(
                content: "# Heading\n",
                format: .json
            ),
            ""
        )
    }

    // MARK: - --key

    func testKeyPrintsAScalarValue() async throws {
        let output = try await runFrontmatter(
            ["--key", "title"],
            on: "---\ntitle: Hello\n---\nBody\n"
        )
        XCTAssertEqual(output, "Hello\n")
    }

    func testKeyPrintsANestedValue() async throws {
        let output = try await runFrontmatter(
            ["--key", "author.name"],
            on: "---\nauthor:\n  name: Jane\n---\nBody\n"
        )
        XCTAssertEqual(output, "Jane\n")
    }

    func testKeyPrintsABooleanValue() async throws {
        let output = try await runFrontmatter(
            ["--key", "draft"],
            on: "---\ndraft: true\n---\nBody\n"
        )
        XCTAssertEqual(output, "true\n")
    }

    func testKeyPrintsAnIntegerValue() async throws {
        let output = try await runFrontmatter(
            ["--key", "count"],
            on: "---\ncount: 42\n---\nBody\n"
        )
        XCTAssertEqual(output, "42\n")
    }

    func testKeyPrintsArrayElementsOnePerLine() async throws {
        let output = try await runFrontmatter(
            ["--key", "tags"],
            on: "---\ntags:\n  - swift\n  - markdown\n---\nBody\n"
        )
        XCTAssertEqual(output, "swift\nmarkdown\n")
    }

    func testKeyPrintsNullValuesAsYAMLNulls() async throws {
        let scalarOutput = try await runFrontmatter(
            ["--key", "published"],
            on: "---\npublished: null\n---\nBody\n"
        )
        XCTAssertEqual(scalarOutput, "null\n")

        let arrayOutput = try await runFrontmatter(
            ["--key", "values"],
            on: "---\nvalues: [first, null]\n---\nBody\n"
        )
        XCTAssertEqual(arrayOutput, "first\nnull\n")
    }

    func testKeyPrintsNothingWhenTheKeyIsAbsent() async throws {
        let output = try await runFrontmatter(
            ["--key", "missing"],
            on: "---\ntitle: Hello\n---\nBody\n"
        )
        XCTAssertEqual(output, "")
    }

    func testKeyPrintsNothingWhenThereIsNoFrontmatter() async throws {
        let output = try await runFrontmatter(
            ["--key", "title"],
            on: "# Heading\n"
        )
        XCTAssertEqual(output, "")
    }

    // MARK: - --set

    func testSetReplacesAnExistingValueAndKeepsTheBody() async throws {
        let output = try await runFrontmatter(
            ["--set", "title=New"],
            on: "---\ntitle: Old\n---\n# Heading\n"
        )
        XCTAssertEqual(output, "---\ntitle: New\n---\n# Heading\n")
    }

    func testSetAddsANewKeyAlongsideTheExistingOnes() async throws {
        let output = try await runFrontmatter(
            ["--set", "draft=true"],
            on: "---\ntitle: Hello\n---\nBody\n"
        )
        XCTAssertEqual(output, "---\ndraft: true\ntitle: Hello\n---\nBody\n")
    }

    func testSetCreatesNestedDictionariesForDottedKeys() async throws {
        let output = try await runFrontmatter(
            ["--set", "author.name=Jane"],
            on: "---\ntitle: Hello\n---\nBody\n"
        )
        XCTAssertEqual(
            output,
            "---\nauthor:\n  name: Jane\ntitle: Hello\n---\nBody\n"
        )
    }

    func testSetParsesTheValueIntoItsNaturalType() async throws {
        let output = try await runFrontmatter(
            ["--set", "count=42"],
            on: "---\ntitle: Hello\n---\nBody\n"
        )
        XCTAssertEqual(output, "---\ncount: 42\ntitle: Hello\n---\nBody\n")
    }

    func testSetAcceptsAnEmptyValue() async throws {
        let output = try await runFrontmatter(
            ["--set", "title="],
            on: "---\ntitle: Hello\n---\nBody\n"
        )
        XCTAssertEqual(output, "---\ntitle: ''\n---\nBody\n")
    }

    func testSetKeepsTheValueAfterLaterEqualsSigns() async throws {
        let output = try await runFrontmatter(
            ["--set", "equation=a=b"],
            on: "---\ntitle: Hello\n---\nBody\n"
        )
        XCTAssertEqual(
            output,
            "---\nequation: a=b\ntitle: Hello\n---\nBody\n"
        )
    }

    func testSetWithoutAnEqualsSignIsRejected() async throws {
        let path = try scratch.write("---\ntitle: Hello\n---\nBody\n", to: "document.md")
        let command = try FrontmatterCommand.parse(["--set", "title", "--file", path])
        await XCTAssertThrowsErrorMessage(
            "--set value must be in key=value format"
        ) {
            try await command.run()
        }
    }

    func testSetCreatesYAMLFrontmatterWhenTheDocumentHasNone() async throws {
        let output = try await runFrontmatter(
            ["--set", "title=Hello"],
            on: "# Heading\n"
        )
        XCTAssertEqual(output, "---\ntitle: Hello\n---\n# Heading\n")
    }

    func testSetCreatesFrontmatterInTheRequestedFormat() async throws {
        let output = try await runFrontmatter(
            ["--set", "title=Hello", "--format", "toml"],
            on: "# Heading\n"
        )
        XCTAssertTrue(output.hasPrefix("+++\n"), "got: \(output)")
        XCTAssertTrue(output.hasSuffix("+++\n# Heading\n"), "got: \(output)")
        let reparsed = try XCTUnwrap(Frontmatter.parse(output))
        XCTAssertEqual(reparsed.format, .toml)
        XCTAssertEqual(reparsed.get("title") as? String, "Hello")
    }

    func testSetConvertsExistingFrontmatterToTheRequestedFormat() async throws {
        let output = try await runFrontmatter(
            ["--set", "draft=true", "--format", "json"],
            on: "---\ntitle: Hello\n---\nBody\n"
        )
        XCTAssertTrue(output.hasPrefix(";;;\n"), "got: \(output)")
        XCTAssertTrue(output.hasSuffix(";;;\nBody\n"), "got: \(output)")
        let reparsed = try XCTUnwrap(Frontmatter.parse(output))
        XCTAssertEqual(reparsed.format, .json)
        XCTAssertEqual(reparsed.get("title") as? String, "Hello")
        XCTAssertEqual(reparsed.get("draft") as? Bool, true)
    }

    func testSetInPlaceRewritesTheFile() async throws {
        let written = try await runFrontmatterInPlace(
            ["--set", "title=New"],
            on: "---\ntitle: Old\n---\n# Heading\n"
        )
        XCTAssertEqual(written, "---\ntitle: New\n---\n# Heading\n")
    }

    func testSetInPlaceCreatesFrontmatterWhenTheDocumentHasNone() async throws {
        let written = try await runFrontmatterInPlace(
            ["--set", "title=Hello"],
            on: "# Heading\n"
        )
        XCTAssertEqual(written, "---\ntitle: Hello\n---\n# Heading\n")
    }

    func testSetWritesNothingToStandardOutputWhenEditingInPlace() async throws {
        let path = try scratch.write("---\ntitle: Old\n---\nBody\n", to: "document.md")
        let command = try FrontmatterCommand.parse(
            ["--set", "title=New", "--in-place", "--file", path]
        )
        let output = try await StandardStream.capturingStandardOutput {
            try await command.run()
        }
        XCTAssertEqual(output, "")
    }

    // MARK: - --remove-key

    func testRemoveKeyDropsThatKeyOnly() async throws {
        let output = try await runFrontmatter(
            ["--remove-key", "draft"],
            on: "---\ntitle: Hello\ndraft: true\n---\nBody\n"
        )
        XCTAssertEqual(output, "---\ntitle: Hello\n---\nBody\n")
    }

    func testRemoveKeyDropsANestedKey() async throws {
        let output = try await runFrontmatter(
            ["--remove-key", "author.email"],
            on: "---\nauthor:\n  name: Jane\n  email: j@e.com\n---\nBody\n"
        )
        XCTAssertEqual(output, "---\nauthor:\n  name: Jane\n---\nBody\n")
    }

    func testRemoveKeyLeavesTheDataAloneWhenTheKeyIsAbsent() async throws {
        let output = try await runFrontmatter(
            ["--remove-key", "missing"],
            on: "---\ntitle: Hello\n---\nBody\n"
        )
        XCTAssertEqual(output, "---\ntitle: Hello\n---\nBody\n")
    }

    func testRemovingTheLastKeyLeavesBareDelimiters() async throws {
        let output = try await runFrontmatter(
            ["--remove-key", "title"],
            on: "---\ntitle: Hello\n---\nBody\n"
        )
        XCTAssertEqual(output, "---\n---\nBody\n")
    }

    func testRemoveKeyEchoesTheDocumentUnchangedWhenThereIsNoFrontmatter() async throws {
        let content = "# Heading\n\nBody.\n"
        let output = try await runFrontmatter(["--remove-key", "title"], on: content)
        XCTAssertEqual(output, content)
    }

    func testRemoveKeyInPlaceRewritesTheFile() async throws {
        let written = try await runFrontmatterInPlace(
            ["--remove-key", "draft"],
            on: "---\ntitle: Hello\ndraft: true\n---\nBody\n"
        )
        XCTAssertEqual(written, "---\ntitle: Hello\n---\nBody\n")
    }

    // MARK: - Input selection

    func testReadsFromStandardInputWhenAskedTo() async throws {
        let command = try FrontmatterCommand.parse(["--key", "title", "--stdin"])
        let output = try await StandardStream.withStandardInput(
            "---\ntitle: Piped\n---\nBody\n"
        ) {
            try await StandardStream.capturingStandardOutput {
                try await command.run()
            }
        }
        XCTAssertEqual(output, "Piped\n")
    }

    func testPreservesAByteOrderMarkOnStandardOutput() async throws {
        let path = scratch.url.appendingPathComponent("bom.md")
        var source = Data([0xEF, 0xBB, 0xBF])
        source.append(contentsOf: Data("---\ntitle: Old\n---\nBody\n".utf8))
        try source.write(to: path)

        let command = try FrontmatterCommand.parse(
            ["--set", "title=New", "--file", path.path]
        )
        let output = try await StandardStream.capturingStandardOutputData {
            try await command.run()
        }
        var expected = Data([0xEF, 0xBB, 0xBF])
        expected.append(contentsOf: Data("---\ntitle: New\n---\nBody\n".utf8))
        XCTAssertEqual(output, expected)
    }
}
