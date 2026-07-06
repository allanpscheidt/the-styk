import AppKit

final class GalleryWindowController: NSWindowController, NSWindowDelegate {
    static let shared = GalleryWindowController()
    
    enum ViewMode {
        case grid
        case list
    }
    
    private let searchField = NSSearchField()
    private let colorPopUp = NSPopUpButton()
    private let viewModeSegmented = NSSegmentedControl()
    private let scrollView = NSScrollView()
    private let gridView = GalleryGridView()
    private let emptyLabel = NSTextField(labelWithString: "")
    
    private var currentFilter = ""
    private var currentViewMode: ViewMode = .grid
    
    private init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 680, height: 480),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.minSize = NSSize(width: 480, height: 320)
        window.title = L("Galeria de Notas")
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.delegate = self
        
        buildUI()
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(notesChanged),
            name: NoteStore.indexDidChange,
            object: nil
        )
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(languageChanged),
            name: L10n.didChange,
            object: nil
        )
    }
    
    required init?(coder: NSCoder) { fatalError("não usado") }
    
    func show() {
        refresh()
        NSApp.activate(ignoringOtherApps: true)
        if window?.isVisible != true { window?.center() }
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }
    
    @objc private func notesChanged() {
        refresh()
    }
    
    @objc private func languageChanged() {
        window?.title = L("Galeria de Notas")
        searchField.placeholderString = L("Pesquisar notas...")
        emptyLabel.stringValue = L("Nenhuma nota cadastrada.")
        
        // Atualiza itens do popup de cores
        let selectedIndex = colorPopUp.indexOfSelectedItem
        colorPopUp.removeAllItems()
        colorPopUp.addItem(withTitle: L("Todas as Cores"))
        for color in NoteColor.allCases {
            colorPopUp.addItem(withTitle: L(portugueseColorName(for: color)))
        }
        colorPopUp.selectItem(at: selectedIndex)
        
        // Atualiza labels/tooltips do segmented control
        if #available(macOS 11.0, *) {
            viewModeSegmented.setToolTip(L("Grade"), forSegment: 0)
            viewModeSegmented.setToolTip(L("Lista"), forSegment: 1)
        } else {
            viewModeSegmented.setLabel(L("Grade"), forSegment: 0)
            viewModeSegmented.setLabel(L("Lista"), forSegment: 1)
        }
        
        refresh()
    }
    
    private func portugueseColorName(for color: NoteColor) -> String {
        switch color {
        case .yellow: return "Amarelo"
        case .pink: return "Rosa"
        case .blue: return "Azul"
        case .green: return "Verde"
        case .orange: return "Laranja"
        case .purple: return "Roxo"
        }
    }
    
    private func buildUI() {
        guard let contentView = window?.contentView else { return }
        
        window?.appearance = NSAppearance(named: .aqua)
        
        // Search bar
        searchField.placeholderString = L("Pesquisar notas...")
        searchField.target = self
        searchField.action = #selector(searchChanged(_:))
        searchField.translatesAutoresizingMaskIntoConstraints = false
        searchField.setContentHuggingPriority(.defaultLow, for: .horizontal)
        
        // Color popup
        colorPopUp.target = self
        colorPopUp.action = #selector(colorFilterChanged(_:))
        colorPopUp.translatesAutoresizingMaskIntoConstraints = false
        colorPopUp.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        colorPopUp.addItem(withTitle: L("Todas as Cores"))
        for color in NoteColor.allCases {
            colorPopUp.addItem(withTitle: L(portugueseColorName(for: color)))
        }
        
        // View mode segmented control
        viewModeSegmented.segmentCount = 2
        if #available(macOS 11.0, *) {
            viewModeSegmented.setImage(NSImage(systemSymbolName: "square.grid.2x2", accessibilityDescription: L("Grade")), forSegment: 0)
            viewModeSegmented.setImage(NSImage(systemSymbolName: "list.bullet", accessibilityDescription: L("Lista")), forSegment: 1)
            viewModeSegmented.setToolTip(L("Grade"), forSegment: 0)
            viewModeSegmented.setToolTip(L("Lista"), forSegment: 1)
        } else {
            viewModeSegmented.setLabel(L("Grade"), forSegment: 0)
            viewModeSegmented.setLabel(L("Lista"), forSegment: 1)
        }
        viewModeSegmented.selectedSegment = 0
        viewModeSegmented.target = self
        viewModeSegmented.action = #selector(viewModeChanged(_:))
        viewModeSegmented.translatesAutoresizingMaskIntoConstraints = false
        viewModeSegmented.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        
        // Top stack
        let topStack = NSStackView(views: [searchField, colorPopUp, viewModeSegmented])
        topStack.orientation = .horizontal
        topStack.spacing = 12
        topStack.alignment = .centerY
        topStack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(topStack)
        
        // Scroll view
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(scrollView)
        
        // Grid View
        gridView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.documentView = gridView
        
        // Empty Label
        emptyLabel.font = .systemFont(ofSize: 14)
        emptyLabel.textColor = .secondaryLabelColor
        emptyLabel.alignment = .center
        emptyLabel.isHidden = true
        emptyLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(emptyLabel)
        
        // Layout Constraints
        NSLayoutConstraint.activate([
            topStack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 16),
            topStack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            topStack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            topStack.heightAnchor.constraint(equalToConstant: 26),
            
            scrollView.topAnchor.constraint(equalTo: topStack.bottomAnchor, constant: 12),
            scrollView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            
            emptyLabel.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: contentView.centerYAnchor)
        ])
        
        updateScrollConfiguration()
    }
    
    private func updateScrollConfiguration() {
        if currentViewMode == .list {
            scrollView.hasHorizontalScroller = false
            scrollView.hasVerticalScroller = true
            if let doc = scrollView.documentView {
                doc.setFrameSize(NSSize(width: scrollView.contentSize.width, height: doc.frame.height))
            }
        } else {
            scrollView.hasHorizontalScroller = true
            scrollView.hasVerticalScroller = false
            if let doc = scrollView.documentView {
                doc.setFrameSize(NSSize(width: doc.frame.width, height: scrollView.contentSize.height))
            }
        }
        gridView.isListMode = currentViewMode == .list
        gridView.needsLayout = true
    }
    
    @objc private func searchChanged(_ sender: NSSearchField) {
        currentFilter = sender.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        refresh()
    }
    
    @objc private func colorFilterChanged(_ sender: NSPopUpButton) {
        refresh()
    }
    
    @objc private func viewModeChanged(_ sender: NSSegmentedControl) {
        currentViewMode = sender.selectedSegment == 0 ? .grid : .list
        updateScrollConfiguration()
        refresh()
    }
    
    private var selectedColorFilter: NoteColor? {
        let index = colorPopUp.indexOfSelectedItem
        if index <= 0 { return nil }
        return NoteColor.allCases[index - 1]
    }
    
    private func refresh() {
        let allEntries = NoteStore.shared.index
        var filtered = allEntries
        
        // Filtro por cor
        if let colorFilter = selectedColorFilter {
            filtered = filtered.filter { $0.color == colorFilter }
        }
        
        // Filtro por texto de pesquisa
        if !currentFilter.isEmpty {
            let query = currentFilter.lowercased()
            filtered = filtered.filter {
                $0.snippet.lowercased().contains(query) ||
                $0.folder.lowercased().contains(query)
            }
        }
        
        emptyLabel.isHidden = !filtered.isEmpty
        
        let cards = filtered.map { entry -> GalleryCardView in
            let card = GalleryCardView(entry: entry)
            card.onEdit = {
                NoteWindowManager.shared.showNoteForEditing(id: entry.id)
            }
            card.onOpenFolder = {
                let url = URL(fileURLWithPath: entry.folder, isDirectory: true).resolvingSymlinksInPath()
                NSWorkspace.shared.open(url)
            }
            card.isListMode = currentViewMode == .list
            return card
        }
        
        gridView.cards = cards
    }
    
    func windowDidResize(_ notification: Notification) {
        updateScrollConfiguration()
    }
}

