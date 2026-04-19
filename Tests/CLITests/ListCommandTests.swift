//
//  ListCommandTests.swift
//  md
//
//  Created by Adam Wulf on 4/12/26.
//

import XCTest
@testable import md

final class ListCommandTests: XCTestCase {

    private var tempRoot: URL!

    override func setUpWithError() throws {
        tempRoot = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("md-list-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempRoot)
    }

    // MARK: - Helpers

    private func write(_ contents: String, to relativePath: String) throws -> URL {
        let url = tempRoot.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try contents.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    private func makeCommand(
        _ directories: [String]? = nil,
        recursive: Bool = false,
        format: FrontmatterFormat = .yaml,
        output: ListOutputFormat = .plain,
        key: String? = nil,
        keys: String? = nil,
        missing: ListMissingMode = .include,
        followSymlinks: Bool = false,
        sort: ListSortOrder = .path
    ) throws -> ListCommand {
        let dirs = directories ?? [tempRoot.path]
        var args = dirs
        if recursive { args.append("--recursive") }
        args.append(contentsOf: ["--format", format.rawValue])
        args.append(contentsOf: ["--output", output.rawValue])
        if let key = key { args.append(contentsOf: ["--key", key]) }
        if let keys = keys { args.append(contentsOf: ["--keys", keys]) }
        args.append(contentsOf: ["--missing", missing.rawValue])
        if followSymlinks { args.append("--follow-symlinks") }
        args.append(contentsOf: ["--sort", sort.rawValue])
        return try ListCommand.parse(args)
    }

    // MARK: - Walking

    func testCollectsOnlyMdFiles() throws {
        _ = try write("---\ntitle: A\n---\nbody\n", to: "a.md")
        _ = try write("not markdown", to: "readme.txt")
        _ = try write("---\ntitle: B\n---\nbody\n", to: "b.md")

        let cmd = try makeCommand()
        let entries = try cmd.collectEntries()
        XCTAssertEqual(entries.map { ($0.path as NSString).lastPathComponent }, ["a.md", "b.md"])
    }

    func testNonRecursiveSkipsSubdirectories() throws {
        _ = try write("---\ntitle: Top\n---\n", to: "top.md")
        _ = try write("---\ntitle: Nested\n---\n", to: "sub/nested.md")

        let cmd = try makeCommand()
        let names = try cmd.collectEntries().map { ($0.path as NSString).lastPathComponent }
        XCTAssertEqual(names, ["top.md"])
    }

    func testRecursiveIncludesSubdirectories() throws {
        _ = try write("---\ntitle: Top\n---\n", to: "top.md")
        _ = try write("---\ntitle: Nested\n---\n", to: "sub/nested.md")

        let cmd = try makeCommand(recursive: true)
        let names = try cmd.collectEntries().map { ($0.path as NSString).lastPathComponent }.sorted()
        XCTAssertEqual(names, ["nested.md", "top.md"])
    }

    func testMissingDirectoryEmitsStderrAndContinues() throws {
        _ = try write("---\ntitle: A\n---\n", to: "a.md")
        let cmd = try makeCommand([tempRoot.path, "/does/not/exist"])
        let entries = try cmd.collectEntries()
        XCTAssertEqual(entries.count, 1)
    }

    // MARK: - Missing-mode filtering

    func testMissingIncludeKeepsFilesWithoutFrontmatter() throws {
        _ = try write("---\ntitle: A\n---\n", to: "a.md")
        _ = try write("# just a heading\n", to: "b.md")

        let cmd = try makeCommand(missing: .include)
        let entries = try cmd.collectEntries()
        XCTAssertEqual(entries.count, 2)
        XCTAssertNotNil(entries[0].frontmatter)
        XCTAssertNil(entries[1].frontmatter)
    }

    func testMissingSkipDropsFilesWithoutFrontmatter() throws {
        _ = try write("---\ntitle: A\n---\n", to: "a.md")
        _ = try write("# no fm\n", to: "b.md")

        let cmd = try makeCommand(missing: .skip)
        let entries = try cmd.collectEntries()
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries[0].frontmatter?.get("title") as? String, "A")
    }

    func testMissingOnlyReturnsFilesWithoutFrontmatter() throws {
        _ = try write("---\ntitle: A\n---\n", to: "a.md")
        _ = try write("# no fm\n", to: "b.md")

        let cmd = try makeCommand(missing: .only)
        let entries = try cmd.collectEntries()
        XCTAssertEqual(entries.count, 1)
        XCTAssertNil(entries[0].frontmatter)
    }

    // MARK: - Sort

    func testSortByName() throws {
        _ = try write("---\ntitle: Z\n---\n", to: "z.md")
        _ = try write("---\ntitle: A\n---\n", to: "a.md")

        let cmd = try makeCommand(sort: .name)
        let names = try cmd.collectEntries().map { ($0.path as NSString).lastPathComponent }
        XCTAssertEqual(names, ["a.md", "z.md"])
    }

    // MARK: - Plain output

    func testPlainOutputDefaultYAML() throws {
        _ = try write("---\ntitle: Hello\n---\n", to: "a.md")
        _ = try write("# no fm\n", to: "b.md")

        let cmd = try makeCommand()
        let out = cmd.renderPlain(try cmd.collectEntries())
        XCTAssertTrue(out.contains("== "))
        XCTAssertTrue(out.contains("a.md =="))
        XCTAssertTrue(out.contains("title: Hello"))
        XCTAssertTrue(out.contains("b.md =="))
        XCTAssertTrue(out.contains("(no frontmatter)"))
    }

    func testPlainOutputConvertsToJSONWithFormatFlag() throws {
        _ = try write("+++\ntitle = \"Hi\"\n+++\n", to: "a.md")

        let cmd = try makeCommand(format: .json)
        let out = cmd.renderPlain(try cmd.collectEntries())
        XCTAssertTrue(out.contains("\"title\""))
        XCTAssertTrue(out.contains("\"Hi\""))
    }

    func testPlainKeyProjectionTSV() throws {
        _ = try write("---\ntitle: First\n---\n", to: "a.md")
        _ = try write("---\ntitle: Second\n---\n", to: "b.md")
        _ = try write("---\nauthor: Jane\n---\n", to: "c.md")

        let cmd = try makeCommand(key: "title")
        let out = cmd.renderPlain(try cmd.collectEntries())
        // c.md has no title and should be skipped
        XCTAssertFalse(out.contains("c.md"))
        let lines = out.split(separator: "\n").map(String.init)
        XCTAssertEqual(lines.count, 2)
        XCTAssertTrue(lines[0].hasSuffix("\tFirst"))
        XCTAssertTrue(lines[1].hasSuffix("\tSecond"))
    }

    // MARK: - JSON output

    func testJSONOutputShape() throws {
        _ = try write("---\ntitle: Hello\ntags: [a, b]\n---\n", to: "a.md")
        _ = try write("# no fm\n", to: "b.md")

        let cmd = try makeCommand(output: .json)
        let out = try cmd.renderJSON(try cmd.collectEntries())
        let data = Data(out.utf8)
        let array = try JSONSerialization.jsonObject(with: data) as? [[String: Any]]
        XCTAssertEqual(array?.count, 2)

        let first = array?[0]
        XCTAssertEqual(first?["format"] as? String, "yaml")
        let fm = first?["frontmatter"] as? [String: Any]
        XCTAssertEqual(fm?["title"] as? String, "Hello")

        let second = array?[1]
        XCTAssertTrue(second?["frontmatter"] is NSNull)
        XCTAssertTrue(second?["format"] is NSNull)
    }

    func testNDJSONOutputEmitsOnePerLine() throws {
        _ = try write("---\ntitle: A\n---\n", to: "a.md")
        _ = try write("---\ntitle: B\n---\n", to: "b.md")

        let cmd = try makeCommand(output: .ndjson)
        let out = try cmd.renderNDJSON(try cmd.collectEntries())
        let lines = out.split(separator: "\n").map(String.init)
        XCTAssertEqual(lines.count, 2)
        for line in lines {
            let obj = try JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any]
            XCTAssertNotNil(obj?["path"])
        }
    }

