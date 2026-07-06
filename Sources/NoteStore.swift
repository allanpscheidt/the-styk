import Foundation

final class NoteStore {
    static let shared = NoteStore()
    static let indexDidChange = Notification.Name("thestyk.indexDidChange")

    private(set) var index: [IndexEntry]
    private(set) var trash: [TrashEntry]

    private let notesDir: URL
    private let trashDir: URL
    private let indexURL: URL
    private let bookmarksURL: URL
    /// Bookmark (base64) por pasta ancorada — segue a pasta quando ela é movida/renomeada.
    private var folderBookmarks: [String: String]
    private var lastReconcile = Date.distantPast
    private var trashPurgeTimer: Timer?
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    // Limites do contrato (anti-DoS / dados adulterados).
    private static let maxIndexBytes: Int64 = 5 * 1024 * 1024
    private static let maxNoteBytes: Int64 = 2 * 1024 * 1024
    private static let maxEntries = 10_000
    private static let maxTextChars = 200_000
    static let trashRetention: TimeInterval = 5 * 86_400   // 5 dias

    private init() {
        let fm = FileManager.default
        let support = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support", isDirectory: true)
        // Seam de teste: THESTYK_DATA_DIR isola o armazenamento (quem controla env já roda código).
        let base: URL
        if let override = ProcessInfo.processInfo.environment["THESTYK_DATA_DIR"], !override.isEmpty {
            base = URL(fileURLWithPath: override, isDirectory: true)
        } else {
            base = support.appendingPathComponent("The Styk", isDirectory: true)
        }
        let notes = base.appendingPathComponent("notes", isDirectory: true)
        let trashD = base.appendingPathComponent("trash", isDirectory: true)
        let idx = base.appendingPathComponent("index.json", isDirectory: false)
        notesDir = notes
        trashDir = trashD
        indexURL = idx
        bookmarksURL = base.appendingPathComponent("folders.json", isDirectory: false)
        do {
            try fm.createDirectory(at: notes, withIntermediateDirectories: true)
            try fm.createDirectory(at: trashD, withIntermediateDirectories: true)
        } catch {
            NSLog("The Styk: falha ao criar diretorios de dados: %@", error.localizedDescription)
        }
        let loaded = NoteStore.loadIndexFile(at: idx)
        index = loaded.0
        trash = loaded.1
        folderBookmarks = NoteStore.loadBookmarks(at: bookmarksURL)
        purgeExpiredTrash()
        reconcileAnchors()

        // App de barra de menus roda semanas sem reiniciar: a promessa dos 5 dias
        // da Lixeira precisa de verificação periódica, não só no boot.
        let timer = Timer(timeInterval: 6 * 3600, repeats: true) { [weak self] _ in
            self?.purgeExpiredTrash()
        }
        RunLoop.main.add(timer, forMode: .common)
        trashPurgeTimer = timer
    }

    /// Raiz dos dados (~/Library/Application Support/The Styk) — usada pelo backup.
    var dataDirectory: URL { indexURL.deletingLastPathComponent() }

    /// Relê o índice do disco (após restauração de backup) e notifica.
    func reloadFromDisk() {
        let loaded = NoteStore.loadIndexFile(at: indexURL)
        index = loaded.0
        trash = loaded.1
        postIndexDidChange()
    }

    // MARK: - Consulta

    func entries(inFolder folder: String) -> [IndexEntry] {
        let f = normalizePath(folder)
        return index.filter { $0.folder == f }
    }

    func folders() -> [String] {
        return Array(Set(index.filter { $0.orphaned != true }.map { $0.folder })).sorted()
    }

    /// Notas cuja pasta original foi apagada — vivem na seção "Notas órfãs".
    func orphans() -> [IndexEntry] {
        return index.filter { $0.orphaned == true }
    }

    // MARK: - Lazy load da nota completa

