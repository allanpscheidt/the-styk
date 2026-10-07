import AppKit

enum ExportService {
    /// Exporta SEMPRE texto Unicode puro (UTF-8, sem atributos) via NSSharingServicePicker.
    static func share(note: Note, relativeTo view: NSView?,
                      authorization: PasswordService.Authorization? = nil) {
        guard PasswordService.consumeAuthorization(authorization, for: .export) else { return }
        let fileURL: URL
        do {
            fileURL = try TemporaryExports.create(text: note.text, fileName: fileName(for: note))
        } catch {
            NSLog("The Styk: falha ao gravar arquivo de exportação: %@", error.localizedDescription)
            return
        }
        let dir = fileURL.deletingLastPathComponent()

        if let view = view, view.window != nil {
            let session = ExportPickerSession(fileURL: fileURL, anchorWindow: nil, tempDir: dir)
            session.retainUntilFinished()
            session.show(relativeTo: view)
        } else {
            // Sem view (menu de status): mini janela-âncora transparente no mouse.
            NSApp.activate(ignoringOtherApps: true)
            let mouse = NSEvent.mouseLocation
            let window = NSWindow(contentRect: NSRect(x: mouse.x - 4, y: mouse.y - 4,
                                                      width: 8, height: 8),
                                  styleMask: .borderless, backing: .buffered, defer: false)
            window.backgroundColor = .clear
            window.isOpaque = false
            window.hasShadow = false
            window.level = .popUpMenu
            window.isReleasedWhenClosed = false
            window.orderFrontRegardless()

            let session = ExportPickerSession(fileURL: fileURL, anchorWindow: window, tempDir: dir)
            session.retainUntilFinished()
            guard let anchorView = window.contentView else { session.finish(); return }
            session.show(relativeTo: anchorView)
        }
    }

    /// "The Styk – <snippet>.txt" sanitizado: sem `/`, `:`, `\0` e chars de controle;
    /// nome com máx 50 chars; fallback "The Styk – Nota.txt".
    private static func fileName(for note: Note) -> String {
        let firstLine = note.text
            .split(whereSeparator: { $0.isNewline })
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first(where: { !$0.isEmpty }) ?? ""

        var cleaned = ""
        for scalar in firstLine.unicodeScalars {
            if scalar == "/" || scalar == ":" || scalar.value == 0 { continue }
            // Cc (controle) e Cf (formato: RLO/isolates bidi, ZWJ…) — anti-spoofing do nome.
            let cat = scalar.properties.generalCategory
            if cat == .control || cat == .format { continue }
            cleaned.unicodeScalars.append(scalar)
        }
        cleaned = cleaned.trimmingCharacters(in: .whitespaces)
        guard !cleaned.isEmpty else { return "The Styk – Nota.txt" }

        var base = String(("The Styk – " + cleaned).prefix(39))   // 39 + ".txt" = 43 (garante ficar abaixo de 50)
        while base.utf8.count > 200 { base.removeLast() }         // NAME_MAX conta bytes, não graphemes
        return base + ".txt"
    }

    /// Chamado somente no launch: remove todas as sobras próprias, de qualquer idade.
    static func purgeOldExports() {
        TemporaryExports.purgeLeftovers()
    }
}

/// Retém picker + janela-âncora enquanto o painel de share está aberto;
/// solta quando o usuário escolhe um serviço ou fecha o painel.
final class ExportPickerSession: NSObject, NSSharingServicePickerDelegate, NSSharingServiceDelegate, NSMenuDelegate {
    private static var active: [UUID: ExportPickerSession] = [:]
    private let id = UUID()
    private var timeout: DispatchWorkItem?
    private var service: NSSharingService?
    private var lockObserver: NSObjectProtocol?
    private var finished = false

    private let picker: NSSharingServicePicker?
    private let legacyMenu: NSMenu?
    private let fileURL: URL
    private let anchorWindow: NSWindow?
    private let tempDir: URL?

