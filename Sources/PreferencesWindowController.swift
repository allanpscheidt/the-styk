import AppKit
import ServiceManagement

/// Iniciar junto com o sistema.
/// macOS 13+: SMAppService — registro imediato, com o aviso do sistema e entrada
/// em Ajustes → Geral → Itens de Início. macOS ≤ 12: LaunchAgent do usuário
/// (vale a partir do próximo login; não há aviso nessas versões).
enum LoginItem {
    private static var agentURL: URL {
        URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("Library/LaunchAgents/br.com.allanpscheidt.thestyk.plist")
    }

    static var isEnabled: Bool {
        if #available(macOS 13.0, *) { return SMAppService.mainApp.status == .enabled }
        return FileManager.default.fileExists(atPath: agentURL.path)
    }

    /// Liga/desliga. Devolve uma mensagem para mostrar ao usuário, ou nil se silencioso.
    @discardableResult
    static func setEnabled(_ on: Bool) -> String? {
        if #available(macOS 13.0, *) {
            try? FileManager.default.removeItem(at: agentURL)   // nunca duplicar com o agente antigo
            do {
                if on { try SMAppService.mainApp.register() }
                else if SMAppService.mainApp.status == .enabled { try SMAppService.mainApp.unregister() }
            } catch {
                return String(format: L("Não foi possível %@: %@"),
                              on ? L("ativar") : L("desativar"), error.localizedDescription)
            }
            if on && SMAppService.mainApp.status == .requiresApproval {
                SMAppService.openSystemSettingsLoginItems()
                return L("Falta aprovar o The Styk em Ajustes → Geral → Itens de Início (a tela já foi aberta).")
            }
            return nil
        }
        // macOS ≤ 12: LaunchAgent.
        let fm = FileManager.default
        guard on else {
            try? fm.removeItem(at: agentURL)
            return nil
        }
        guard let exec = Bundle.main.executablePath else { return L("Não foi possível localizar o executável do app.") }
        let plist: [String: Any] = [
            "Label": "br.com.allanpscheidt.thestyk",
            "ProgramArguments": [exec],
            "RunAtLoad": true,
            "LimitLoadToSessionType": "Aqua",
            "AssociatedBundleIdentifiers": ["br.com.allanpscheidt.thestyk"],
        ]
        do {
            try fm.createDirectory(at: agentURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
            try data.write(to: agentURL, options: .atomic)
        } catch {
            return String(format: L("Não foi possível ativar: %@"), error.localizedDescription)
        }
        return L("Pronto — o The Styk vai iniciar junto no próximo login.")
    }

    /// Migra o LaunchAgent antigo para SMAppService (preserva a intenção do usuário).
    static func migrateIfNeeded() {
        guard #available(macOS 13.0, *),
              FileManager.default.fileExists(atPath: agentURL.path) else { return }
        try? FileManager.default.removeItem(at: agentURL)
        try? SMAppService.mainApp.register()
    }
}

/// Janela de Configurações: permissão do Finder, início com o sistema e backups.
/// Layout no estilo dos Ajustes do macOS: seções com ícone + explicação em uma
/// linha, grid de 8 pt, largura fixa de 460 pt. Sem animações próprias (Reduce
/// Motion sempre satisfeito); a aparência (claro/escuro) segue o sistema.
final class PreferencesWindowController: NSWindowController {

    static let shared = PreferencesWindowController()

    private weak var finder: FinderObserver?
    private let permissionIcon = NSImageView()
    private let permissionStatus = NSTextField(labelWithString: "")
    private let permissionButton = NSButton(title: "", target: nil, action: nil)   // título em buildUI() (muda com o idioma)
    private let loginCheckbox = NSButton(checkboxWithTitle: "", target: nil, action: nil)
    private let autoBackupCheckbox = NSButton(checkboxWithTitle: "", target: nil, action: nil)
    private let frequencyField = NSTextField()
    private let unitPopup = NSPopUpButton()
    private var rootStack: NSStackView?
    private var footnotes: [NSTextField] = []
    private var glassBackground: NSView?

