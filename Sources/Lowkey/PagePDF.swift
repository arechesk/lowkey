import AppKit
import UniformTypeIdentifiers
import WebKit

/// Use WebKit's print layout, including print CSS and every printed page, not a viewport snapshot.
@MainActor enum PagePDF {
    private static var isPrinting = false

    enum Failure: LocalizedError {
        case printing
        var errorDescription: String? { "Could not save the page as PDF." }
    }

    @MainActor private final class PrintJob: NSObject {
        var completion: CheckedContinuation<Bool, Never>?

        func run(_ operation: NSPrintOperation, in window: NSWindow) async -> Bool {
            await withCheckedContinuation { completion in
                self.completion = completion
                operation.runModal(for: window, delegate: self,
                    didRun: #selector(finished(_:success:context:)), contextInfo: nil)
            }
        }

        @objc private func finished(_ operation: NSPrintOperation, success: Bool, context: UnsafeMutableRawPointer?) {
            completion?.resume(returning: success)
            completion = nil
        }
    }

    static func save(_ view: WKWebView, to destination: URL, overwrite: Bool = false) async throws {
        guard !isPrinting else { throw Failure.printing }
        isPrinting = true
        defer { isPrinting = false }
        if !overwrite, FileManager.default.fileExists(atPath: destination.path) {
            throw CocoaError(.fileWriteFileExists)
        }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: directory) }
        let temporary = directory.appendingPathComponent("page.pdf")
        let info = NSPrintInfo.shared.copy() as! NSPrintInfo
        info.paperSize = NSSize(width: 595.28, height: 841.89) // A4 in points; no printer required.
        info.topMargin = 36
        info.bottomMargin = 36
        info.leftMargin = 36
        info.rightMargin = 36
        info.jobDisposition = .save
        info.dictionary()[NSPrintInfo.AttributeKey.jobSavingURL] = temporary
        info.horizontalPagination = .fit
        info.verticalPagination = .automatic
        let operation = view.printOperation(with: info)
        operation.showsPrintPanel = false
        operation.showsProgressPanel = false
        // WebKit prepares pagination asynchronously. Synchronous run() can print endlessly.
        let job = PrintJob()
        let window = view.window ?? NSWindow(contentRect: view.bounds, styleMask: [], backing: .buffered, defer: false)
        let succeeded = await job.run(operation, in: window)
        guard succeeded, FileManager.default.fileExists(atPath: temporary.path) else { throw Failure.printing }
        let data = try Data(contentsOf: temporary)
        try data.write(to: destination, options: overwrite ? .atomic : .withoutOverwriting)
    }

    static func chooseDestination(for view: WKWebView, in window: NSWindow) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        panel.nameFieldStringValue = (view.title?.isEmpty == false ? view.title! : "Page")
            .replacingOccurrences(of: "/", with: "-") + ".pdf"
        panel.beginSheetModal(for: window) { response in
            guard response == .OK, let url = panel.url else { return }
            Task { @MainActor in
                do { try await save(view, to: url, overwrite: true) }
                catch { _ = await NSAlert(error: error).beginSheetModal(for: window) }
            }
        }
    }
}
