import AppKit
import UniformTypeIdentifiers

@MainActor
enum ExportDialog {
    /// Presents the period picker, then a save panel, then runs the export.
    /// Returns silently if the user cancels at any step.
    static func present() {
        let entries = Storage.shared.entries
        let options = ExportPeriod.availableOptions(for: entries)
        guard let chosen = pickPeriod(options: options) else { return }
        guard let url = pickSaveURL(default: chosen.defaultFilename) else { return }
        runExport(period: chosen, entries: entries, to: url)
    }

    private static func pickPeriod(options: [ExportPeriod]) -> ExportPeriod? {
        let alert = NSAlert()
        alert.messageText = "Export to Excel"
        alert.informativeText = "Choose what to include in the export."
        alert.addButton(withTitle: "Choose location…")
        alert.addButton(withTitle: "Cancel")

        let popup = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 280, height: 26), pullsDown: false)
        for option in options {
            popup.addItem(withTitle: option.displayName)
        }
        popup.selectItem(at: 0)
        alert.accessoryView = popup

        NSApp.activate(ignoringOtherApps: true)
        let response = alert.runModal()
        guard response == .alertFirstButtonReturn else { return nil }

        let index = popup.indexOfSelectedItem
        guard options.indices.contains(index) else { return nil }
        return options[index]
    }

    private static func pickSaveURL(default name: String) -> URL? {
        let panel = NSSavePanel()
        if let xlsx = UTType(filenameExtension: "xlsx") {
            panel.allowedContentTypes = [xlsx]
        }
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = name
        panel.title = "Save Excel Export"

        NSApp.activate(ignoringOtherApps: true)
        let response = panel.runModal()
        guard response == .OK else { return nil }
        return panel.url
    }

    private static func runExport(period: ExportPeriod, entries: [Entry], to url: URL) {
        do {
            try ExcelExporter.export(entries: entries, period: period, to: url)
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } catch {
            let alert = NSAlert(error: error)
            alert.messageText = "Export failed"
            alert.runModal()
        }
    }
}