// MARK: - Grid / Row Flow Layout

final class GalleryGridView: NSView {
    var isListMode = false
    var cards: [GalleryCardView] = [] {
        didSet {
            subviews.forEach { $0.removeFromSuperview() }
            cards.forEach { addSubview($0) }
            needsLayout = true
        }
    }
    
    override var isFlipped: Bool { true }
    
    override func layout() {
        super.layout()
        let spacing: CGFloat = 16
        let boundsWidth = bounds.width
        
        if isListMode {
            // Modo Lista: Rola Verticalmente, linhas horizontais esticadas
            let rowHeight: CGFloat = 48
            let rowSpacing: CGFloat = 8
            var y: CGFloat = spacing
            
            for card in cards {
                card.isListMode = true
                card.frame = NSRect(x: spacing, y: y, width: max(200, boundsWidth - spacing * 2), height: rowHeight)
                y += rowHeight + rowSpacing
            }
            
            let totalHeight = y + spacing
            if frame.height != totalHeight {
                setFrameSize(NSSize(width: boundsWidth, height: totalHeight))
            }
        } else {
            // Modo Grade Lado a Lado Horizontal: Rola Horizontalmente, uma única linha
            let cardWidth: CGFloat = 180
            let cardHeight: CGFloat = 140
            let y: CGFloat = spacing
            var x: CGFloat = spacing
            
            for card in cards {
                card.isListMode = false
                card.frame = NSRect(x: x, y: y, width: cardWidth, height: cardHeight)
                x += cardWidth + spacing
            }
            
            let totalWidth = x
            let contentHeight = superview?.bounds.height ?? (cardHeight + spacing * 2)
            if frame.width != totalWidth || frame.height != contentHeight {
                setFrameSize(NSSize(width: totalWidth, height: contentHeight))
            }
        }
    }
}

