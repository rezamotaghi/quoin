import AppKit

/// Thin NSDocumentController subclass. The bundle's Info.plist declares the
/// document types; these overrides make the same answers available even when
/// the binary runs outside the bundle (swift run), and route every file,
/// whatever its extension, to TextDocument: a text editor opens anything.
@MainActor
final class DocumentController: NSDocumentController {

    static let textDocumentType = "Text Document"

    override var defaultType: String? { Self.textDocumentType }

    override func documentClass(forType typeName: String) -> AnyClass? {
        TextDocument.self
    }

    override func typeForContents(of url: URL) throws -> String {
        Self.textDocumentType
    }
}
