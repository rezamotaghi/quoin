// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "Quoin",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "EditorCore", targets: ["EditorCore"]),
        .library(name: "SyntaxKit", targets: ["SyntaxKit"]),
        .library(name: "CommandKit", targets: ["CommandKit"]),
        .library(name: "FuzzyKit", targets: ["FuzzyKit"]),
        .executable(name: "QuoinApp", targets: ["QuoinApp"]),
    ],
    dependencies: [
        // The rented text view (see ARCHITECTURE.md "rental"). Chosen at
        // Phase 1 after verifying candidates; reasoning recorded in AGENTS.md.
        .package(url: "https://github.com/krzyzanowskim/STTextView", from: "2.3.10"),
        // CommonMark+GFM parser (Apple) for the Markdown preview. Branch pin:
        // its 0.x tags make SPM's upToNextMajor too narrow; Package.resolved
        // still locks the exact commit.
        .package(url: "https://github.com/swiftlang/swift-markdown.git", branch: "main"),
        // Phase 3: tree-sitter (incremental parsing) + per-language grammars.
        // Versions verified against live tags 2026-07-12.
        .package(url: "https://github.com/ChimeHQ/SwiftTreeSitter", from: "0.25.0"),
        // exact: the vendored TreeSitterPythonScanner target must match this
        // tag byte-for-byte (see its README for why it exists at all).
        .package(url: "https://github.com/tree-sitter/tree-sitter-python", exact: "0.25.0"),
        .package(url: "https://github.com/tree-sitter/tree-sitter-json", from: "0.24.8"),
        .package(url: "https://github.com/tree-sitter-grammars/tree-sitter-markdown", from: "0.5.3"),
        // The plain tags of this grammar don't include the generated parser.c;
        // only the "-with-generated-files" tags are SwiftPM-consumable.
        .package(url: "https://github.com/alex-pinkus/tree-sitter-swift", exact: "0.7.3-with-generated-files"),
        // Amendment 1 (agent surface): official MCP SDK, used ONLY by the
        // QuoinMCP stdio shim, never linked into the app itself.
        .package(url: "https://github.com/modelcontextprotocol/swift-sdk", from: "0.12.1"),
    ],
    targets: [
        // Pure data: the document model. Must never import AppKit or SwiftUI.
        .target(name: "EditorCore"),
        // Highlighting boundary: owns tree-sitter and every grammar. Emits
        // semantic style names only (invariant 5); never imports AppKit.
        .target(name: "SyntaxKit", dependencies: [
            "EditorCore",
            .product(name: "SwiftTreeSitter", package: "SwiftTreeSitter"),
            .product(name: "TreeSitterPython", package: "tree-sitter-python"),
            .product(name: "TreeSitterJSON", package: "tree-sitter-json"),
            .product(name: "TreeSitterMarkdown", package: "tree-sitter-markdown"),
            .product(name: "TreeSitterSwift", package: "tree-sitter-swift"),
            "TreeSitterPythonScanner",
        ]),
        // Upstream tree-sitter-python's manifest drops its external scanner
        // (relative-path bug); this vendored C target supplies the missing
        // symbols. See Sources/TreeSitterPythonScanner/README.md.
        .target(name: "TreeSitterPythonScanner", cSettings: [.headerSearchPath("src")]),
        // Command registry: every user-facing action is a Command.
        .target(name: "CommandKit"),
        // Fuzzy matching for Cmd+P and the command palette. Pure functions.
        .target(name: "FuzzyKit"),
        // The AppKit shell. The ONLY target that may name the rented text view.
        .executableTarget(
            name: "QuoinApp",
            dependencies: [
                "EditorCore", "SyntaxKit", "CommandKit", "FuzzyKit",
                .product(name: "STTextView", package: "STTextView"),
                .product(name: "Markdown", package: "swift-markdown"),
            ]
        ),
        // Amendment 1: stdio<->unix-socket shim so MCP clients (Claude Code
        // etc.) can talk to the running app's agent endpoint.
        .executableTarget(
            name: "QuoinMCP",
            dependencies: [
                "EditorCore",
                .product(name: "MCP", package: "swift-sdk"),
            ]
        ),
        .testTarget(name: "EditorCoreTests", dependencies: ["EditorCore"]),
        .testTarget(name: "FuzzyKitTests", dependencies: ["FuzzyKit"]),
        .testTarget(name: "SyntaxKitTests", dependencies: ["SyntaxKit"]),
    ]
)
