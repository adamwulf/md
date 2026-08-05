//
//  ListCommandCoverageTests.swift
//  md
//
//  Covers the parts of `md list` the existing suite does not reach: run()
//  itself, mtime ordering, unreadable files and directories, and the shapes
//  each emitter produces for frontmatter that projects down to nothing.
//

import XCTest
@testable import md

final class ListCommandCoverageTests: XCTestCase {

    private var scratch: ScratchDirectory!

    override func setUpWithError() throws {
        scratch = try ScratchDirectory()
    }

    override func tearDownWithError() throws {
        // Anything the tests made unreadable has to be opened back up before
        // the scratch directory can remove it.
        if let children = try? FileManager.default.contentsOfDirectory(
            at: scratch.url,
            includingPropertiesForKeys: nil
        ) {
            for child in children {
                chmod(child.path, 0o700)
            }
        }
        scratch = nil
    }

    // MARK: - Helpers

    @discardableResult
    private func write(_ contents: String, to relativePath: String) throws -> URL {
        let url = scratch.url.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data(contents.utf8).write(to: url)
        return url
    }

    private func runList(_ arguments: [String] = []) async throws -> String {
        let command = try ListCommand.parse(arguments + [scratch.url.path])
        return try await StandardStream.capturingStandardOutput {
            try await command.run()
        }
    }

    private func setModificationDate(_ date: Date, on url: URL) throws {
        try FileManager.default.setAttributes(
            [.modificationDate: date],
            ofItemAtPath: url.path
        )
    }

    // MARK: - run()

    func testRunWritesTheRenderedListingToStandardOutput() async throws {
        let url = try write("---\ntitle: Only\n---\nBody\n", to: "only.md")
        let output = try await runList()
        XCTAssertEqual(output, "== \(url.path) ==\ntitle: Only\n")
    }

    func testRunWritesNothingForAnEmptyDirectory() async throws {
        let output = try await runList()
        XCTAssertEqual(output, "")
    }

    func testRunAddsNoTrailingNewlineOfItsOwn() async throws {
        try write("---\ntitle: A\n---\n", to: "a.md")
        let output = try await runList(["--output", "ndjson"])
        XCTAssertEqual(output.hasSuffix("}\n"), true, "got: \(output)")
        XCTAssertFalse(output.hasSuffix("\n\n"), "got: \(output)")
    }

    // MARK: - Sorting

    func testSortByModificationTimePutsTheOldestFirst() async throws {
        let older = try write("---\ntitle: Older\n---\n", to: "z-older.md")
        let newer = try write("---\ntitle: Newer\n---\n", to: "a-newer.md")
        try setModificationDate(Date(timeIntervalSince1970: 1_000), on: older)
        try setModificationDate(Date(timeIntervalSince1970: 2_000), on: newer)

        let output = try await runList(["--sort", "mtime", "--key", "title"])
        XCTAssertEqual(
            output,
            "\(older.path)\tOlder\n\(newer.path)\tNewer\n"
        )
    }

    func testSortByPathIsTheDefault() async throws {
        try write("---\ntitle: B\n---\n", to: "b.md")
        try write("---\ntitle: A\n---\n", to: "a.md")

        let output = try await runList(["--key", "title"])
        let titles = output
            .split(separator: "\n")
            .compactMap { $0.split(separator: "\t").last.map(String.init) }
        XCTAssertEqual(titles, ["A", "B"])
    }

    func testSortByNameIgnoresTheDirectoryPart() async throws {
        try write("---\ntitle: Nested\n---\n", to: "zzz/aaa.md")
        try write("---\ntitle: Top\n---\n", to: "bbb.md")

        let output = try await runList(["-r", "--sort", "name", "--key", "title"])
        let titles = output
            .split(separator: "\n")
            .compactMap { $0.split(separator: "\t").last.map(String.init) }
        XCTAssertEqual(titles, ["Nested", "Top"])
    }

    // MARK: - Files and directories that cannot be read

    func testAnUnreadableFileIsListedWithoutFrontmatter() async throws {
        let unreadable = try write("---\ntitle: Secret\n---\n", to: "secret.md")
        XCTAssertEqual(chmod(unreadable.path, 0o000), 0)
        defer { chmod(unreadable.path, 0o600) }

        let output = try await runList()
        XCTAssertEqual(output, "== \(unreadable.path) ==\n(no frontmatter)\n")
    }

    func testAnUnreadableSubdirectoryDoesNotStopTheWalk() async throws {
        let readable = try write("---\ntitle: Readable\n---\n", to: "readable.md")
        try write("---\ntitle: Hidden\n---\n", to: "locked/hidden.md")
        let locked = scratch.url.appendingPathComponent("locked")
        XCTAssertEqual(chmod(locked.path, 0o000), 0)
        defer { chmod(locked.path, 0o700) }

        let output = try await runList(["-r", "--key", "title"])
        XCTAssertEqual(output, "\(readable.path)\tReadable\n")
    }