    func loadNote(id: UUID) -> Note? {
        let url = noteURL(id)
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attrs[.size] as? NSNumber, size.int64Value <= NoteStore.maxNoteBytes,
              let data = try? Data(contentsOf: url),
              Int64(data.count) <= NoteStore.maxNoteBytes,   // re-checa pós-leitura (TOCTOU)
              var note = try? decoder.decode(Note.self, from: data),
              note.id == id,
              note.folder.hasPrefix("/")
        else { return nil }

        note.folder = normalizePath(note.folder)
        if note.text.count > NoteStore.maxTextChars {
            note.text = String(note.text.prefix(NoteStore.maxTextChars))
        }
        note.style.fontSize = NoteStore.clamp(note.style.fontSize, 8, 72)
        note.frame.w = NoteStore.clamp(note.frame.w, 120, 4_000)
        note.frame.h = NoteStore.clamp(note.frame.h, 120, 4_000)
        if !note.frame.x.isFinite { note.frame.x = 0 }
        if !note.frame.y.isFinite { note.frame.y = 0 }
        return note
    }

    // MARK: - Mutação

    func createNote(inFolder folder: String, frame: NoteFrame) -> Note {
        let now = Date()
        let note = Note(id: UUID(),
                        folder: normalizePath(folder),
                        text: "",
                        style: NoteStyle(color: .yellow, fontID: .system, fontSize: 14),
                        frame: frame,
                        created: now,
                        modified: now)
        writeNoteFile(note)
        index.append(indexEntry(for: note))
        bookmarkFolder(note.folder)   // para migrar junto se a pasta for movida
        writeIndex()
        postIndexDidChange()
        return note
    }

    func save(_ note: Note) {
        var n = note
        n.modified = Date()
        n.folder = normalizePath(n.folder)
        if n.text.count > NoteStore.maxTextChars {
            n.text = String(n.text.prefix(NoteStore.maxTextChars))
        }
        writeNoteFile(n)
        let entry = indexEntry(for: n)
        if let i = index.firstIndex(where: { $0.id == n.id }) {
            index[i] = entry
        } else {
            index.append(entry)
        }
        writeIndex()
        postIndexDidChange()
    }

    // MARK: - Lixeira (recuperável por 5 dias)

    /// Move a nota para a Lixeira do app.
    func moveToTrash(id: UUID) {
        guard let i = index.firstIndex(where: { $0.id == id }) else { return }
        let entry = index.remove(at: i)
        let fm = FileManager.default
        let dest = trashDir.appendingPathComponent(id.uuidString + ".json", isDirectory: false)
        try? fm.removeItem(at: dest)
        do {
            try fm.moveItem(at: noteURL(id), to: dest)
            trash.append(TrashEntry(id: entry.id, folder: entry.folder,
                                    snippet: entry.snippet, color: entry.color, deletedAt: Date()))
        } catch {
            NSLog("The Styk: falha ao mover nota %@ para a lixeira: %@", id.uuidString, error.localizedDescription)
            try? fm.removeItem(at: noteURL(id))   // não deixar arquivo solto fora do índice
        }
        writeIndex()
        postIndexDidChange()
    }

    /// Restaura da Lixeira; se a pasta original sumiu, volta como nota órfã.
    func restoreFromTrash(id: UUID) {
        guard let i = trash.firstIndex(where: { $0.id == id }) else { return }
        let t = trash[i]
        let fm = FileManager.default
        do {
            try fm.moveItem(at: trashDir.appendingPathComponent(id.uuidString + ".json", isDirectory: false),
                            to: noteURL(id))
        } catch {
            NSLog("The Styk: falha ao restaurar nota %@: %@", id.uuidString, error.localizedDescription)
            return
        }
        trash.remove(at: i)
        var isDir: ObjCBool = false
        let folderExists = fm.fileExists(atPath: t.folder, isDirectory: &isDir) && isDir.boolValue
        index.append(IndexEntry(id: t.id, folder: t.folder, snippet: t.snippet,
                                color: t.color, modified: Date(),
                                orphaned: folderExists ? nil : true))
        writeIndex()
        postIndexDidChange()
    }

    func deletePermanently(id: UUID) {
        trash.removeAll { $0.id == id }
        try? FileManager.default.removeItem(
            at: trashDir.appendingPathComponent(id.uuidString + ".json", isDirectory: false))
        writeIndex()
        postIndexDidChange()
    }

    func emptyTrash() {
        for t in trash {
            try? FileManager.default.removeItem(
                at: trashDir.appendingPathComponent(t.id.uuidString + ".json", isDirectory: false))
        }
        trash = []
        writeIndex()
        postIndexDidChange()
    }

