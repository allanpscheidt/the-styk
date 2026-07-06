import AppKit

final class StatusMenuController: NSObject, NSMenuDelegate {
    private let statusItem: NSStatusItem
    private let finder: FinderObserver
    private let menu: NSMenu

    init(statusItem: NSStatusItem, finder: FinderObserver) {
        self.statusItem = statusItem
        self.finder = finder
        self.menu = NSMenu()
        super.init()
        menu.delegate = self
        menu.autoenablesItems = false
        
        if let button = statusItem.button {
            button.target = self
            button.action = #selector(statusItemClicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }

        // Aumentar contraste pode mudar ao vivo — as bolinhas de cor são redesenhadas.
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(accessibilityDisplayChanged),
            name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
            object: nil
        )
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(lockStateChanged),
            name: PasswordService.lockStateDidChangeNotification,
            object: nil
        )
    }

    @objc private func lockStateChanged() {
        // Recria os itens na próxima abertura
    }

    // MARK: - NSMenuDelegate

    // Reconstrói o menu a cada abertura, sempre a partir do índice (leve).
    // Notas completas só são carregadas no clique, via representedObject.
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        // 1. Nova nota
        if let folder = finder.currentFolder {
            let item = NSMenuItem(title: L("Nova nota nesta pasta"),
                                  action: #selector(newNote(_:)), keyEquivalent: "n")
            item.keyEquivalentModifierMask = [.command, .option]
            item.target = self
            item.representedObject = folder
            item.image = Self.symbol("plus.square.on.square")
            menu.addItem(item)
        } else {
            let item = NSMenuItem(title: L("Abra uma pasta no Finder para criar uma nota"),
                                  action: nil, keyEquivalent: "")
            item.isEnabled = false
            menu.addItem(item)
        }

        menu.addItem(.separator())

        // 3. Ver Todas as Notas (abre a galeria)
        let galleryItem = NSMenuItem(title: L("Ver Todas as Notas..."),
                                     action: #selector(openGallery), keyEquivalent: "g")
        galleryItem.target = self
        galleryItem.image = Self.symbol("square.grid.2x2")
        menu.addItem(galleryItem)

        // 4. Notas órfãs (pasta original apagada)
        let orphanEntries = NoteStore.shared.orphans()
        if !orphanEntries.isEmpty {
            menu.addItem(.separator())
            let orphansItem = NSMenuItem(title: String(format: L("Notas órfãs (%d)"), orphanEntries.count),
                                         action: nil, keyEquivalent: "")
            orphansItem.image = Self.symbol("folder.badge.questionmark")
            let orphansMenu = NSMenu()
            orphansMenu.autoenablesItems = false
            let caption = NSMenuItem(title: L("A pasta original foi apagada"),
                                     action: nil, keyEquivalent: "")
            caption.isEnabled = false
            orphansMenu.addItem(caption)
            orphansMenu.addItem(.separator())
            for entry in orphanEntries {
                let item = NSMenuItem(title: entry.snippet, action: nil, keyEquivalent: "")
                item.image = Self.dot(for: entry.color)
                item.toolTip = String(format: L("Era em: %@"), (entry.folder as NSString).abbreviatingWithTildeInPath)
                let sub = NSMenu()
                sub.autoenablesItems = false
                let reattach = NSMenuItem(title: L("Levar para uma pasta…"),
                                          action: #selector(reattachOrphan(_:)), keyEquivalent: "")
                reattach.target = self
                reattach.representedObject = entry.id
                reattach.image = Self.symbol("folder.badge.plus")
                sub.addItem(reattach)
                let export = NSMenuItem(title: L("Exportar…"),
                                        action: #selector(exportNote(_:)), keyEquivalent: "")
                export.target = self
                export.representedObject = entry.id
                export.image = Self.symbol("square.and.arrow.up")
                sub.addItem(export)
                let del = NSMenuItem(title: L("Mover para a Lixeira"),
                                     action: #selector(deleteNote(_:)), keyEquivalent: "")
                del.target = self
                del.representedObject = entry.id
                del.image = Self.symbol("trash")
                sub.addItem(del)
                item.submenu = sub
                orphansMenu.addItem(item)
            }
            orphansItem.submenu = orphansMenu
            menu.addItem(orphansItem)
        }

        // 5. Lixeira (recuperável por 5 dias)
        let trashed = NoteStore.shared.trash
        if !trashed.isEmpty {
            menu.addItem(.separator())
            let trashItem = NSMenuItem(title: String(format: L("Lixeira (%d)"), trashed.count),
                                       action: nil, keyEquivalent: "")
            trashItem.image = Self.symbol("trash")
            let trashMenu = NSMenu()
            trashMenu.autoenablesItems = false
            let caption = NSMenuItem(title: L("Notas somem daqui após 5 dias"),
                                     action: nil, keyEquivalent: "")
            caption.isEnabled = false
            trashMenu.addItem(caption)
            trashMenu.addItem(.separator())
            let df = DateFormatter()
            df.dateStyle = .short
            df.timeStyle = .none
            for t in trashed.sorted(by: { $0.deletedAt > $1.deletedAt }) {
                let item = NSMenuItem(title: t.snippet, action: nil, keyEquivalent: "")
                item.image = Self.dot(for: t.color)
                item.toolTip = String(format: L("Apagada em %@ · era em %@"),
                                      df.string(from: t.deletedAt),
                                      (t.folder as NSString).abbreviatingWithTildeInPath)
                let sub = NSMenu()
                sub.autoenablesItems = false
                let restore = NSMenuItem(title: L("Restaurar"),
                                         action: #selector(restoreNote(_:)), keyEquivalent: "")
                restore.target = self
                restore.representedObject = t.id
                restore.image = Self.symbol("arrow.uturn.backward")
                sub.addItem(restore)
                let del = NSMenuItem(title: L("Apagar definitivamente…"),
                                     action: #selector(deleteForever(_:)), keyEquivalent: "")
                del.target = self
                del.representedObject = t.id
                del.image = Self.symbol("xmark.bin")
                sub.addItem(del)
                item.submenu = sub
                trashMenu.addItem(item)
            }
            trashMenu.addItem(.separator())
            let empty = NSMenuItem(title: L("Esvaziar Lixeira…"),
                                   action: #selector(emptyTrashAction), keyEquivalent: "")
            empty.target = self
            trashMenu.addItem(empty)
            trashItem.submenu = trashMenu
            menu.addItem(trashItem)
        }

        // 6. Bloqueio / Preferências
        menu.addItem(.separator())
        if PasswordService.hasPassword {
            if PasswordService.isLocked {
                let unlockItem = NSMenuItem(title: L("Desbloquear Notas..."),
                                            action: #selector(unlockNotes), keyEquivalent: "")
                unlockItem.target = self
                unlockItem.image = Self.symbol("lock.open")
                menu.addItem(unlockItem)
            } else {
                let lockItem = NSMenuItem(title: L("Bloquear Notas"),
                                          action: #selector(lockNotes), keyEquivalent: "")
                lockItem.target = self
                lockItem.image = Self.symbol("lock")
                menu.addItem(lockItem)
            }
        }

        let settingsItem = NSMenuItem(title: L("Preferências…"),
                                      action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        settingsItem.image = Self.symbol("gearshape")
        menu.addItem(settingsItem)

        // 7. Sobre / Sair
        menu.addItem(.separator())
        let about = NSMenuItem(title: L("Sobre o The Styk"),
                               action: #selector(showAbout), keyEquivalent: "")
        about.target = self
        about.image = Self.symbol("info.circle")
        menu.addItem(about)
        let quit = NSMenuItem(title: L("Sair do The Styk"),
                              action: #selector(quitApp), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
    }

    // MARK: - Itens

    private func openFolderItem(_ folder: String, valid: Bool) -> NSMenuItem {
        guard valid else {
            let item = NSMenuItem(title: L("Pasta não encontrada"), action: nil, keyEquivalent: "")
            item.isEnabled = false
            item.image = Self.symbol("folder.badge.questionmark")
            return item
        }
        let item = NSMenuItem(title: L("Abrir pasta no Finder"),
                              action: #selector(openFolder(_:)), keyEquivalent: "")
        item.target = self
        item.representedObject = folder
        item.image = Self.symbol("folder")
        return item
    }

    /// Guardrail: só abre se existe, é diretório e NÃO é pacote (índice adulterado não lança .app).
    /// Symlinks são resolvidos ANTES da validação — o alvo real é o que conta.
    private static func isValidFolder(_ path: String) -> Bool {
        let url = URL(fileURLWithPath: path).resolvingSymlinksInPath()
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir),
              isDir.boolValue else { return false }
        let isPackage = (try? url.resourceValues(forKeys: [.isPackageKey]).isPackage) ?? false
        return !isPackage
    }

    /// Símbolo SF em tamanho de menu (~16 pt), template. Nil em macOS < 11: item fica só com texto.
    private static func symbol(_ name: String) -> NSImage? {
        guard #available(macOS 11.0, *) else { return nil }
        guard let base = NSImage(systemSymbolName: name, accessibilityDescription: nil) else { return nil }
        let image = base.withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 16, weight: .regular)) ?? base
        image.isTemplate = true
        return image
    }

    private static var dotCache: [NoteColor: NSImage] = [:]

    /// "Aumentar contraste" mudou: joga fora o cache — o menu é remontado a cada abertura.
    @objc private func accessibilityDisplayChanged() {
        Self.dotCache.removeAll()
    }

    private static func dot(for color: NoteColor) -> NSImage {
        if let cached = dotCache[color] { return cached }
        let highContrast = NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
        let image = NSImage(size: NSSize(width: 10, height: 10), flipped: false) { rect in
            let oval = NSBezierPath(ovalIn: rect.insetBy(dx: 0.5, dy: 0.5))
            Theme.nsColor(color).setFill()
            oval.fill()
            // Borda: pastel puro some sobre menu claro; bem mais escura com "Aumentar contraste".
            NSColor.black.withAlphaComponent(highContrast ? 0.8 : 0.25).setStroke()
            oval.lineWidth = 1
            oval.stroke()
            return true
        }
        image.accessibilityDescription = colorLabel(color)   // VoiceOver: "Cor amarela" etc.
        dotCache[color] = image
        return image
    }

    private static func colorLabel(_ c: NoteColor) -> String {
        switch c {
        case .yellow: return L("Cor amarela")
        case .pink:   return L("Cor rosa")
        case .blue:   return L("Cor azul")
        case .green:  return L("Cor verde")
        case .orange: return L("Cor laranja")
        case .purple: return L("Cor roxa")
        }
    }

    // MARK: - Ações

    @objc private func newNote(_ sender: NSMenuItem) {
        guard let folder = sender.representedObject as? String else { return }
        _ = NoteStore.shared.createNote(inFolder: folder,
                                        frame: NoteWindowManager.shared.suggestedFrame())
    }

    @objc private func openFolder(_ sender: NSMenuItem) {
        guard let folder = sender.representedObject as? String,
              Self.isValidFolder(folder) else { return }   // revalida no clique
        // Abre o alvo resolvido — o mesmo que foi validado.
        NSWorkspace.shared.open(URL(fileURLWithPath: folder, isDirectory: true).resolvingSymlinksInPath())
    }

    @objc private func exportNote(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? UUID,
              let note = NoteStore.shared.loadNote(id: id) else { return }
        ExportService.share(note: note, relativeTo: nil)
    }

    @objc private func deleteNote(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? UUID else { return }
        // Sem alerta: recuperável — fica 5 dias na Lixeira do app.
        NoteStore.shared.moveToTrash(id: id)
    }

    @objc private func restoreNote(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? UUID else { return }
        NoteStore.shared.restoreFromTrash(id: id)
    }

    @objc private func deleteForever(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? UUID else { return }
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = L("Apagar definitivamente?")
        alert.informativeText = L("Aí sim não dá para desfazer.")
        alert.alertStyle = .warning
        let button = alert.addButton(withTitle: L("Apagar"))
        if #available(macOS 11.0, *) { button.hasDestructiveAction = true }
        alert.addButton(withTitle: L("Cancelar"))
        if alert.runModal() == .alertFirstButtonReturn {
            NoteStore.shared.deletePermanently(id: id)
        }
    }

    @objc private func emptyTrashAction() {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = L("Esvaziar a Lixeira?")
        alert.informativeText = L("Todas as notas da Lixeira serão apagadas de vez.")
        alert.alertStyle = .warning
        let button = alert.addButton(withTitle: L("Esvaziar"))
        if #available(macOS 11.0, *) { button.hasDestructiveAction = true }
        alert.addButton(withTitle: L("Cancelar"))
        if alert.runModal() == .alertFirstButtonReturn {
            NoteStore.shared.emptyTrash()
        }
    }

    @objc private func reattachOrphan(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? UUID else { return }
        NSApp.activate(ignoringOtherApps: true)
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = L("Escolher")
        panel.message = L("Escolha a nova pasta desta nota.")
        if panel.runModal() == .OK, let url = panel.url {
            NoteStore.shared.reattach(id: id, toFolder: url.path)
        }
    }

    @objc private func openSettings() {
        PreferencesWindowController.shared.show(finder: finder)
    }

    @objc private func openGallery() {
        GalleryWindowController.shared.show()
    }

    @objc private func lockNotes() {
        PasswordService.isLocked = true
    }

    @objc private func unlockNotes() {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = L("Desbloquear Notas")
        alert.informativeText = L("Digite a senha para visualizar e editar suas notas.")
        alert.addButton(withTitle: L("Confirmar"))
        alert.addButton(withTitle: L("Cancelar"))
        
        let input = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 220, height: 24))
        alert.accessoryView = input
        alert.window.initialFirstResponder = input
        
        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            let pass = input.stringValue
            if PasswordService.verifyPassword(pass) {
                PasswordService.isLocked = false
            } else {
                let err = NSAlert()
                err.messageText = L("Senha incorreta")
                err.informativeText = L("A senha digitada está incorreta. Tente novamente.")
                err.addButton(withTitle: L("Ok"))
                err.runModal()
            }
        }
    }

    @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
        let event = NSApp.currentEvent
        let isRightClick = event?.type == .rightMouseUp
        let isCmdClick = event?.modifierFlags.contains(.command) == true
        
        if isRightClick || isCmdClick {
            showPasswordSettings()
        } else {
            statusItem.popUpMenu(menu)
        }
    }

    private func showPasswordSettings() {
        NSApp.activate(ignoringOtherApps: true)
        if !PasswordService.hasPassword {
            // Definir senha
            let alert = NSAlert()
            alert.messageText = L("Definir Senha do The Styk")
            alert.informativeText = L("Digite uma senha para proteger suas notas quando o aplicativo estiver bloqueado.")
            alert.addButton(withTitle: L("Confirmar"))
            alert.addButton(withTitle: L("Cancelar"))
            
            let input = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 220, height: 24))
            alert.accessoryView = input
            alert.window.initialFirstResponder = input
            
            let response = alert.runModal()
            if response == .alertFirstButtonReturn {
                let pass = input.stringValue
                if !pass.isEmpty {
                    PasswordService.setPassword(pass)
                    let info = NSAlert()
                    info.messageText = L("Senha definida")
                    info.informativeText = L("A senha foi cadastrada. Suas notas agora podem ser protegidas.")
                    info.addButton(withTitle: L("Ok"))
                    info.runModal()
                }
            }
        } else {
            // Alterar/Remover senha
            let alert = NSAlert()
            alert.messageText = L("Alterar ou Remover Senha")
            alert.informativeText = L("Digite a senha atual para alterá-la ou removê-la.")
            alert.addButton(withTitle: L("Confirmar"))
            alert.addButton(withTitle: L("Cancelar"))
            
            let currentInput = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 220, height: 24))
            alert.accessoryView = currentInput
            alert.window.initialFirstResponder = currentInput
            
            let response = alert.runModal()
            if response == .alertFirstButtonReturn {
                let currentPass = currentInput.stringValue
                if PasswordService.verifyPassword(currentPass) {
                    // Senha atual correta! Agora pergunte pela nova senha
                    let newAlert = NSAlert()
                    newAlert.messageText = L("Digite a nova senha")
                    newAlert.informativeText = L("Digite a nova senha desejada ou deixe em branco para remover a proteção por senha.")
                    newAlert.addButton(withTitle: L("Confirmar"))
                    newAlert.addButton(withTitle: L("Cancelar"))
                    
                    let newInput = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 220, height: 24))
                    newAlert.accessoryView = newInput
                    newAlert.window.initialFirstResponder = newInput
                    
                    let newResponse = newAlert.runModal()
                    if newResponse == .alertFirstButtonReturn {
                        let newPass = newInput.stringValue
                        PasswordService.setPassword(newPass)
                        let info = NSAlert()
                        if newPass.isEmpty {
                            info.messageText = L("Senha removida")
                            info.informativeText = L("A proteção por senha foi desativada.")
                        } else {
                            info.messageText = L("Senha alterada")
                            info.informativeText = L("Sua senha foi atualizada com sucesso.")
                        }
                        info.addButton(withTitle: L("Ok"))
                        info.runModal()
                    }
                } else {
                    let err = NSAlert()
                    err.messageText = L("Senha incorreta")
                    err.informativeText = L("A senha digitada está incorreta. Operação cancelada.")
                    err.addButton(withTitle: L("Ok"))
                    err.runModal()
                }
            }
        }
    }

    @objc private func showAbout() {
        NSApp.activate(ignoringOtherApps: true)
        let credits = NSAttributedString(
            string: L("Notas adesivas que grudam nas suas pastas."),
            attributes: [.font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)]
        )
        let info = Bundle.main.infoDictionary
        var options: [NSApplication.AboutPanelOptionKey: Any] = [.credits: credits]
        options[.applicationVersion] = (info?["CFBundleShortVersionString"] as? String) ?? "1.0"
        if info?["NSHumanReadableCopyright"] == nil {
            options[NSApplication.AboutPanelOptionKey(rawValue: "Copyright")] = "© 2026 Allan Pscheidt"
        }
        NSApp.orderFrontStandardAboutPanel(options: options)
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }
}
