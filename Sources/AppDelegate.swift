import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {

    private var statusItem: NSStatusItem?
    private var finderObserver: FinderObserver?
    private var menuController: StatusMenuController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = item.button {
            let image = NSImage(named: "StatusBarIcon")
            image?.isTemplate = true
            button.image = image
            button.toolTip = L("The Styk — notas por pasta")
            button.setAccessibilityLabel(L("The Styk — notas por pasta"))
        }
        statusItem = item

        let observer = FinderObserver()
        finderObserver = observer
        menuController = StatusMenuController(statusItem: item, finder: observer)

        observer.onChange = { folder, bounds in
            // Pastas movidas migram / apagadas viram órfãs (máx. 1 verificação a cada 30 s).
            NoteStore.shared.reconcileAnchorsIfStale()
            NoteWindowManager.shared.setVisibleFolder(folder, windowBounds: bounds)
        }
        observer.start()
        LoginItem.migrateIfNeeded()
        BackupService.startPeriodicTimer()
        ExportService.purgeOldExports()   // cópias temporárias de export não sobrevivem ao relaunch
        showWelcomeOnce()
        
        // Abre a janela de preferências no início
        PreferencesWindowController.shared.show(finder: observer)
        
        // Registra atalho global de teclado (⌥⌘N)
        GlobalShortcutService.shared.onTrigger = { [weak self] in
            self?.handleCreateNoteShortcut()
        }
        GlobalShortcutService.shared.register()
    }

    func applicationWillTerminate(_ notification: Notification) {
        NoteWindowManager.shared.flushAll()
    }

    private func handleCreateNoteShortcut() {
        let isFinderFront = NSWorkspace.shared.frontmostApplication?.bundleIdentifier == "com.apple.finder"
        if isFinderFront, let folder = finderObserver?.currentFolder {
            _ = NoteStore.shared.createNote(
                inFolder: folder,
                frame: NoteWindowManager.shared.suggestedFrame()
            )
        } else {
            showFinderErrorAlert()
        }
    }

    private func showFinderErrorAlert() {
        DispatchQueue.main.async {
            NSApp.activate(ignoringOtherApps: true)
            let alert = NSAlert()
            alert.icon = NSApp.applicationIconImage
            alert.messageText = L("Finder não ativo")
            alert.informativeText = L("Abra uma pasta no Finder para criar uma nota adesiva nesta localização.")
            alert.addButton(withTitle: L("Entendi"))
            alert.runModal()
        }
    }

    /// Ícone da barra desenhado à mão para macOS sem SF Symbols: nota com linhas.


    private func showWelcomeOnce() {
        let key = "thestyk.welcomeShown"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        UserDefaults.standard.set(true, forKey: key)

        let alert = NSAlert()
        alert.icon = NSApp.applicationIconImage
        alert.messageText = L("O The Styk está na barra de menus")
        alert.informativeText = L("""
        Abra uma pasta no Finder e clique no ícone de nota lá em cima para criar sua primeira nota. Ela gruda na pasta: some quando você sai e volta quando você volta.

        Na primeira vez, o macOS pede permissão para o The Styk ver o Finder — é só permitir.
        """)
        alert.addButton(withTitle: L("Entendi"))
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }
}