    // MARK: - Frontmatter that projects down to nothing

    func testAFileWithEmptyFrontmatterIsLabelledAsSuch() async throws {
        let url = try write("---\n---\nBody\n", to: "empty.md")
        let output = try await runList()
        XCTAssertEqual(output, "== \(url.path) ==\n(empty frontmatter)\n")
    }

    func testAProjectionThatMatchesNothingLeavesTheBlockEmpty() async throws {
        let url = try write("---\ntitle: A\n---\n", to: "a.md")
        let output = try await runList(["--keys", "absent"])
        XCTAssertEqual(output, "== \(url.path) ==\n(empty frontmatter)\n")
    }

    func testAProjectionThatMatchesNothingIsNullInJSON() async throws {
        try write("---\ntitle: A\n---\n", to: "a.md")
        let output = try await runList(["--output", "json", "--keys", "absent"])
        let array = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(output.utf8)) as? [[String: Any]]
        )
        XCTAssertEqual(array.count, 1)
        XCTAssertEqual(array[0]["format"] as? String, "yaml")
        XCTAssertTrue(array[0]["frontmatter"] is NSNull)
    }

    func testAFileWithoutFrontmatterIsNullInNDJSON() async throws {
        let url = try write("# No frontmatter\n", to: "a.md")
        let output = try await runList(["--output", "ndjson"])
        let record = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(output.utf8)) as? [String: Any]
        )
        XCTAssertEqual(record["path"] as? String, url.path)
        XCTAssertTrue(record["format"] is NSNull)
        XCTAssertTrue(record["frontmatter"] is NSNull)
    }

    // MARK: - Scalar formatting in plain output

    func testAKeyHoldingAnArrayIsJoinedWithCommas() async throws {
        let url = try write("---\ntags:\n  - one\n  - two\n---\n", to: "a.md")
        let output = try await runList(["--key", "tags"])
        XCTAssertEqual(output, "\(url.path)\tone,two\n")
    }

    func testAKeyHoldingADictionaryIsRenderedAsCompactJSON() async throws {
        let url = try write("---\nauthor:\n  name: Jane\n---\n", to: "a.md")
        let output = try await runList(["--key", "author"])
        XCTAssertEqual(output, "\(url.path)\t{\"name\":\"Jane\"}\n")
    }

    func testAKeyHoldingABooleanPrintsTheBoolean() async throws {
        let url = try write("---\ndraft: true\n---\n", to: "a.md")
        let output = try await runList(["--key", "draft"])
        XCTAssertEqual(output, "\(url.path)\ttrue\n")
    }

    func testAKeyHoldingAnIntegerPrintsTheInteger() async throws {
        let url = try write("---\ncount: 42\n---\n", to: "a.md")
        let output = try await runList(["--key", "count"])
        XCTAssertEqual(output, "\(url.path)\t42\n")
    }

    func testAKeyHoldingADatePrintsAnInternetDateTimeString() async throws {
        let url = try write("---\ndate: 2026-04-18\n---\n", to: "a.md")
        let output = try await runList(["--key", "date"])
        XCTAssertEqual(output, "\(url.path)\t2026-04-18T00:00:00Z\n")
    }

    // MARK: - Plain output separators

    func testPlainOutputSeparatesFilesWithABlankLine() async throws {
        let first = try write("---\ntitle: A\n---\n", to: "a.md")
        let second = try write("---\ntitle: B\n---\n", to: "b.md")
        let output = try await runList()
        XCTAssertEqual(
            output,
            "== \(first.path) ==\ntitle: A\n\n== \(second.path) ==\ntitle: B\n"
        )
    }

    // MARK: - Validation

    func testAtLeastOneDirectoryIsRequired() throws {
        // ArgumentParser rejects the empty array before validate() runs, so the
        // guard in validate() is reachable only by parsing a real directory and
        // then clearing the list.
        var command = try ListCommand.parse([scratch.url.path])
        command.directories = []
        XCTAssertThrowsError(try command.validate()) { error in
            XCTAssertEqual(
                "\(error)",
                "md list: expected at least one directory"
            )
        }
    }

    func testAFileGivenInPlaceOfADirectoryYieldsNoEntries() async throws {
        let file = try write("---\ntitle: A\n---\n", to: "a.md")
        let command = try ListCommand.parse([file.path])
        let output = try await StandardStream.capturingStandardOutput {
            try await command.run()
        }
        XCTAssertEqual(output, "")
    }
}