    init(fileURL: URL, anchorWindow: NSWindow?, tempDir: URL?) {
        self.fileURL = fileURL
        if #available(macOS 13.0, *) {
            picker = NSSharingServicePicker(items: [fileURL])
            legacyMenu = nil
        } else {
            // Versões antigas não oferecem close() no picker. Um menu próprio
            // permite cancelar e verificar a sessão antes de executar o serviço.
            picker = nil
            legacyMenu = NSMenu()
        }
        self.anchorWindow = anchorWindow
        self.tempDir = tempDir
        super.init()
    }

    func show(relativeTo view: NSView) {
        guard !finished, PasswordService.canAccessNotes else { finish(); return }
        if let picker = picker {
            picker.delegate = self
            picker.show(relativeTo: view.bounds, of: view, preferredEdge: .minY)
        } else if let menu = legacyMenu {
            menu.delegate = self
            for service in NSSharingService.sharingServices(forItems: [fileURL]) {
                let item = NSMenuItem(title: service.title, action: #selector(chooseLegacyService(_:)), keyEquivalent: "")
                item.image = service.image
                item.target = self
                item.representedObject = service
                menu.addItem(item)
            }
            guard !menu.items.isEmpty else { finish(); return }
            menu.popUp(positioning: nil, at: NSPoint(x: view.bounds.minX, y: view.bounds.maxY), in: view)
        }
    }

    @objc private func chooseLegacyService(_ item: NSMenuItem) {
        guard !finished, PasswordService.canAccessNotes,
              let selected = item.representedObject as? NSSharingService else { finish(); return }
        service = selected
        selected.delegate = self
        selected.perform(withItems: [fileURL])
    }

    func menuDidClose(_ menu: NSMenu) {
        // O target do item é executado após o menu fechar.
        DispatchQueue.main.async { [self] in
            if service == nil { finish() }
        }
    }

    func retainUntilFinished() {
        Self.active[id] = self
        lockObserver = NotificationCenter.default.addObserver(
            forName: PasswordService.lockStateDidChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            if !PasswordService.canAccessNotes { self?.finish() }
        }
        let work = DispatchWorkItem { [weak self] in self?.finish() }
        timeout = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 900, execute: work)
    }

    func finish() {
        guard !finished else { return }
        finished = true
        if let observer = lockObserver { NotificationCenter.default.removeObserver(observer) }
        lockObserver = nil
        timeout?.cancel()
        timeout = nil
        legacyMenu?.cancelTracking()
        picker?.delegate = nil
        if #available(macOS 13.0, *) { picker?.close() }
        anchorWindow?.close()
        service?.delegate = nil
        service = nil
        if let dir = tempDir { TemporaryExports.remove(dir) }
        Self.active.removeValue(forKey: id)
    }

    func sharingServicePicker(_ sharingServicePicker: NSSharingServicePicker,
                              delegateFor sharingService: NSSharingService) -> NSSharingServiceDelegate? {
        guard !finished, PasswordService.canAccessNotes else { finish(); return nil }
        service = sharingService
        return self
    }

    func sharingServicePicker(_ sharingServicePicker: NSSharingServicePicker,
                              didChoose service: NSSharingService?) {
        guard !finished, PasswordService.canAccessNotes else { finish(); return }
        self.service = service
        service?.delegate = self
        // Serviço escolhido pode ler o arquivo assincronamente. Aguarda callback
        // de sucesso/falha; cancelar o picker apaga a cópia imediatamente.
        DispatchQueue.main.async { [self] in
            anchorWindow?.orderOut(nil)
            if service == nil { finish() }
        }
    }

    func sharingService(_ sharingService: NSSharingService, didShareItems items: [Any]) {
        finish()
    }

    func sharingService(_ sharingService: NSSharingService, didFailToShareItems items: [Any], error: Error) {
        finish()
    }
}
