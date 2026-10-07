import AppKit
import Darwin

/// Local backups use ditto only to create ZIPs. Restore uses a bounded ZIP reader
/// and a validated, durable directory transaction, never an external extractor.
enum BackupService {
    enum RestoreResult: Equatable {
        case restored(Int)
        case unchanged
        /// Commit/rollback durability is uncertain; both stores are retained.
        case recoveryRequired(URL)

        static func fromFailure(_ error: Error) -> RestoreResult {
            if case BackupRestoreTransaction.Failure.rollbackFailed(let directory) = error {
                return .recoveryRequired(directory)
            }
            return .unchanged
        }
    }

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
        guard UserDefaults.standard.bool(forKey: autoKey), !PasswordService.hasPassword else { return }
        
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
        guard UserDefaults.standard.bool(forKey: autoKey), !PasswordService.hasPassword else { return }
        
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

    /// Captures index, active notes, trash and bookmarks, without the backup folder.
    @discardableResult
    static func makeBackup(to dest: URL, authorization: PasswordService.Authorization? = nil) -> Bool {
        guard PasswordService.consumeAuthorization(authorization, for: .backup) else { return false }
        let fm = FileManager.default
        let data = NoteStore.shared.dataDirectory
        guard fm.fileExists(atPath: data.appendingPathComponent("index.json").path) else { return false }

        let stageRoot = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("TheStyk-stage-" + UUID().uuidString, isDirectory: true)
        let stage = stageRoot.appendingPathComponent("The Styk", isDirectory: true)
        let destinationParent = dest.deletingLastPathComponent().resolvingSymlinksInPath()
        let liveRoot = data.resolvingSymlinksInPath()
        let insideLive = destinationParent.path == liveRoot.path || destinationParent.path.hasPrefix(liveRoot.path + "/")
        // A restore can exchange the complete live root while ditto runs. Keep its
        // output outside that root, on the destination's filesystem, until publish.
        let outputParent = insideLive ? data.deletingLastPathComponent() : destinationParent
        let outputRoot = outputParent.appendingPathComponent(".TheStyk-backup-" + UUID().uuidString, isDirectory: true)
        let output = outputRoot.appendingPathComponent("backup.zip")
        defer {
            try? fm.removeItem(at: stageRoot)
            try? fm.removeItem(at: outputRoot)
        }
        do {
            try BackupFiles.createPrivateDirectory(stageRoot)
            try BackupFiles.createPrivateDirectory(stage)
            try BackupFiles.createPrivateDirectory(outputRoot)
            // NoteStore mutations run on the main thread. Capture the complete corpus
            // there so the index, active notes, trash, and bookmarks are one snapshot.
            let snapshot = {
                guard PasswordService.canAccessNotes else { throw BackupRestoreTransaction.Failure.invalidStore }
                for name in ["index.json", "notes", "trash", "folders.json"] {
                    let source = data.appendingPathComponent(name)
                    if fm.fileExists(atPath: source.path) {
                        try fm.copyItem(at: source, to: stage.appendingPathComponent(name))
                    }
                }
            }
            if Thread.isMainThread { try snapshot() }
            else { try DispatchQueue.main.sync(execute: snapshot) }
            _ = try BackupRestoreTransaction.validateStore(stage)
        } catch { return false }
        let createArguments = ["-c", "-k", "--norsrc", "--noextattr", "--noqtn", "--noacl", "--keepParent"]
        guard runDitto(createArguments + [stage.path, output.path]),
              chmod(output.path, 0o600) == 0 else { return false }
        // Validate the produced ZIP too. An incomplete or unsupported backup never
        // replaces a previous destination file.
        let verify = stageRoot.appendingPathComponent("verify", isDirectory: true)
        do {
            try BackupArchive.extract(output, to: verify)
        } catch BackupArchive.Failure.compressionRatioExceeded {
            // Repeated legitimate text may compress beyond the restore ratio cap.
            // Recreate that snapshot without compression rather than emit a backup
            // that the same application would reject, then run every limit again.
            do { try fm.removeItem(at: output) } catch { return false }
            guard runDitto(createArguments + ["--zlibCompressionLevel", "0", stage.path, output.path]),
                  chmod(output.path, 0o600) == 0 else { return false }
            do { try BackupArchive.extract(output, to: verify) } catch { return false }
        } catch { return false }
        let publish = { PasswordService.canAccessNotes && rename(output.path, dest.path) == 0 }
        if Thread.isMainThread { return publish() }
        return DispatchQueue.main.sync(execute: publish)
    }

    /// Distinguishes safe rejection from a commit failure that needs recovery.
    /// Invalid ZIPs/stores and failed preparation never touch the live directory.
    static func restore(from zip: URL, authorization: PasswordService.Authorization? = nil) -> RestoreResult {
        guard PasswordService.consumeAuthorization(authorization, for: .restore) else { return .unchanged }
        do {
            let count = try BackupRestoreTransaction.restore(zip, to: NoteStore.shared.dataDirectory,
                fault: { step in
                    if step == .beforeSwap {
                        guard PasswordService.canAccessNotes else { throw BackupRestoreTransaction.Failure.invalidStore }
                        NoteWindowManager.shared.prepareForRestore()
                        guard PasswordService.canAccessNotes else { throw BackupRestoreTransaction.Failure.invalidStore }
                    }
                },
                serializeCommit: { action in
                    if Thread.isMainThread {
                        guard PasswordService.canAccessNotes else { throw BackupRestoreTransaction.Failure.invalidStore }
                        let count = try action()
                        NoteStore.shared.reloadFromDisk()
                        return count
                    }
                    return try DispatchQueue.main.sync {
                        guard PasswordService.canAccessNotes else { throw BackupRestoreTransaction.Failure.invalidStore }
                        let count = try action()
                        NoteStore.shared.reloadFromDisk()
                        return count
                    }
                })
            return .restored(count)
        } catch {
            NSLog("The Styk: backup restore failed (%@)", String(describing: type(of: error)))
            let result = RestoreResult.fromFailure(error)
            if case .recoveryRequired = result {
                // The swap may have installed the replacement despite a later
                // rollback failure. Never keep the old in-memory index over it.
                if Thread.isMainThread { NoteStore.shared.reloadFromDisk() }
                else { DispatchQueue.main.sync { NoteStore.shared.reloadFromDisk() } }
            }
            return result
        }
    }

    // MARK: - Helpers

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
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        let completed = DispatchSemaphore(value: 0)
        p.terminationHandler = { _ in completed.signal() }
        do { try p.run() } catch { return false }
        if completed.wait(timeout: .now() + 30) == .timedOut {
            p.terminate()
            if completed.wait(timeout: .now() + 2) == .timedOut { kill(p.processIdentifier, SIGKILL) }
            p.waitUntilExit()
            return false
        }
        p.waitUntilExit()
        return p.terminationStatus == 0
    }
}