    private init() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 460, height: 100),
                              styleMask: [.titled, .closable],
                              backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false   // título em buildUI() (muda com o idioma)
        super.init(window: window)
        buildUI()
        applyAccessibilityDisplayOptions()
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(displayOptionsChanged),
            name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil)
    }

    required init?(coder: NSCoder) { fatalError("não usado") }

    func show(finder: FinderObserver) {
        self.finder = finder
        refresh()
        NSApp.activate(ignoringOtherApps: true)
        if window?.isVisible != true { window?.center() }
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }

    // MARK: - UI

    private func buildUI() {
        window?.title = L("Preferências do The Styk")
        footnotes.removeAll()   // reconstrução (troca de idioma) descarta as antigas

        permissionButton.title = L("Pedir permissão do Finder…")
        permissionButton.target = self
        permissionButton.action = #selector(askPermission)
        permissionButton.keyEquivalent = "\r"   // ação primária quando falta permissão; some junto com o botão
        loginCheckbox.title = L("Iniciar o The Styk junto com o sistema")
        loginCheckbox.target = self
        loginCheckbox.action = #selector(toggleLogin)
        autoBackupCheckbox.title = L("Backup automático local")
        autoBackupCheckbox.target = self
        autoBackupCheckbox.action = #selector(toggleAutoBackup)

        frequencyField.target = self
        frequencyField.action = #selector(frequencySettingsChanged)
        frequencyField.controlSize = .small
        
        let formatter = NumberFormatter()
        formatter.numberStyle = .none
        formatter.minimum = 1
        formatter.maximum = 999
        frequencyField.formatter = formatter
        frequencyField.alignment = .center
        frequencyField.widthAnchor.constraint(equalToConstant: 45).isActive = true
        
        unitPopup.removeAllItems()
        unitPopup.addItems(withTitles: [L("horas"), L("dias"), L("semanas")])
        unitPopup.target = self
        unitPopup.action = #selector(frequencySettingsChanged)
        unitPopup.controlSize = .small
        
        let frequencyLabel = NSTextField(labelWithString: L("A cada:"))
        frequencyLabel.font = .systemFont(ofSize: 13)
        
        let frequencyRow = NSStackView(views: [frequencyLabel, frequencyField, unitPopup])
        frequencyRow.orientation = .horizontal
        frequencyRow.spacing = 8
        frequencyRow.alignment = .centerY
        
        frequencyField.setAccessibilityLabel(L("Número do intervalo de backup"))
        unitPopup.setAccessibilityLabel(L("Unidade de tempo do intervalo de backup"))

        let languagePopup = NSPopUpButton()
        languagePopup.addItems(withTitles: AppLanguage.allCases.map { $0.displayName })   // nome nativo — nunca traduzir
        if let idx = AppLanguage.allCases.firstIndex(of: L10n.current) {
            languagePopup.selectItem(at: idx)
        }
        languagePopup.target = self
        languagePopup.action = #selector(languageChanged(_:))

        let backupNow = NSButton(title: L("Fazer backup agora…"), target: self, action: #selector(backupNow(_:)))
        let restoreBtn = NSButton(title: L("Restaurar backup…"), target: self, action: #selector(restoreBackup(_:)))
        if #available(macOS 11.0, *) {
            for button in [permissionButton, backupNow, restoreBtn, languagePopup] { button.controlSize = .large }  // alvo ≥ 28 pt
        }

        // VoiceOver: ajuda em todos os controles; ícones são decorativos (o texto diz o estado).
        languagePopup.setAccessibilityLabel(L("Idioma"))
        permissionButton.setAccessibilityHelp(L("Abre o pedido do sistema para o The Styk ler a pasta frontal do Finder."))
        loginCheckbox.setAccessibilityHelp(L("Abre o The Styk automaticamente quando você faz login."))
        autoBackupCheckbox.setAccessibilityHelp(L("Cria backups locais automáticos e mantém os últimos 7."))
        backupNow.setAccessibilityHelp(L("Salva agora um arquivo .zip com todas as notas."))
        restoreBtn.setAccessibilityHelp(L("Substitui as notas atuais pelas notas de um backup salvo."))
        permissionIcon.setAccessibilityElement(false)

        permissionStatus.font = .systemFont(ofSize: 13)
        Self.enableWrapping(permissionStatus)   // status longo (de/fr) quebra em vez de alargar
        permissionIcon.isHidden = true          // aparece no refresh() quando há SF Symbol (macOS 11+)
        let statusRow = NSStackView(views: [permissionIcon, permissionStatus])
        statusRow.orientation = .horizontal
        statusRow.spacing = 8
        statusRow.alignment = .centerY

        let buttonRow = NSStackView(views: [backupNow, restoreBtn])
        buttonRow.orientation = .horizontal
        buttonRow.spacing = 8

        // Cabeçalho com o logo e texto de ajuda
        let logoView = NSImageView()
        logoView.image = NSApp.applicationIconImage
        logoView.imageScaling = .scaleProportionallyUpOrDown
        logoView.translatesAutoresizingMaskIntoConstraints = false
        logoView.widthAnchor.constraint(equalToConstant: 64).isActive = true
        logoView.heightAnchor.constraint(equalToConstant: 64).isActive = true
        
        let headerText = NSTextField(labelWithString: L("O \"The Styk\" está em execução. Você pode encontrar o seu ícone no lado direito da barra de menus. Abra uma pasta e clique nele para criar sua primeira nota.\n\nClique com o botão direito (ou ⌘-clique) no ícone da barra de menus para definir uma senha."))
        headerText.font = .systemFont(ofSize: 13)
        Self.enableWrapping(headerText)
        headerText.translatesAutoresizingMaskIntoConstraints = false
        headerText.widthAnchor.constraint(equalToConstant: 332).isActive = true
        
        let headerStack = NSStackView(views: [logoView, headerText])
        headerStack.orientation = .horizontal
        headerStack.spacing = 16
        headerStack.alignment = .centerY

        let stack = NSStackView(views: [
            headerStack,
            section(L("Idioma"), symbol: "globe", views: [
                languagePopup,
                footnote(L("Menus e janelas mudam na hora; notas abertas atualizam ao reabrir.")),
            ]),
            section(L("Permissão"), symbol: "lock.shield", views: [
                statusRow,
                footnote(L("Necessária para ancorar as notas à pasta aberta no Finder.")),
                permissionButton,
            ]),
            section(L("Sistema"), symbol: "gearshape", views: [
                loginCheckbox,
                footnote(L("Abre o The Styk automaticamente quando você faz login.")),
            ]),
            section(L("Backup"), symbol: "archivebox", views: [
                autoBackupCheckbox,
                frequencyRow,
                footnote(L("Guarda um backup automático local e mantém os últimos 7.")),
                buttonRow,
                footnote(L("O backup é um .zip com todas as notas em texto (JSON).")),
            ]),
        ])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 24
        stack.edgeInsets = NSEdgeInsets(top: 24, left: 24, bottom: 24, right: 24)
        rootStack = stack

        let container = NSView()
        if #available(macOS 10.14, *) {
            // Toque discreto de material; escondido sob Reduce Transparency (fundo opaco da janela).
            let effect = NSVisualEffectView()
            effect.material = .windowBackground
            effect.blendingMode = .behindWindow
            effect.state = .active
            effect.autoresizingMask = [.width, .height]
            container.addSubview(effect)
            glassBackground = effect
        }
        stack.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: container.topAnchor),
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            stack.widthAnchor.constraint(equalToConstant: 460),
        ])
        window?.contentView = container
        sizeToFit()
        glassBackground?.frame = container.bounds
        window?.initialFirstResponder = permissionButton
    }

    /// Seção no estilo Ajustes: cabeçalho (ícone + título) e conteúdo, agrupados para o VoiceOver.
    private func section(_ title: String, symbol: String, views: [NSView]) -> NSStackView {
        let label = NSTextField(labelWithString: title)
        label.font = .boldSystemFont(ofSize: 13)
        var headerViews: [NSView] = []
        if #available(macOS 11.0, *),
           let image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil) {
            let icon = NSImageView(image: image)
            icon.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 13, weight: .semibold)
            icon.contentTintColor = .controlAccentColor
            icon.setAccessibilityElement(false)   // decorativo — o título ao lado nomeia a seção
            headerViews.append(icon)
        }
        headerViews.append(label)
        let header = NSStackView(views: headerViews)
        header.orientation = .horizontal
        header.spacing = 8
        header.alignment = .centerY

        let stack = NSStackView(views: [header] + views)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.setAccessibilityElement(true)
        stack.setAccessibilityRole(.group)
        stack.setAccessibilityLabel(title)
        return stack
    }

    /// Explicação de 1 linha; cor reforçada quando "Aumentar contraste" está ativo.
    private func footnote(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        if #available(macOS 11.0, *) {
            label.font = .preferredFont(forTextStyle: .footnote, options: [:])
        } else {
            label.font = .systemFont(ofSize: 11)
        }
        label.textColor = .secondaryLabelColor
        Self.enableWrapping(label)
        footnotes.append(label)
        return label
    }

    /// Quebra automática dentro da largura útil (460 − 2×24 de insets): alemão e
    /// francês são ~30% mais longos que o pt-BR e não podem deslocar os controles.
    static func enableWrapping(_ label: NSTextField) {
        label.lineBreakMode = .byWordWrapping
        label.usesSingleLineMode = false
        label.cell?.wraps = true
        label.maximumNumberOfLines = 0
        label.preferredMaxLayoutWidth = 412
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    }

    private func sizeToFit() {
        guard let window = window, let stack = rootStack else { return }
        stack.layoutSubtreeIfNeeded()
        var frame = window.frameRect(forContentRect: NSRect(origin: .zero, size: stack.fittingSize))
        let old = window.frame
        frame.origin = NSPoint(x: old.minX, y: old.maxY - frame.height)   // preserva o canto superior
        window.setFrame(frame, display: true, animate: false)             // nunca anima (Reduce Motion)
    }

    private func refresh() {
        // Estado sempre em palavras + símbolo — nunca só cor (Differentiate Without Color).
        let status: (text: String, symbol: String, tint: NSColor)
        switch finder?.automationStatus() {
        case .some(0):
            status = (L("Acesso ao Finder: concedido"), "checkmark.circle.fill", .systemGreen)
            permissionButton.isHidden = true
        case .some(-1743):
            status = (L("Acesso ao Finder: negado"), "xmark.circle.fill", .systemRed)
            permissionButton.isHidden = false
        case .some:
            status = (L("Acesso ao Finder: ainda não pedido"), "questionmark.circle.fill", .secondaryLabelColor)
            permissionButton.isHidden = false
        case nil:
            status = (L("Acesso ao Finder: automático neste macOS"), "checkmark.circle", .secondaryLabelColor)
            permissionButton.isHidden = true
        }
        permissionStatus.stringValue = status.text
        if #available(macOS 11.0, *) {
            permissionIcon.image = NSImage(systemSymbolName: status.symbol, accessibilityDescription: nil)
            permissionIcon.contentTintColor = status.tint
            permissionIcon.isHidden = false
        }
        loginCheckbox.state = LoginItem.isEnabled ? .on : .off
        
        let isBackupOn = UserDefaults.standard.bool(forKey: BackupService.autoKey)
        autoBackupCheckbox.state = isBackupOn ? .on : .off
        
        let value = UserDefaults.standard.integer(forKey: BackupService.valueKey)
        frequencyField.integerValue = value > 0 ? value : 1
        
        let unitRaw = UserDefaults.standard.string(forKey: BackupService.unitKey) ?? "days"
        let units = ["hours", "days", "weeks"]
        if let idx = units.firstIndex(of: unitRaw) {
            unitPopup.selectItem(at: idx)
        }
        
        frequencyField.isEnabled = isBackupOn
        unitPopup.isEnabled = isBackupOn
        
        sizeToFit()
    }

    // MARK: - Acessibilidade (opções de exibição do sistema, ao vivo)

    @objc private func displayOptionsChanged() { applyAccessibilityDisplayOptions() }

    private func applyAccessibilityDisplayOptions() {
        let workspace = NSWorkspace.shared
        // Reduce Transparency: sem material — fica o fundo opaco da janela.
        glassBackground?.isHidden = workspace.accessibilityDisplayShouldReduceTransparency
        // Increase Contrast: texto secundário mais escuro (controles nativos já reagem sozinhos).
        let color: NSColor = workspace.accessibilityDisplayShouldIncreaseContrast
            ? .labelColor : .secondaryLabelColor
        for label in footnotes { label.textColor = color }
    }

    // MARK: - Ações

    @objc private func languageChanged(_ sender: NSPopUpButton) {
        guard sender.indexOfSelectedItem >= 0 else { return }
        L10n.setCurrent(AppLanguage.allCases[sender.indexOfSelectedItem])
        buildUI()                            // reconstrói tudo no novo idioma (inclui o título da janela)
        applyAccessibilityDisplayOptions()   // reaplica cor nas footnotes novas
        refresh()
    }

    @objc private func askPermission() {
        finder?.requestAutomationPermission { [weak self] in self?.refresh() }
    }

    @objc private func toggleLogin() {
        let message = LoginItem.setEnabled(loginCheckbox.state == .on)
        refresh()   // reflete o estado real (reverte se o registro falhou)
        if let message = message { info(message) }
    }

    @objc private func toggleAutoBackup() {
        UserDefaults.standard.set(autoBackupCheckbox.state == .on, forKey: BackupService.autoKey)
        if autoBackupCheckbox.state == .on {
            BackupService.startPeriodicTimer()
        } else {
            BackupService.stopPeriodicTimer()
        }
        refresh()
    }

    @objc private func frequencySettingsChanged() {
        let val = frequencyField.integerValue
        let savedVal = val > 0 ? val : 1
        UserDefaults.standard.set(savedVal, forKey: BackupService.valueKey)
        
        let units = ["hours", "days", "weeks"]
        let idx = unitPopup.indexOfSelectedItem
        if idx >= 0 && idx < units.count {
            UserDefaults.standard.set(units[idx], forKey: BackupService.unitKey)
        }
        BackupService.startPeriodicTimer()
    }

    @objc private func backupNow(_ sender: Any?) {
        guard let window = window else { return }
        let panel = NSSavePanel()
        panel.allowedFileTypes = ["zip"]
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        panel.nameFieldStringValue = "TheStyk-backup-\(df.string(from: Date())).zip"
        panel.beginSheetModal(for: window) { response in
            guard response == .OK, let dest = panel.url else { return }
            DispatchQueue.global(qos: .userInitiated).async {
                let ok = BackupService.makeBackup(to: dest)
                DispatchQueue.main.async {
                    self.info(ok ? L("Backup salvo.")
                                 : L("Não foi possível criar o backup — crie ao menos uma nota primeiro."))
                }
            }
        }
    }

    @objc private func restoreBackup(_ sender: Any?) {
        guard let window = window else { return }
        let panel = NSOpenPanel()
        panel.allowedFileTypes = ["zip"]
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.beginSheetModal(for: window) { response in
            guard response == .OK, let zip = panel.url else { return }
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = L("Restaurar este backup?")
            alert.informativeText = L("As notas atuais serão substituídas pelas do backup. Esta ação não pode ser desfeita.")
            alert.addButton(withTitle: L("Restaurar"))
            alert.addButton(withTitle: L("Cancelar"))
            guard alert.runModal() == .alertFirstButtonReturn else { return }

            NoteWindowManager.shared.prepareForRestore()   // fecha painéis (com flush) ANTES de trocar os dados
            DispatchQueue.global(qos: .userInitiated).async {
                let count = BackupService.restore(from: zip)
                DispatchQueue.main.async {
                    NoteStore.shared.reloadFromDisk()
                    self.info(count >= 0 ? String(format: L("%d nota(s) restaurada(s)."), count)
                                         : L("Arquivo de backup inválido — nada foi alterado."))
                }
            }
        }
    }

    private func info(_ text: String) {
        let alert = NSAlert()
        alert.messageText = text
        alert.addButton(withTitle: L("OK"))
        if let window = window, window.isVisible {
            alert.beginSheetModal(for: window, completionHandler: nil)
        } else {
            alert.runModal()
        }
    }
}
