import AppKit

final class NoteWindowController: NSWindowController, NSWindowDelegate, NSTextViewDelegate {

    let noteID: UUID

    // Tinta escura fixa (#1C1C1E) — papel pastel, texto legível nos dois modos.
    private static let ink = NSColor(srgbRed: 0x1C / 255.0, green: 0x1C / 255.0,
                                     blue: 0x1E / 255.0, alpha: 1)

    private var note: Note
    private var textView: NSTextView!
    private var hoverChip: NSView!
    private var containerView: HoverTrackingView!
    private var colorDots: [NSButton] = []
    private var backgroundView: NSView!
    private var fallbackTintLayer: CALayer?
    private var mouseInside = false

    private var textSaveTimer: Timer?
    private var frameSaveTimer: Timer?
    private var textDirty = false
    private var frameDirty = false
    private var deleted = false

    // Ancoragem à janela do Finder (a nota "gruda" na janela).
    private var lastWindowTopLeft: NSPoint?
    private var isProgrammaticMove = false

    // MARK: - Acessibilidade (estado do sistema, lido ao vivo)

    private var reduceMotion: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }
    private var reduceTransparency: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency }
    private var increaseContrast: Bool { NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast }
    private var differentiateWithoutColor: Bool { NSWorkspace.shared.accessibilityDisplayShouldDifferentiateWithoutColor }

    /// Tinta efetiva: preto puro com Aumentar Contraste ativo.
    private var inkColor: NSColor { increaseContrast ? .black : Self.ink }

    init(note: Note) {
        self.noteID = note.id
        self.note = note

        let rect = Self.onScreenRect(for: note.frame)
        let panel = NSPanel(contentRect: rect,
                            styleMask: [.titled, .fullSizeContentView, .nonactivatingPanel, .resizable],
                            backing: .buffered,
                            defer: false)
        super.init(window: panel)

        configure(panel)
        buildContent(in: panel, size: rect.size)
        panel.delegate = self

        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(accessibilityOptionsDidChange),
            name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(lockStateChanged),
            name: PasswordService.lockStateDidChangeNotification,
            object: nil
        )

        panel.orderFrontRegardless()

        // Nota recém-criada: foco imediato no editor, pronta para digitar.
        if note.text.isEmpty, Date().timeIntervalSince(note.created) < 3 {
            panel.makeKey()
            panel.makeFirstResponder(textView)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) não suportado") }

    deinit {
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        NotificationCenter.default.removeObserver(self)
        textSaveTimer?.invalidate()
        frameSaveTimer?.invalidate()
    }

    // MARK: - Contrato

    func flushPendingSave() {
        textSaveTimer?.invalidate()
        frameSaveTimer?.invalidate()
        guard !deleted, textDirty || frameDirty else { return }
        // Se a nota foi apagada/movida para a lixeira por outro meio (ex: menu de status),
        // não devemos salvá-la novamente, pois isso a ressuscitaria.
        guard NoteStore.shared.index.contains(where: { $0.id == noteID }) else { return }
        syncFromUI()
        textDirty = false
        frameDirty = false
        NoteStore.shared.save(note)
    }

    override func close() {
        flushPendingSave()
        super.close()
    }

    // MARK: - Painel

    private func configure(_ panel: NSPanel) {
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.standardWindowButton(.closeButton)?.isHidden = true
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = true
        panel.isMovableByWindowBackground = true
        panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        panel.minSize = NSSize(width: 160, height: 140)
        panel.isReleasedWhenClosed = false
        panel.animationBehavior = reduceMotion ? .none : .utilityWindow
        // Post-it é sempre papel claro com tinta escura — mesmo visual nos dois modos.
        panel.appearance = NSAppearance(named: .aqua)
    }

    /// Frame salvo fora de qualquer tela volta para o centro da tela principal.
    private static func onScreenRect(for frame: NoteFrame) -> NSRect {
        var rect = NSRect(x: frame.x, y: frame.y,
                          width: min(max(frame.w, 160), 4000),
                          height: min(max(frame.h, 140), 4000))
        let visible = NSScreen.screens.contains { $0.visibleFrame.intersects(rect) }
        if !visible, let vf = NSScreen.main?.visibleFrame {
            rect.origin.x = vf.midX - rect.width / 2
            rect.origin.y = vf.midY - rect.height / 2
        }
        return rect
    }

    // MARK: - Conteúdo

    private func buildContent(in panel: NSPanel, size: NSSize) {
        let scroll = NSScrollView()
        scroll.borderType = .noBorder
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = false
        scroll.automaticallyAdjustsContentInsets = false
        // Topo alto o bastante para a barra de ferramentas não cobrir texto.
        scroll.contentInsets = NSEdgeInsets(top: 56, left: 0, bottom: 0, right: 0)

        let tv = NoteTextView()
        tv.isRichText = false
        tv.importsGraphics = false
        tv.allowsImageEditing = false
        tv.isAutomaticLinkDetectionEnabled = false
        tv.isAutomaticDataDetectionEnabled = false
        tv.isAutomaticTextReplacementEnabled = false
        tv.isAutomaticSpellingCorrectionEnabled = false
        tv.isAutomaticTextCompletionEnabled = false
        tv.allowsUndo = true
        tv.drawsBackground = false
        tv.textContainerInset = NSSize(width: 12, height: 10)
        if PasswordService.isLocked {
            tv.string = L("nota bloqueada, desbloqueie no menu bar")
            tv.isEditable = false
        } else {
            tv.string = note.text
            tv.isEditable = true
        }
        tv.isVerticallyResizable = true
        tv.isHorizontallyResizable = false
        tv.autoresizingMask = [.width]
        tv.minSize = NSSize(width: 0, height: 0)
        tv.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        tv.textContainer?.widthTracksTextView = true
        tv.textContainer?.containerSize = NSSize(width: CGFloat.greatestFiniteMagnitude,
                                                 height: CGFloat.greatestFiniteMagnitude)
        tv.delegate = self
        tv.setAccessibilityLabel(L("Texto da nota"))
        tv.onFontSizeCommand = { [weak self] delta in self?.changeFontSize(by: delta) } // ⌘+ / ⌘−
        textView = tv
        applyTextAttributes()
        scroll.documentView = tv

        let container = HoverTrackingView()
        container.onHover = { [weak self] inside in
            self?.mouseInside = inside
            self?.updateBarVisibility()
        }
        containerView = container
        container.addSubview(scroll)
        scroll.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: container.topAnchor),
            scroll.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            scroll.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: container.trailingAnchor),
        ])
        installHoverChip(in: container)

        let bg = makeBackground(content: container, size: size)
        backgroundView = bg
        panel.contentView = bg

        updateAccessibilityTitle()
    }

    // MARK: - Fundo

    /// Vidro (26+) ou visual effect + cor (fallback); papel sólido com Reduzir Transparência.
    private func makeBackground(content: NSView, size: NSSize) -> NSView {
        let tint = Theme.nsColor(note.style.color)
        if !reduceTransparency {
            if #available(macOS 26.0, *) {
                let glass = NSGlassEffectView(frame: NSRect(origin: .zero, size: size))
                glass.cornerRadius = 12
                glass.tintColor = tint.withAlphaComponent(0.55)
                glass.contentView = content
                return glass
            }
            if #available(macOS 10.14, *) {
                let effect = NSVisualEffectView(frame: NSRect(origin: .zero, size: size))
                effect.material = .hudWindow
                effect.state = .active
                effect.blendingMode = .behindWindow
                effect.maskImage = Self.roundedMask(radius: 12)

                let overlay = NSView(frame: effect.bounds)
                overlay.wantsLayer = true
                overlay.layer?.cornerRadius = 12
                overlay.autoresizingMask = [.width, .height]
                effect.addSubview(overlay)
                fallbackTintLayer = overlay.layer
                
                applyTint()

                content.frame = effect.bounds
                content.autoresizingMask = [.width, .height]
                effect.addSubview(content)
                return effect
            }
        }
        // Papel sólido: Reduzir Transparência ativo, ou ≤10.13 (sem material de blur).
        let plain = NSView(frame: NSRect(origin: .zero, size: size))
        plain.wantsLayer = true
        plain.layer?.cornerRadius = 12
        fallbackTintLayer = plain.layer
        
        applyTint()
        
        content.frame = plain.bounds
        content.autoresizingMask = [.width, .height]
        plain.addSubview(content)
        return plain
    }

    private func applyTint() {
        let tint = Theme.nsColor(note.style.color)
        if #available(macOS 26.0, *), let glass = backgroundView as? NSGlassEffectView {
            glass.tintColor = tint.withAlphaComponent(0.55)
            return
        }
        let isKey = window?.isKeyWindow == true
        let alpha: CGFloat = backgroundView is NSVisualEffectView
            ? (isKey ? 0.85 : 0.96)
            : (reduceTransparency ? 1.0 : 0.97)
        fallbackTintLayer?.backgroundColor = tint.withAlphaComponent(alpha).cgColor
    }

    /// Reconstrói o fundo quando as opções de acessibilidade mudam (ex.: transparência).
    private func rebuildBackground() {
        guard let panel = window else { return }
        let wasEditing = panel.firstResponder === textView
        if #available(macOS 26.0, *), let glass = backgroundView as? NSGlassEffectView {
            glass.contentView = nil
        }
        containerView.removeFromSuperview()
        fallbackTintLayer = nil
        let size = panel.contentView?.bounds.size ?? panel.frame.size
        let bg = makeBackground(content: containerView, size: size)
        backgroundView = bg
        panel.contentView = bg
        if wasEditing { panel.makeFirstResponder(textView) }
    }

    private static func roundedMask(radius: CGFloat) -> NSImage {
        let edge = radius * 2 + 1
        let image = NSImage(size: NSSize(width: edge, height: edge), flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
            return true
        }
        image.capInsets = NSEdgeInsets(top: radius, left: radius, bottom: radius, right: radius)
        image.resizingMode = .stretch
        return image
    }

    // MARK: - Barra de ferramentas (hover / janela key)

    /// (Re)monta a cápsula da barra — fundo próprio para os controles serem
    /// legíveis sobre qualquer cor de papel; opaca sob Reduzir Transparência.
    private func installHoverChip(in container: NSView) {
        hoverChip?.removeFromSuperview()
        colorDots = []

        let dotsRow = NSStackView()
        dotsRow.orientation = .horizontal
        dotsRow.spacing = 2
        for (i, color) in NoteColor.allCases.enumerated() {
            let dot = NSButton(title: "", target: self, action: #selector(colorTapped(_:)))
            dot.isBordered = false
            dot.setButtonType(.momentaryChange)
            dot.toolTip = Theme.label(color)
            dot.tag = i
            dot.setAccessibilityHelp(L("Muda a cor do papel desta nota"))
            styleClickTarget(dot)
            colorDots.append(dot)
            dotsRow.addArrangedSubview(dot)
        }

        let actionsRow = NSStackView()
        actionsRow.orientation = .horizontal
        actionsRow.spacing = 2
        actionsRow.addArrangedSubview(textButton("A−", label: L("Diminuir letra"),
                                                 help: L("Diminui o tamanho da letra (⌘−)"),
                                                 action: #selector(fontSmaller)))
        actionsRow.addArrangedSubview(textButton("A+", label: L("Aumentar letra"),
                                                 help: L("Aumenta o tamanho da letra (⌘+)"),
                                                 action: #selector(fontBigger)))
        actionsRow.addArrangedSubview(textButton("Aa", label: L("Trocar fonte"),
                                                 help: L("Alterna entre as fontes da nota"),
                                                 action: #selector(cycleFont)))
        actionsRow.addArrangedSubview(symbolButton("square.and.arrow.up", fallback: "⤴",
                                                   label: L("Exportar nota"),
                                                   help: L("Compartilha o texto desta nota"),
                                                   action: #selector(shareTapped(_:))))
        actionsRow.addArrangedSubview(symbolButton("trash", fallback: "✕",
                                                   label: L("Mover para a Lixeira"),
                                                   help: L("A nota fica 5 dias na Lixeira do The Styk, no menu da barra"),
                                                   action: #selector(deleteTapped)))

        let rows = NSStackView(views: [dotsRow, actionsRow])
        rows.orientation = .vertical
        rows.alignment = .centerX
        rows.spacing = 2

        let chip = NSView()
        chip.wantsLayer = true
        chip.layer?.cornerRadius = 14
        chip.layer?.backgroundColor = NSColor.white.withAlphaComponent(reduceTransparency ? 1.0 : 0.72).cgColor
        if increaseContrast {
            chip.layer?.borderWidth = 1
            chip.layer?.borderColor = NSColor.black.cgColor
        }
        chip.setAccessibilityElement(true)
        chip.setAccessibilityRole(.group)
        chip.setAccessibilityLabel(L("Ferramentas da nota"))
        chip.alphaValue = (mouseInside || window?.isKeyWindow == true) ? 1 : 0

        chip.addSubview(rows)
        rows.translatesAutoresizingMaskIntoConstraints = false
        chip.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(chip)

        let centerX = chip.centerXAnchor.constraint(equalTo: container.centerXAnchor)
        centerX.priority = NSLayoutConstraint.Priority(900) // painel estreito: chip clipa em vez de quebrar layout
        NSLayoutConstraint.activate([
            rows.topAnchor.constraint(equalTo: chip.topAnchor, constant: 4),
            rows.bottomAnchor.constraint(equalTo: chip.bottomAnchor, constant: -4),
            rows.leadingAnchor.constraint(equalTo: chip.leadingAnchor, constant: 8),
            rows.trailingAnchor.constraint(equalTo: chip.trailingAnchor, constant: -8),
            chip.topAnchor.constraint(equalTo: container.topAnchor, constant: 6),
            centerX,
        ])
        hoverChip = chip
        refreshDots()
    }

    /// A barra aparece com o mouse em cima OU quando a janela vira key
    /// (teclado); fade respeita Reduzir Movimento.
    private func updateBarVisibility() {
        guard hoverChip != nil else { return }
        let shouldShow = (mouseInside || window?.isKeyWindow == true) && !PasswordService.isLocked
        let alpha: CGFloat = shouldShow ? 1 : 0
        if reduceMotion {
            hoverChip.alphaValue = alpha
            return
        }
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.18
            hoverChip.animator().alphaValue = alpha
        }
    }

    func windowDidBecomeKey(_ notification: Notification) {
        updateBarVisibility()
        applyTint()
    }
    func windowDidResignKey(_ notification: Notification) {
        updateBarVisibility()
        applyTint()
    }

    /// Alvo de clique ≥ 24×24 pt (área, não o glifo) + borda com Aumentar Contraste.
    private func styleClickTarget(_ b: NSButton) {
        b.widthAnchor.constraint(greaterThanOrEqualToConstant: 24).isActive = true
        b.heightAnchor.constraint(equalToConstant: 24).isActive = true
        if increaseContrast {
            b.wantsLayer = true
            b.layer?.cornerRadius = 6
            b.layer?.borderWidth = 1
            b.layer?.borderColor = NSColor.black.withAlphaComponent(0.6).cgColor
        }
    }

    private func textButton(_ title: String, label: String, help: String, action: Selector) -> NSButton {
        let b = NSButton(title: title, target: self, action: action)
        b.isBordered = false
        b.setButtonType(.momentaryChange)
        b.attributedTitle = NSAttributedString(string: title, attributes: [
            .font: NSFont.systemFont(ofSize: 11, weight: .semibold),
            .foregroundColor: increaseContrast ? NSColor.black : Self.ink.withAlphaComponent(0.8),
        ])
        b.toolTip = label
        b.setAccessibilityLabel(label)
        b.setAccessibilityHelp(help)
        styleClickTarget(b)
        return b
    }

    private func symbolButton(_ name: String, fallback: String, label: String, help: String,
                              action: Selector) -> NSButton {
        let b = NSButton(title: "", target: self, action: action)
        b.isBordered = false
        b.setButtonType(.momentaryChange)
        if #available(macOS 11.0, *) {
            b.image = NSImage(systemSymbolName: name, accessibilityDescription: label)
            b.contentTintColor = increaseContrast ? .black : Self.ink.withAlphaComponent(0.8)
        } else {
            // ≤10.15: glifo de texto no lugar do SF Symbol
            b.attributedTitle = NSAttributedString(string: fallback, attributes: [
                .font: NSFont.systemFont(ofSize: 12, weight: .semibold),
                .foregroundColor: increaseContrast ? NSColor.black : Self.ink.withAlphaComponent(0.8),
            ])
        }
        b.toolTip = label
        b.setAccessibilityLabel(label)
        b.setAccessibilityHelp(help)
        styleClickTarget(b)
        return b
    }

    /// Bolinha de cor; a cor atual ganha anel de seleção e, com Diferenciar
    /// Sem Cor ativo, uma marca ✓ explícita.
    private static func dotImage(_ color: NSColor, selected: Bool, contrast: Bool, mark: Bool) -> NSImage {
        NSImage(size: NSSize(width: 20, height: 20), flipped: false) { rect in
            let dot = NSBezierPath(ovalIn: rect.insetBy(dx: 4, dy: 4))
            color.setFill()
            dot.fill()
            NSColor.black.withAlphaComponent(contrast ? 0.8 : 0.25).setStroke()
            dot.lineWidth = 1
            dot.stroke()
            if selected {
                let ring = NSBezierPath(ovalIn: rect.insetBy(dx: 1, dy: 1))
                ring.lineWidth = 1.5
                ink.setStroke()
                ring.stroke()
                if mark {
                    let check = "✓" as NSString
                    let attrs: [NSAttributedString.Key: Any] = [
                        .font: NSFont.boldSystemFont(ofSize: 9),
                        .foregroundColor: ink,
                    ]
                    let s = check.size(withAttributes: attrs)
                    check.draw(at: NSPoint(x: rect.midX - s.width / 2, y: rect.midY - s.height / 2),
                               withAttributes: attrs)
                }
            }
            return true
        }
    }

    /// Estado de seleção das bolinhas: visual (anel/✓) + VoiceOver ("selecionada").
    private func refreshDots() {
        let all = NoteColor.allCases
        for (i, dot) in colorDots.enumerated() where i < all.count {
            let color = all[i]
            let selected = color == note.style.color
            dot.image = Self.dotImage(Theme.nsColor(color),
                                      selected: selected,
                                      contrast: increaseContrast,
                                      mark: differentiateWithoutColor)
            let name = Self.colorA11yName(color)
            dot.setAccessibilityLabel(selected ? String(format: L("Cor %@, selecionada"), name)
                                               : String(format: L("Cor %@"), name))
        }
    }

    private static func colorA11yName(_ c: NoteColor) -> String {
        switch c {
        case .yellow: return L("amarela")
        case .pink:   return L("rosa")
        case .blue:   return L("azul")
        case .green:  return L("verde")
        case .orange: return L("laranja")
        case .purple: return L("roxa")
        }
    }

    // MARK: - Acessibilidade dinâmica

    @objc private func accessibilityOptionsDidChange() {
        guard let panel = window else { return }
        panel.animationBehavior = reduceMotion ? .none : .utilityWindow
        applyTextAttributes()
        installHoverChip(in: containerView)
        rebuildBackground()
    }

    /// Tipografia do editor: respiro entre linhas/parágrafos + tinta efetiva.
    private func applyTextAttributes() {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineHeightMultiple = 1.15
        paragraph.paragraphSpacing = CGFloat(note.style.fontSize) * 0.4
        let attrs: [NSAttributedString.Key: Any] = [
            .font: Theme.font(note.style),
            .foregroundColor: inkColor,
            .paragraphStyle: paragraph,
        ]
        textView.defaultParagraphStyle = paragraph
        textView.typingAttributes = attrs
        textView.textColor = inkColor
        textView.insertionPointColor = inkColor
        if let storage = textView.textStorage, storage.length > 0 {
            storage.addAttributes(attrs, range: NSRange(location: 0, length: storage.length))
        }
    }

    /// VoiceOver: título do painel = "Nota: <primeira linha>" (ou "Nota vazia").
    private func updateAccessibilityTitle() {
        let firstLine = textView.string.prefix(300)
            .split(whereSeparator: { $0.isNewline })
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { !$0.isEmpty } ?? ""
        let snippet = firstLine.isEmpty ? L("Nota vazia") : String(firstLine.prefix(60))
        window?.title = String(format: L("Nota: %@"), snippet)
    }

    // MARK: - Ações

    @objc private func colorTapped(_ sender: NSButton) {
        guard !PasswordService.isLocked else { return }
        let all = NoteColor.allCases
        guard sender.tag >= 0, sender.tag < all.count else { return }
        note.style.color = all[sender.tag]
        applyTint()
        refreshDots()
        saveNow()
    }

    @objc private func fontSmaller() { changeFontSize(by: -2) }
    @objc private func fontBigger() { changeFontSize(by: 2) }

    private func changeFontSize(by delta: Double) {
        guard !PasswordService.isLocked else { return }
        note.style.fontSize = min(max(note.style.fontSize + delta, 8), 72)
        applyTextAttributes()
        saveNow()
    }

    @objc private func cycleFont() {
        guard !PasswordService.isLocked else { return }
        let all = NoteFontID.allCases
        let i = all.firstIndex(of: note.style.fontID) ?? 0
        note.style.fontID = all[(i + 1) % all.count]
        applyTextAttributes()
        saveNow()
    }

    @objc private func shareTapped(_ sender: NSButton) {
        guard !PasswordService.isLocked else { return }
        flushPendingSave()
        syncFromUI()
        ExportService.share(note: note, relativeTo: sender)
    }

    @objc private func deleteTapped() {
        guard !PasswordService.isLocked else { return }
        // Sem alerta: a ação é recuperável — a nota fica 5 dias na Lixeira do app.
        deleted = true
        textSaveTimer?.invalidate()
        frameSaveTimer?.invalidate()
        NoteStore.shared.moveToTrash(id: noteID)
    }

    // MARK: - Persistência

    private func syncFromUI() {
        if !PasswordService.isLocked {
            note.text = textView.string
        }
        if let f = window?.frame {
            note.frame = NoteFrame(x: Double(f.origin.x), y: Double(f.origin.y),
                                   w: Double(f.size.width), h: Double(f.size.height))
        }
    }

    private func saveNow() {
        guard !deleted else { return }
        textSaveTimer?.invalidate()
        frameSaveTimer?.invalidate()
        syncFromUI()
        textDirty = false
        frameDirty = false
        NoteStore.shared.save(note)
    }

    @objc private func lockStateChanged() {
        if PasswordService.isLocked {
            textView.string = L("nota bloqueada, desbloqueie no menu bar")
            textView.isEditable = false
        } else {
            textView.string = note.text
            textView.isEditable = true
        }
        applyTextAttributes()
        updateAccessibilityTitle()
        updateBarVisibility()
    }

    func textDidChange(_ notification: Notification) {
        updateAccessibilityTitle()
        textDirty = true
        textSaveTimer?.invalidate()
        textSaveTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: false) { [weak self] _ in
            self?.flushPendingSave()
        }
    }

    func windowDidMove(_ notification: Notification) {
        // Arrasto do usuário redefine a âncora; movimento programático (janela do
        // Finder mudou) mantém a âncora que o causou.
        if !isProgrammaticMove { recomputeAnchor() }
        scheduleFrameSave()
    }

    func windowDidEndLiveResize(_ notification: Notification) {
        if !isProgrammaticMove { recomputeAnchor() }
        scheduleFrameSave()
    }

    // MARK: - Âncora na janela do Finder

    /// Reposiciona a nota mantendo o offset (dx, dy) em relação ao canto
    /// superior-esquerdo da janela do Finder. Primeiro show sem âncora: adota a
    /// posição atual como âncora.
    func updateAnchoredPosition(windowTopLeft: NSPoint) {
        lastWindowTopLeft = windowTopLeft
        guard let window = window else { return }
        guard let anchor = note.anchor else {
            recomputeAnchor()
            scheduleFrameSave()
            return
        }
        var f = window.frame
        f.origin.x = windowTopLeft.x + CGFloat(anchor.dx)
        f.origin.y = windowTopLeft.y - CGFloat(anchor.dy) - f.height
        f = Self.clampPartiallyVisible(f, near: windowTopLeft)
        guard f != window.frame else { return }
        isProgrammaticMove = true
        window.setFrame(f, display: true)
        isProgrammaticMove = false
        scheduleFrameSave()   // persiste o frame absoluto novo
    }

    private func recomputeAnchor() {
        guard let topLeft = lastWindowTopLeft, let f = window?.frame else { return }
        note.anchor = NoteAnchor(dx: Double(f.minX - topLeft.x),
                                 dy: Double(topLeft.y - f.maxY))
    }

    /// Garante pelo menos 40 pt da nota visíveis na tela onde está a janela do Finder.
    private static func clampPartiallyVisible(_ f: NSRect, near p: NSPoint) -> NSRect {
        let screen = NSScreen.screens.first { NSPointInRect(p, $0.frame) }
            ?? NSScreen.main
        guard let v = screen?.visibleFrame else { return f }
        var r = f
        r.origin.x = min(max(r.origin.x, v.minX - r.width + 40), v.maxX - 40)
        r.origin.y = min(max(r.origin.y, v.minY - r.height + 40), v.maxY - r.height)
        return r
    }

    private func scheduleFrameSave() {
        frameDirty = true
        frameSaveTimer?.invalidate()
        frameSaveTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { [weak self] _ in
            self?.flushPendingSave()
        }
    }
}

/// View que rastreia hover sem reter o controller (dona da própria tracking area).
private final class HoverTrackingView: NSView {
    var onHover: ((Bool) -> Void)?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero,
                                       options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                       owner: self, userInfo: nil))
    }

    override func mouseEntered(with event: NSEvent) { onHover?(true) }
    override func mouseExited(with event: NSEvent) { onHover?(false) }
}

/// Editor com ⌘+ / ⌘− para ajustar o tamanho da letra sem sair do teclado.
private final class NoteTextView: NSTextView {
    var onFontSizeCommand: ((Double) -> Void)?

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if flags.subtracting([.shift, .numericPad, .function]) == .command,
           let key = event.charactersIgnoringModifiers {
            switch key {
            case "+", "=": onFontSizeCommand?(2); return true
            case "-": onFontSizeCommand?(-2); return true
            default: break
            }
        }
        return super.performKeyEquivalent(with: event)
    }
}
