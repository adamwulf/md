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

### Format/normalize a markdown file

```bash
md format README.md
```

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