    private func purgeExpiredTrash() {
        let cutoff = Date(timeIntervalSinceNow: -NoteStore.trashRetention)
        let expired = trash.filter { $0.deletedAt < cutoff }
        guard !expired.isEmpty else { return }
        for t in expired {
            try? FileManager.default.removeItem(
                at: trashDir.appendingPathComponent(t.id.uuidString + ".json", isDirectory: false))
        }
        trash.removeAll { $0.deletedAt < cutoff }
        writeIndex()
        postIndexDidChange()
    }

    // MARK: - Âncoras: pasta movida migra, apagada vira órfã, recriada des-órfã

    /// Reanexa uma nota (órfã ou não) a outra pasta.
    func reattach(id: UUID, toFolder folder: String) {
        guard var note = loadNote(id: id) else { return }
        let f = normalizePath(folder)
        note.folder = f
        note.modified = Date()
        writeNoteFile(note)
        if let i = index.firstIndex(where: { $0.id == id }) {
            index[i].folder = f
            index[i].orphaned = nil
            index[i].modified = note.modified
        }
        bookmarkFolder(f)
        writeIndex()
        postIndexDidChange()
    }

    /// Versão com throttle (máx. 1×/30 s) para chamar a cada troca de pasta no Finder.
    func reconcileAnchorsIfStale() {
        guard Date().timeIntervalSince(lastReconcile) > 30 else { return }
        reconcileAnchors()
    }

    func reconcileAnchors() {
        lastReconcile = Date()
        let fm = FileManager.default
        var changed = false

        for folder in Set(index.map { $0.folder }) {
            var isDir: ObjCBool = false
            let exists = fm.fileExists(atPath: folder, isDirectory: &isDir) && isDir.boolValue
            let isOrphan = index.first(where: { $0.folder == folder })?.orphaned == true

            if exists {
                if isOrphan {   // pasta voltou a existir → deixa de ser órfã
                    for i in index.indices where index[i].folder == folder { index[i].orphaned = nil }
                    changed = true
                }
                bookmarkFolder(folder)
                continue
            }

            // Pasta sumiu do caminho antigo. Bookmark resolve para um destino válido? → migrou.
            var newPath: String?
            if let b64 = folderBookmarks[folder], let data = Data(base64Encoded: b64) {
                var stale = false
                if let resolved = try? URL(resolvingBookmarkData: data, options: [.withoutUI],
                                           relativeTo: nil, bookmarkDataIsStale: &stale) {
                    let p = normalizePath(resolved.path)
                    var rIsDir: ObjCBool = false
                    // Pasta jogada no Lixo do Finder conta como apagada, não como movida.
                    if p != folder, !p.contains("/.Trash"),
                       fm.fileExists(atPath: p, isDirectory: &rIsDir), rIsDir.boolValue {
                        newPath = p
                    }
                }
            }

            if let newPath = newPath {
                for i in index.indices where index[i].folder == folder {
                    index[i].folder = newPath
                    index[i].orphaned = nil
                    if var note = loadNote(id: index[i].id) {
                        note.folder = newPath
                        writeNoteFile(note)
                    }
                }
                folderBookmarks[newPath] = folderBookmarks.removeValue(forKey: folder)
                writeBookmarks()
                changed = true
                // Sem caminhos no log unificado (dado potencialmente pessoal) — só a contagem.
                NSLog("The Styk: pasta ancorada migrada (%d nota(s))",
                      index.filter { $0.folder == newPath }.count)
            } else if !isOrphan {
                for i in index.indices where index[i].folder == folder { index[i].orphaned = true }
                changed = true
            }
        }
        if changed {
            writeIndex()
            postIndexDidChange()
        }
    }

    private func bookmarkFolder(_ folder: String) {
        guard folderBookmarks[folder] == nil,
              let data = try? URL(fileURLWithPath: folder, isDirectory: true)
                  .bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
        else { return }
        folderBookmarks[folder] = data.base64EncodedString()
        writeBookmarks()
    }

    private func writeBookmarks() {
        if let data = try? encoder.encode(folderBookmarks) {
            try? data.write(to: bookmarksURL, options: .atomic)
        }
    }

