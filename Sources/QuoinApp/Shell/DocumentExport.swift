import AppKit
import UniformTypeIdentifiers

/// File > Export formats. The menu items carry these raw values as their
/// tag, and one selector dispatches on it (the same tag pattern as the find
/// bar items in MainMenu).
enum ExportFormat: Int {
    case markdown = 1
    case plainText = 2
    case pdf = 3

    var fileExtension: String {
        switch self {
        case .markdown: "md"
        case .plainText: "txt"
        case .pdf: "pdf"
        }
    }

    var contentType: UTType {
        switch self {
        case .markdown: UTType(filenameExtension: "md") ?? .plainText
        case .plainText: .plainText
        case .pdf: .pdf
        }
    }
}

/// Export and Reveal in Finder. Both live on the document so the responder
/// chain enables the menu items only while a document window is frontmost.
extension TextDocument {

    /// File > Export > Markdown / Plain Text / PDF. Every format runs
    /// through a save panel, so the destination is always explicit.
    @objc func exportDocument(_ sender: Any?) {
        guard let format = ExportFormat(rawValue: (sender as? NSMenuItem)?.tag ?? 0),
              let window = windowControllers.first?.window else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [format.contentType]
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        panel.nameFieldStringValue = exportBaseName + "." + format.fileExtension
        panel.beginSheetModal(for: window) { [weak self] response in
            guard let self, response == .OK, let url = panel.url else { return }
            do {
                try self.export(to: url, format: format)
            } catch {
                self.presentError(error)
            }
        }
    }

    /// Always-visible Save As. The custom selector name keeps AppKit's
    /// autosave menu rewriting away from the item (see MainMenu); the body
    /// is just the standard NSDocument Save As flow.
    @objc func saveDocumentAsExplicit(_ sender: Any?) {
        saveAs(sender)   // NSDocument's standard Save As flow (Swift name)
    }

    /// File > Reveal in Finder: answers "where is this file actually saved".
    @objc func revealInFinder(_ sender: Any?) {
        guard let fileURL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([fileURL])
    }

    override func validateUserInterfaceItem(_ item: any NSValidatedUserInterfaceItem) -> Bool {
        if item.action == #selector(revealInFinder(_:)) {
            return fileURL != nil   // dimmed until the document exists on disk
        }
        return super.validateUserInterfaceItem(item)
    }

    // MARK: - Writing

    private var exportBaseName: String {
        fileURL?.deletingPathExtension().lastPathComponent ?? displayName ?? "Untitled"
    }

    /// Exports always take the LIVE buffer (including unsaved edits), same
    /// snapshot rule as save's data(ofType:).
    private var liveText: String {
        (windowControllers.first as? DocumentWindowController)?.currentText ?? text
    }

    private func export(to url: URL, format: ExportFormat) throws {
        switch format {
        case .markdown, .plainText:
            // The buffer already is markdown/plain text; export = write the
            // bytes under the chosen extension.
            try Data(liveText.utf8).write(to: url, options: .atomic)
        case .pdf:
            try exportPDF(to: url)
        }
    }

    /// Classic Cocoa print-to-PDF: lay the text out in an offscreen
    /// NSTextView and run a panel-less NSPrintOperation whose job
    /// disposition is "save to URL". NSPrintOperation paginates for us.
    /// Paper idiom, not editor idiom: black text on white, regardless of the
    /// app theme.
    private func exportPDF(to url: URL) throws {
        let printInfo = NSPrintInfo()
        printInfo.horizontalPagination = .fit
        printInfo.verticalPagination = .automatic
        printInfo.topMargin = 36
        printInfo.bottomMargin = 36
        printInfo.leftMargin = 36
        printInfo.rightMargin = 36
        printInfo.jobDisposition = .save
        printInfo.dictionary()[NSPrintInfo.AttributeKey.jobSavingURL] = url

        let settings = SettingsStore.shared.settings
        let font = settings.fontFace.isEmpty
            ? NSFont.monospacedSystemFont(ofSize: settings.fontSize, weight: .regular)
            : NSFont(name: settings.fontFace, size: settings.fontSize)
                ?? NSFont.monospacedSystemFont(ofSize: settings.fontSize, weight: .regular)

        let contentWidth = printInfo.paperSize.width - printInfo.leftMargin - printInfo.rightMargin
        let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: contentWidth, height: 1))
        textView.string = liveText
        textView.font = font
        textView.textColor = .black
        textView.drawsBackground = false

        let operation = NSPrintOperation(view: textView, printInfo: printInfo)
        operation.showsPrintPanel = false
        operation.showsProgressPanel = false
        guard operation.run() else {
            throw NSError(domain: NSCocoaErrorDomain, code: NSFileWriteUnknownError, userInfo: [
                NSLocalizedDescriptionKey: "The PDF could not be written to \(url.path).",
            ])
        }
    }
}