// MARK: - Adaptable Note Item Card/Row

final class GalleryCardView: NSView {
    let entry: IndexEntry
    var onEdit: (() -> Void)?
    var onOpenFolder: (() -> Void)?
    
    var isListMode = false {
        didSet {
            if oldValue != isListMode {
                updateVisuals()
                needsLayout = true
            }
        }
    }
    
    private let colorDot = NSView()
    private let label = NSTextField(labelWithString: "")
    private let folderLabel = NSTextField(labelWithString: "")
    private let editBtn = NSButton()
    private let folderBtn = NSButton()
    private let hoverOverlay = NSView()
    
    init(entry: IndexEntry) {
        self.entry = entry
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 10
        layer?.borderWidth = 1
        
        // Bolinha colorida (usada no modo Lista)
        colorDot.wantsLayer = true
        colorDot.layer?.cornerRadius = 6
        colorDot.isHidden = true
        addSubview(colorDot)
        
        // Snippet de texto
        label.textColor = NSColor(red: 0.16, green: 0.14, blue: 0.08, alpha: 1.0)
        label.cell?.lineBreakMode = .byTruncatingTail
        label.cell?.usesSingleLineMode = false
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        
        // Pasta mãe
        folderLabel.textColor = NSColor.black.withAlphaComponent(0.5)
        folderLabel.lineBreakMode = .byTruncatingMiddle
        folderLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(folderLabel)
        
        // Hover sutil
        hoverOverlay.wantsLayer = true
        hoverOverlay.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.04).cgColor
        hoverOverlay.layer?.cornerRadius = 10
        hoverOverlay.isHidden = true
        hoverOverlay.frame = bounds
        hoverOverlay.autoresizingMask = [.width, .height]
        addSubview(hoverOverlay)
        