    private static func loadBookmarks(at url: URL) -> [String: String] {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attrs[.size] as? NSNumber, size.int64Value <= 5 * 1024 * 1024,
              let data = try? Data(contentsOf: url),
              Int64(data.count) <= 5 * 1024 * 1024,
              let map = try? JSONDecoder().decode([String: String].self, from: data)
        else { return [:] }
        return map
    }

    // MARK: - Disco

    private struct IndexFileOut: Encodable {
        var version: Int
        var notes: [IndexEntry]
        var trash: [TrashEntry]
    }

    // Entrada inválida é descartada em silêncio sem derrubar o índice inteiro.
    private struct FailableEntry: Decodable {
        let entry: IndexEntry?
        init(from decoder: Decoder) throws {
            entry = try? IndexEntry(from: decoder)
        }
    }

    private struct FailableTrash: Decodable {
        let entry: TrashEntry?
        init(from decoder: Decoder) throws {
            entry = try? TrashEntry(from: decoder)
        }
    }

    private struct IndexFileIn: Decodable {
        var version: Int
        var notes: [FailableEntry]
        var trash: [FailableTrash]?   // ausente em índices antigos
    }

    private static func loadIndexFile(at url: URL) -> ([IndexEntry], [TrashEntry]) {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attrs[.size] as? NSNumber, size.int64Value <= maxIndexBytes,
              let data = try? Data(contentsOf: url),
              Int64(data.count) <= maxIndexBytes,            // re-checa pós-leitura (TOCTOU)
              let file = try? JSONDecoder().decode(IndexFileIn.self, from: data)
        else { return ([], []) }

        var entries: [IndexEntry] = []
        for wrapped in file.notes {
            if entries.count >= maxEntries { break }
            guard var e = wrapped.entry, e.folder.hasPrefix("/") else { continue }
            e.folder = normalizePath(e.folder)
            e.snippet = makeSnippet(e.snippet)
            entries.append(e)
        }
        var trashed: [TrashEntry] = []
        for wrapped in file.trash ?? [] {
            if trashed.count >= maxEntries { break }
            guard var t = wrapped.entry, t.folder.hasPrefix("/") else { continue }
            t.folder = normalizePath(t.folder)
            t.snippet = makeSnippet(t.snippet)
            trashed.append(t)
        }
        return (entries, trashed)
    }

    private func noteURL(_ id: UUID) -> URL {
        return notesDir.appendingPathComponent(id.uuidString + ".json", isDirectory: false)
    }

    private func writeNoteFile(_ note: Note) {
        do {
            let data = try encoder.encode(note)
            try data.write(to: noteURL(note.id), options: .atomic)
        } catch {
            NSLog("The Styk: falha ao gravar nota %@: %@", note.id.uuidString, error.localizedDescription)
        }
    }

    private func writeIndex() {
        do {
            let data = try encoder.encode(IndexFileOut(version: 1, notes: index, trash: trash))
            try data.write(to: indexURL, options: .atomic)
        } catch {
            NSLog("The Styk: falha ao gravar index.json: %@", error.localizedDescription)
        }
    }

    // MARK: - Helpers

    private func indexEntry(for note: Note) -> IndexEntry {
        return IndexEntry(id: note.id,
                          folder: note.folder,
                          snippet: NoteStore.makeSnippet(note.text),
                          color: note.style.color,
                          modified: note.modified)
    }

    /// 1ª linha não vazia, sem chars de controle, máx 60 chars, fallback "Nota vazia".
    private static func makeSnippet(_ text: String) -> String {
        for line in text.components(separatedBy: .newlines) {
            // Cc (controle) e Cf (formato: RLO bidi etc.) fora — snippet vai para títulos de menu.
            let kept = line.unicodeScalars.filter {
                let cat = $0.properties.generalCategory
                return cat != .control && cat != .format
            }
            let clean = String(String.UnicodeScalarView(kept)).trimmingCharacters(in: .whitespaces)
            if !clean.isEmpty { return String(clean.prefix(60)) }
        }
        return "Nota vazia"
    }

    private static func clamp(_ v: Double, _ lo: Double, _ hi: Double) -> Double {
        guard v.isFinite else { return lo }
        return min(max(v, lo), hi)
    }

    private func postIndexDidChange() {
        if Thread.isMainThread {
            NotificationCenter.default.post(name: NoteStore.indexDidChange, object: self)
        } else {
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: NoteStore.indexDidChange, object: self)
            }
        }
    }
}
