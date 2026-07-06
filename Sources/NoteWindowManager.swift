import AppKit

/// Reconcilia painéis de nota abertos com a pasta visível no Finder.
/// Painéis são destruídos ao sair da pasta (não escondidos) — leveza.
final class NoteWindowManager {

    static let shared = NoteWindowManager()

    private var controllers: [UUID: NoteWindowController] = [:]
    private var visibleFolder: String?

    private init() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(indexDidChange),
            name: NoteStore.indexDidChange,
            object: nil
        )
    }

    private var windowBounds: NSRect?

    func setVisibleFolder(_ folder: String?, windowBounds bounds: NSRect? = nil) {
        let folderChanged = folder != visibleFolder
        visibleFolder = folder
        windowBounds = bounds
        if folderChanged { reconcile() }
        applyAnchors()
    }

    /// Cola as notas abertas na janela do Finder (segue mover/redimensionar/trocar de monitor).
    private func applyAnchors() {
        guard let bounds = windowBounds else { return }
        let topLeft = NSPoint(x: bounds.minX, y: bounds.maxY)
        for controller in controllers.values {
            controller.updateAnchoredPosition(windowTopLeft: topLeft)
        }
    }

    func suggestedFrame() -> NoteFrame {
        let w = 260.0
        let h = 240.0
        // Nota nova nasce sobre a janela do Finder; sem janela conhecida, centro da tela.
        let screen = windowBounds
            ?? NSScreen.main?.visibleFrame
            ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let offset = CGFloat(controllers.count % 12) * 24  // wrap: cascata nunca sai da tela
        return NoteFrame(
            x: Double(screen.midX - CGFloat(w) / 2 + offset),
            y: Double(screen.midY - CGFloat(h) / 2 - offset),
            w: w,
            h: h
        )
    }

    func flushAll() {
        for controller in controllers.values {
            controller.flushPendingSave()
        }
    }

    /// Fecha todos os painéis (close() já faz flush) ANTES de uma restauração
    /// substituir os dados — um flush tardio corromperia o backup restaurado.
    /// A restauração posta indexDidChange, e o reconcile reabre com o conteúdo novo.
    func prepareForRestore() {
        for (id, controller) in controllers {
            controller.close()
            controllers[id] = nil
        }
    }

    // MARK: - Reconcile

    @objc private func indexDidChange() {
        reconcile()
    }

    private func reconcile() {
        let entries = visibleFolder.map { NoteStore.shared.entries(inFolder: $0) } ?? []
        let wanted = Set(entries.map { $0.id })

        // Fecha os que sobram (close() já dá flush, por contrato).
        for (id, controller) in controllers where !wanted.contains(id) {
            controller.close()
            controllers[id] = nil
        }

        // Abre os que faltam (leitura lazy da nota completa).
        var opened = false
        for id in wanted where controllers[id] == nil {
            guard let note = NoteStore.shared.loadNote(id: id) else { continue }
            let controller = NoteWindowController(note: note)
            controllers[id] = controller
            controller.showWindow(nil)
            opened = true
        }
        if opened { applyAnchors() }
    }

    func showNoteForEditing(id: UUID) {
        guard let note = NoteStore.shared.loadNote(id: id) else { return }
        if controllers[id] == nil {
            let controller = NoteWindowController(note: note)
            controllers[id] = controller
        }
        controllers[id]?.showWindow(nil)
        controllers[id]?.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