        // Botão Editar
        editBtn.isBordered = false
        editBtn.setButtonType(.momentaryChange)
        editBtn.target = self
        editBtn.action = #selector(editClicked)
        if #available(macOS 11.0, *), let img = NSImage(systemSymbolName: "pencil", accessibilityDescription: L("Editar")) {
            editBtn.image = img
        } else {
            editBtn.title = L("Editar")
        }
        addSubview(editBtn)
        
        // Botão Pasta
        folderBtn.isBordered = false
        folderBtn.setButtonType(.momentaryChange)
        folderBtn.target = self
        folderBtn.action = #selector(folderClicked)
        if #available(macOS 11.0, *), let img = NSImage(systemSymbolName: "folder", accessibilityDescription: L("Abrir pasta mãe")) {
            folderBtn.image = img
        } else {
            folderBtn.title = L("Pasta")
        }
        addSubview(folderBtn)
        
        updateVisuals()
        
        let trackingArea = NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingArea)
    }
    
    required init?(coder: NSCoder) { fatalError("não usado") }
    
    private func updateVisuals() {
        let color = Theme.nsColor(entry.color)
        if isListMode {
            layer?.backgroundColor = color.withAlphaComponent(0.12).cgColor
            layer?.borderColor = color.withAlphaComponent(0.25).cgColor
            colorDot.layer?.backgroundColor = color.cgColor
            colorDot.isHidden = false
        } else {
            layer?.backgroundColor = color.cgColor
            layer?.borderColor = NSColor.black.withAlphaComponent(0.08).cgColor
            colorDot.isHidden = true
        }
    }
    
    override var isFlipped: Bool { true }
    
    override func layout() {
        super.layout()
        hoverOverlay.frame = bounds
        
        let pad: CGFloat = 12
        let boundsWidth = bounds.width
        let boundsHeight = bounds.height
        
        // Atualiza textos
        label.stringValue = entry.snippet
        folderLabel.stringValue = (entry.folder as NSString).abbreviatingWithTildeInPath
        
        if isListMode {
            // Bolinha colorida na esquerda
            colorDot.frame = NSRect(x: pad, y: (boundsHeight - 12) / 2, width: 12, height: 12)
            
            let btnWidth: CGFloat = 24
            let rightEdge = boundsWidth - pad
            
            // Botões de ação no canto direito
            folderBtn.frame = NSRect(x: rightEdge - btnWidth, y: (boundsHeight - btnWidth) / 2, width: btnWidth, height: btnWidth)
            editBtn.frame = NSRect(x: folderBtn.frame.minX - btnWidth - 8, y: (boundsHeight - btnWidth) / 2, width: btnWidth, height: btnWidth)
            
            // Espaço de texto centralizado horizontalmente
            let textLeft = colorDot.frame.maxX + 12
            let textRight = editBtn.frame.minX - 12
            let availableTextWidth = max(50, textRight - textLeft)
            
            let snippetWidth = availableTextWidth * 0.65
            let folderWidth = availableTextWidth * 0.35
            
            label.frame = NSRect(x: textLeft, y: (boundsHeight - 18) / 2, width: snippetWidth, height: 18)
            folderLabel.frame = NSRect(x: label.frame.maxX + 8, y: (boundsHeight - 16) / 2, width: folderWidth - 8, height: 16)
            
            label.font = .systemFont(ofSize: 13, weight: .semibold)
            folderLabel.font = .systemFont(ofSize: 11)
            folderLabel.alignment = .right
        } else {
            // Modo Cartão Clássico: Grade horizontal
            let btnWidth: CGFloat = 24
            
            label.frame = NSRect(x: pad, y: pad, width: boundsWidth - pad * 2, height: 60)
            folderLabel.frame = NSRect(x: pad, y: label.frame.maxY + 4, width: boundsWidth - pad * 2, height: 16)
            
            editBtn.frame = NSRect(x: pad, y: boundsHeight - pad - btnWidth, width: btnWidth, height: btnWidth)
            folderBtn.frame = NSRect(x: boundsWidth - pad - btnWidth, y: boundsHeight - pad - btnWidth, width: btnWidth, height: btnWidth)
            
            label.font = .systemFont(ofSize: 13, weight: .semibold)
            folderLabel.font = .systemFont(ofSize: 10)
            folderLabel.alignment = .left
        }
    }
    
    @objc private func editClicked() {
        onEdit?()
    }
    
    @objc private func folderClicked() {
        onOpenFolder?()
    }
    
    override func mouseDown(with event: NSEvent) {
        onEdit?()
    }
    
    override func mouseEntered(with event: NSEvent) {
        hoverOverlay.isHidden = false
    }
    
    override func mouseExited(with event: NSEvent) {
        hoverOverlay.isHidden = true
    }
}
