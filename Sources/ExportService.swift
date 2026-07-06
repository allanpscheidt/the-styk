import AppKit

enum ExportService {
    /// Exporta SEMPRE texto Unicode puro (UTF-8, sem atributos) via NSSharingServicePicker.
    static func share(note: Note, relativeTo view: NSView?) {
        purgeOldExports()
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("TheStyk-" + UUID().uuidString, isDirectory: true)
        let fileURL = dir.appendingPathComponent(fileName(for: note), isDirectory: false)
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try Data(note.text.utf8).write(to: fileURL, options: .atomic)
        } catch {
            NSLog("The Styk: falha ao gravar arquivo de exportação: %@", error.localizedDescription)
            return
        }

        let picker = NSSharingServicePicker(items: [fileURL])

        if let view = view, view.window != nil {
            let session = ExportPickerSession(picker: picker, anchorWindow: nil, tempDir: dir)
            ExportPickerSession.active = session
            picker.delegate = session
            picker.show(relativeTo: view.bounds, of: view, preferredEdge: .minY)
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

            let session = ExportPickerSession(picker: picker, anchorWindow: window, tempDir: dir)
            ExportPickerSession.active = session
            picker.delegate = session
            guard let anchorView = window.contentView else { return }
            picker.show(relativeTo: anchorView.bounds, of: anchorView, preferredEdge: .minY)
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

    /// Remove exports temporários antigos — cópias em texto das notas não acumulam em $TMPDIR.
    /// Chamado a cada export e no launch do app (promessa da política de privacidade).
    static func purgeOldExports() {
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
        let cutoff = Date(timeIntervalSinceNow: -86_400)
        let items = (try? FileManager.default.contentsOfDirectory(
            at: tmp, includingPropertiesForKeys: [.contentModificationDateKey],
            options: .skipsSubdirectoryDescendants)) ?? []
        for item in items where item.lastPathComponent.hasPrefix("TheStyk-") {
            let date = (try? item.resourceValues(forKeys: [.contentModificationDateKey])
                .contentModificationDate) ?? .distantPast
            if date < cutoff { try? FileManager.default.removeItem(at: item) }
        }
    }
}

/// Retém picker + janela-âncora enquanto o painel de share está aberto;
/// solta quando o usuário escolhe um serviço ou fecha o painel.
private final class ExportPickerSession: NSObject, NSSharingServicePickerDelegate {
    static var active: ExportPickerSession?

    private let picker: NSSharingServicePicker   // referência forte proposital
    private let anchorWindow: NSWindow?
    private let tempDir: URL?

    init(picker: NSSharingServicePicker, anchorWindow: NSWindow?, tempDir: URL?) {
        self.picker = picker
        self.anchorWindow = anchorWindow
        self.tempDir = tempDir
    }

    func sharingServicePicker(_ sharingServicePicker: NSSharingServicePicker,
                              didChoose service: NSSharingService?) {
        // A cópia temporária some sozinha: 15 min dá folga para o AirDrop/Mail
        // terminar de ler o arquivo (promessa da política de privacidade).
        if let dir = tempDir {
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 900) {
                try? FileManager.default.removeItem(at: dir)
            }
        }
        // Solta no próximo ciclo: o serviço escolhido já retém o que precisa.
        DispatchQueue.main.async { [self] in
            anchorWindow?.orderOut(nil)
            if ExportPickerSession.active === self {
                ExportPickerSession.active = nil
            }
        }
    }
}
