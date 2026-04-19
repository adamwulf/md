# md

A Swift command line tool for parsing and operating on Markdown files. Uses [cmark-gfm](https://github.com/apple/swift-cmark) for GitHub Flavored Markdown parsing.

## Installation

Install globally using [Mint](https://github.com/yonaskolb/Mint):

```bash
mint install adamwulf/md@main --force
```

Or build from source:

```bash
swift build -c release
cp .build/release/md /usr/local/bin/
```

## Usage

All commands require either `--file <path>` or `--stdin` to specify input.

### Format

Parse and normalize a markdown file:

```bash
md format --file README.md
cat README.md | md format --stdin
```

### Table of Contents

Print a table of contents with dot-fill and aligned numbers. Requires `--lines` or `--blocks`:

```bash
md toc --lines --file README.md
md toc --blocks --file README.md
```

### Blocks

List, count, or print blocks by index (1-based):

```bash
md blocks --file README.md              # list all blocks with summaries
md blocks --count --file README.md      # print number of blocks
md blocks 2 --file README.md            # print block 2
md blocks 2 5 --file README.md          # print blocks 2-5
```

### Lines

List, count, or print lines by number (1-based):

```bash
md lines --file README.md               # list all lines with numbers
md lines --count --file README.md        # print number of lines
md lines 10 --file README.md            # print line 10
md lines 10 20 --file README.md         # print lines 10-20
```

### Insert

Insert markdown content before or after a block (1-based index):

```bash
md insert-after 1 "New paragraph." --file README.md
md insert-before 3 "## New Section" --file README.md
```

Use `-i` to edit the file in place:

```bash
md insert-after 1 "New paragraph." --file README.md -i
```

### Remove

Remove one or more blocks (1-based index):

```bash
md remove 3 --file README.md            # remove block 3
md remove 2 4 --file README.md          # remove blocks 2-4
md remove 3 --file README.md -i         # remove in place
```

### Replace

Replace one or more blocks with new markdown content:

```bash
md replace 1 "# New Title" --file README.md           # replace block 1
md replace 2 4 "Replacement." --file README.md         # replace blocks 2-4
md replace 1 "# New Title" --file README.md -i         # replace in place
```

### Frontmatter

Read, set, or remove frontmatter key/value pairs. Supports YAML (`---`), TOML (`+++`), and JSON (`;;;`) delimiters.

```bash
md frontmatter --file doc.md                          # print frontmatter data
md frontmatter --key title --file doc.md              # get a specific key
md frontmatter --key author.name --file doc.md        # nested key via dot syntax
md frontmatter --set "title=My Doc" --file doc.md -i  # set a key in place
md frontmatter --set "author.name=Jane" --file doc.md -i  # set a nested key
md frontmatter --remove-key draft --file doc.md -i    # remove a key in place
md frontmatter --format json --file doc.md            # convert output to JSON
```

Setting a key on a file without frontmatter creates new YAML frontmatter (or the format specified by `--format`):

```bash
md frontmatter --set "title=Hello" --file plain.md
md frontmatter --set "title=Hello" --format toml --file plain.md
```

### List

List frontmatter for every `.md` file in one or more directories. Output defaults to YAML, one block per file.

```bash
md list ./notes                                       # top-level .md files
md list -r ./notes                                    # recurse into subdirectories
md list ./notes --format json                         # normalize all frontmatter to JSON
md list ./notes --key title                           # path<TAB>value lines, one per file
md list ./notes --keys title,author                   # project a subset of keys
md list -r . --output json                            # single JSON array of {path, format, frontmatter}
md list -r . --output ndjson                          # one JSON object per line
md list ./notes --missing skip                        # omit files without frontmatter
md list ./notes --missing only                        # list only files without frontmatter
```

Files with no frontmatter appear with `(no frontmatter)` in plain output (or `null` in JSON). Parse errors for individual files are reported to stderr and the run continues.

## Library

The `MarkdownKit` library can be used independently in other Swift packages:

```swift
.package(url: "https://github.com/adamwulf/md", branch: "main")
```

Then depend on `MarkdownKit`:

```swift
.target(name: "YourTarget", dependencies: [
    .product(name: "MarkdownKit", package: "md")
])
```