    func testKeysProjectionSubsetsFrontmatter() throws {
        _ = try write("---\ntitle: Hello\nauthor: Jane\ndraft: true\n---\n", to: "a.md")

        let cmd = try makeCommand(output: .json, keys: "title,author")
        let out = try cmd.renderJSON(try cmd.collectEntries())
        let array = try JSONSerialization.jsonObject(with: Data(out.utf8)) as? [[String: Any]]
        let fm = array?[0]["frontmatter"] as? [String: Any]
        XCTAssertEqual(fm?["title"] as? String, "Hello")
        XCTAssertEqual(fm?["author"] as? String, "Jane")
        XCTAssertNil(fm?["draft"])
    }

    func testKeysProjectionNestedPath() throws {
        _ = try write("---\nauthor:\n  name: Jane\n  email: j@e.com\nother: x\n---\n", to: "a.md")

        let cmd = try makeCommand(output: .json, keys: "author.name")
        let out = try cmd.renderJSON(try cmd.collectEntries())
        let array = try JSONSerialization.jsonObject(with: Data(out.utf8)) as? [[String: Any]]
        let fm = array?[0]["frontmatter"] as? [String: Any]
        let author = fm?["author"] as? [String: Any]
        XCTAssertEqual(author?["name"] as? String, "Jane")
        XCTAssertNil(author?["email"])
        XCTAssertNil(fm?["other"])
    }

    // MARK: - Validation

    func testRejectsBothKeyAndKeys() {
        XCTAssertThrowsError(try makeCommand(key: "a", keys: "b,c"))
    }

    func testRejectsEmptyDirectoryList() {
        // ArgumentParser flags [String] with no values as zero-length; our validate() rejects it.
        XCTAssertThrowsError(try ListCommand.parse([]))
    }
}
