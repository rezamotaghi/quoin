Vendored copy of tree-sitter-python's external scanner (src/scanner.c and its
tree_sitter/ headers), byte-for-byte from the v0.25.0 tag.

Why: the upstream Package.swift decides whether to compile scanner.c with
`FileManager.default.fileExists(atPath: "src/scanner.c")` -- a RELATIVE path.
SwiftPM evaluates manifests from a temporary directory, so the check fails,
scanner.c is silently dropped, and the app fails to link with undefined
_tree_sitter_python_external_scanner_* symbols. This target supplies them.

If the tree-sitter-python pin in Package.swift ever moves off v0.25.0, re-copy
these files from the new checkout (or delete this target if upstream fixes
the manifest).
