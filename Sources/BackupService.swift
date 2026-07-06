import AppKit

/// Backup local em zip (via /usr/bin/ditto — executável constante, caminhos vêm
/// do nosso diretório de dados ou de NSSave/OpenPanel, nunca de conteúdo de nota).
enum BackupService {

    static let autoKey = "thestyk.autoBackup"
    static let valueKey = "thestyk.autoBackupValue"
    static let unitKey = "thestyk.autoBackupUnit"
    static let lastBackupKey = "thestyk.lastBackupTime"

    static var backupsDir: URL {
        NoteStore.shared.dataDirectory.appendingPathComponent("Backups", isDirectory: true)
    }

    private static var checkTimer: Timer?

    /// Inicia o agendador de backup periódico (verificação imediata e a cada 15 min).
    static func startPeriodicTimer() {
        checkTimer?.invalidate()
        guard UserDefaults.standard.bool(forKey: autoKey) else { return }
        
        checkAndRunBackup()
        
        let t = Timer(timeInterval: 900, repeats: true) { _ in
            checkAndRunBackup()
        }
        RunLoop.main.add(t, forMode: .common)
        checkTimer = t
    }

    static func stopPeriodicTimer() {
        checkTimer?.invalidate()
        checkTimer = nil
    }

    static func checkAndRunBackup() {
        guard UserDefaults.standard.bool(forKey: autoKey) else { return }
        
        let value = UserDefaults.standard.integer(forKey: valueKey)
        let val = value > 0 ? value : 1
        let unitRaw = UserDefaults.standard.string(forKey: unitKey) ?? "days"
        
        let secondsPerUnit: TimeInterval
        switch unitRaw {
        case "hours": secondsPerUnit = 3600
        case "weeks": secondsPerUnit = 86400 * 7
        default:      secondsPerUnit = 86400 // "days"
        }
        
        let interval = Double(val) * secondsPerUnit
        let lastBackup = UserDefaults.standard.object(forKey: lastBackupKey) as? Date ?? Date.distantPast
        
        if Date().timeIntervalSince(lastBackup) >= interval {
            DispatchQueue.global(qos: .utility).async {
                let fm = FileManager.default
                try? fm.createDirectory(at: backupsDir, withIntermediateDirectories: true)
                let df = DateFormatter()
                df.dateFormat = "yyyy-MM-dd_HH-mm"
                let dest = backupsDir.appendingPathComponent("TheStyk-\(df.string(from: Date())).zip")
                guard !fm.fileExists(atPath: dest.path) else { return }
                if makeBackup(to: dest) {
                    UserDefaults.standard.set(Date(), forKey: lastBackupKey)
                    prune()
                }
            }
        }
    }

    /// Zipa index.json + notes/ (via staging — nunca inclui a pasta Backups).
    @discardableResult
    static func makeBackup(to dest: URL) -> Bool {
        let fm = FileManager.default
        let data = NoteStore.shared.dataDirectory
        guard fm.fileExists(atPath: data.appendingPathComponent("index.json").path) else { return false }

        let stageRoot = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("TheStyk-stage-" + UUID().uuidString, isDirectory: true)
        let stage = stageRoot.appendingPathComponent("The Styk", isDirectory: true)
        defer { try? fm.removeItem(at: stageRoot) }
        do {
            try fm.createDirectory(at: stage, withIntermediateDirectories: true)
            try fm.copyItem(at: data.appendingPathComponent("index.json"),
                            to: stage.appendingPathComponent("index.json"))
            let notes = data.appendingPathComponent("notes", isDirectory: true)
            if fm.fileExists(atPath: notes.path) {
                try fm.copyItem(at: notes, to: stage.appendingPathComponent("notes"))
            }
        } catch { return false }
        try? fm.removeItem(at: dest)
        return runDitto(["-c", "-k", "--keepParent", stage.path, dest.path])
    }

    /// Restaura de um zip. Devolve o nº de notas restauradas, ou -1 (arquivo inválido —
    /// nesse caso NADA foi alterado). Anti zip-slip: extrai em tmp e copia SÓ os
    /// arquivos esperados (index.json + notes/<UUID>.json regulares, com limites).
    static func restore(from zip: URL) -> Int {
        let fm = FileManager.default
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("TheStyk-restore-" + UUID().uuidString, isDirectory: true)
        defer { try? fm.removeItem(at: tmp) }

        guard runDitto(["-x", "-k", zip.path, tmp.path]),
              let root = findDataRoot(in: tmp) else { return -1 }

        // Valida o índice ANTES de tocar nos dados atuais.
        let newIndex = root.appendingPathComponent("index.json")
        guard isRegularFile(newIndex, maxBytes: 5 * 1024 * 1024) else { return -1 }

        let data = NoteStore.shared.dataDirectory
        let liveNotes = data.appendingPathComponent("notes", isDirectory: true)
        try? fm.removeItem(at: liveNotes)
        try? fm.createDirectory(at: liveNotes, withIntermediateDirectories: true)

        var count = 0
        let restored = root.appendingPathComponent("notes", isDirectory: true)
        for f in (try? fm.contentsOfDirectory(at: restored, includingPropertiesForKeys: [.isRegularFileKey])) ?? [] {
            let name = f.lastPathComponent
            guard name.hasSuffix(".json"),
                  UUID(uuidString: String(name.dropLast(5))) != nil,   // nome tem de ser UUID.json
                  isRegularFile(f, maxBytes: 2 * 1024 * 1024),
                  (try? fm.copyItem(at: f, to: liveNotes.appendingPathComponent(name))) != nil
            else { continue }
            count += 1
        }
        try? fm.removeItem(at: data.appendingPathComponent("index.json"))
        try? fm.copyItem(at: newIndex, to: data.appendingPathComponent("index.json"))
        return count
    }

    // MARK: - Helpers

    /// index.json na raiz do zip ou um nível abaixo (layout The Styk/…).
    private static func findDataRoot(in dir: URL) -> URL? {
        let fm = FileManager.default
        if fm.fileExists(atPath: dir.appendingPathComponent("index.json").path) { return dir }
        for sub in (try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
        where fm.fileExists(atPath: sub.appendingPathComponent("index.json").path) {
            return sub
        }
        return nil
    }

    /// Regular de verdade (symlink extraído de zip malicioso não passa) e dentro do limite.
    private static func isRegularFile(_ url: URL, maxBytes: Int) -> Bool {
        guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
              values.isRegularFile == true,
              (values.fileSize ?? .max) <= maxBytes else { return false }
        return true
    }

    private static func prune() {
        let fm = FileManager.default
        let zips = ((try? fm.contentsOfDirectory(at: backupsDir, includingPropertiesForKeys: nil)) ?? [])
            .filter { $0.pathExtension == "zip" }
            .sorted { $0.lastPathComponent > $1.lastPathComponent }   // nome = data → mais novo primeiro
        for old in zips.dropFirst(7) { try? fm.removeItem(at: old) }
    }

    private static func runDitto(_ args: [String]) -> Bool {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        p.arguments = args
        do { try p.run() } catch { return false }
        p.waitUntilExit()
        return p.terminationStatus == 0
    }
}
