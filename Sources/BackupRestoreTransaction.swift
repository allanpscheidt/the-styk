import Foundation
import Darwin

/// A restore only reaches the live store after every reference and JSON file agrees.
/// The prepared store is a sibling of the live store, so RENAME_SWAP is atomic.
enum BackupRestoreTransaction {
    enum Failure: Error { case invalidStore, commitFailed, rollbackFailed(URL) }
    enum CommitStep { case beforeSwap, afterSwap, afterDurability, beforeRollback, afterRollback }

    private struct IndexFile: Decodable {
        let version: Int
        let notes: [IndexEntry]
        let trash: [TrashEntry]?
    }

    static func restore(_ archive: URL, to live: URL, limits: BackupArchive.Limits = .init(),
                        fault: ((CommitStep) throws -> Void)? = nil,
                        serializeCommit: (((() throws -> Int) throws -> Int))? = nil) throws -> Int {
        let fm = FileManager.default
        let parent = live.deletingLastPathComponent()
        guard BackupFiles.isDirectory(parent), BackupFiles.isDirectory(live) else { throw Failure.invalidStore }
        let work = parent.appendingPathComponent(".TheStyk-restore-" + UUID().uuidString, isDirectory: true)
        try BackupFiles.createPrivateDirectory(work)
        var retainRecovery = false
        defer {
            if !retainRecovery { try? fm.removeItem(at: work) }
        }
        let extracted = work.appendingPathComponent("archive", isDirectory: true)
        try BackupArchive.extract(archive, to: extracted, limits: limits)
        let root = try dataRoot(in: extracted)
        let count = try validateStore(root)
        let prepared = work.appendingPathComponent("prepared", isDirectory: true)
        try fm.moveItem(at: root, to: prepared)

        let commit = { () throws -> Int in
            // Keep backups and ancillary files. The application executes this phase
            // on its store's main thread, preventing a save during the directory swap.
            let ancillary = try fm.contentsOfDirectory(at: live, includingPropertiesForKeys: nil).filter { item in
                let name = item.lastPathComponent
                return !["index.json", "notes", "trash"].contains(name) &&
                    !(name == "folders.json" && fm.fileExists(atPath: prepared.appendingPathComponent(name).path))
            }
            let bytesToCopy = try ancillary.reduce(Int64(0)) { try $0 + treeBytes($1) }
            let free = try parent.resourceValues(forKeys: [.volumeAvailableCapacityKey]).volumeAvailableCapacity ?? 0
            guard Int64(free) > bytesToCopy + 16 * 1024 * 1024 else { throw BackupArchive.Failure.limitExceeded }
            for item in ancillary {
                try fm.copyItem(at: item, to: prepared.appendingPathComponent(item.lastPathComponent))
            }
            for directory in ["notes", "trash"] {
                let target = prepared.appendingPathComponent(directory, isDirectory: true)
                if !fm.fileExists(atPath: target.path) { try BackupFiles.createPrivateDirectory(target) }
            }
            // Verify all copies and flush files/directories before the single commit point.
            guard try validateStore(prepared, allowAncillaryFiles: true) == count else { throw Failure.invalidStore }
            try secureAndSyncTree(prepared)
            try BackupFiles.syncDirectory(work)
            try BackupFiles.syncDirectory(parent)
            try fault?(.beforeSwap)
            guard swap(prepared, live) else { throw Failure.commitFailed }
            do {
                try fault?(.afterSwap)
                try BackupFiles.syncDirectory(parent)
                try BackupFiles.syncDirectory(work)
                try fault?(.afterDurability)
            } catch {
                // The previous store remains at prepared until durability is confirmed.
                do {
                    try fault?(.beforeRollback)
                    guard swap(prepared, live) else { throw Failure.commitFailed }
                } catch {
                    retainRecovery = true
                    recordRecovery(in: work, previousStore: prepared, replacementStore: live)
                    NSLog("The Styk: restore rollback failed; prior store retained in a private recovery directory")
                    throw Failure.rollbackFailed(work)
                }
                do {
                    try fault?(.afterRollback)
                    try BackupFiles.syncDirectory(parent)
                    try BackupFiles.syncDirectory(work)
                } catch {
                    // A rollback rename succeeded, but its durability is uncertain.
                    // Retain both stores and report that uncertainty explicitly.
                    retainRecovery = true
                    recordRecovery(in: work, previousStore: live, replacementStore: prepared)
                    NSLog("The Styk: restore rollback durability failed; recovery directory retained")
                    throw Failure.rollbackFailed(work)
                }
                throw error
            }
            return count
        }
        // The defer can now delete the prior store. Cleanup cannot change commit success.
        if let serialize = serializeCommit { return try serialize(commit) }
        return try commit()
    }

    static func validateStore(_ root: URL, allowAncillaryFiles: Bool = false) throws -> Int {
        let fm = FileManager.default
        guard BackupFiles.isDirectory(root) else { throw Failure.invalidStore }
        if !allowAncillaryFiles {
            let allowed: Set<String> = ["index.json", "notes", "trash", "folders.json"]
            guard try fm.contentsOfDirectory(atPath: root.path).allSatisfy({ allowed.contains($0) }) else {
                throw Failure.invalidStore
            }
        }
        let bytes = try BackupFiles.read(root.appendingPathComponent("index.json"), maxBytes: 5 * 1024 * 1024)
        let index = try JSONDecoder().decode(IndexFile.self, from: bytes)
        let trash = index.trash ?? []
        guard index.version == 1, index.notes.count <= 10_000, trash.count <= 10_000 else { throw Failure.invalidStore }
        var ids = Set<UUID>()
        for entry in index.notes {
            guard ids.insert(entry.id).inserted, validFolder(entry.folder), validSnippet(entry.snippet),
                  entry.modified.timeIntervalSinceReferenceDate.isFinite else { throw Failure.invalidStore }
            let note = try readNote(entry.id, directory: root.appendingPathComponent("notes"))
            guard note.folder == entry.folder, note.style.color == entry.color,
                  snippet(note.text) == entry.snippet else { throw Failure.invalidStore }
        }
        for entry in trash {
            guard ids.insert(entry.id).inserted, validFolder(entry.folder), validSnippet(entry.snippet),
                  entry.deletedAt.timeIntervalSinceReferenceDate.isFinite else { throw Failure.invalidStore }
            let note = try readNote(entry.id, directory: root.appendingPathComponent("trash"))
            guard note.folder == entry.folder, note.style.color == entry.color,
                  snippet(note.text) == entry.snippet else { throw Failure.invalidStore }
        }
        try validateDirectory(root.appendingPathComponent("notes"), ids: Set(index.notes.map { $0.id }))
        try validateDirectory(root.appendingPathComponent("trash"), ids: Set(trash.map { $0.id }))
        let bookmarks = root.appendingPathComponent("folders.json")
        if fm.fileExists(atPath: bookmarks.path) {
            let map = try JSONDecoder().decode([String: String].self,
                from: BackupFiles.read(bookmarks, maxBytes: 5 * 1024 * 1024))
            guard map.count <= 10_000,
                  map.allSatisfy({ validFolder($0.key) && Data(base64Encoded: $0.value) != nil }) else {
                throw Failure.invalidStore
            }
        }
        return index.notes.count
    }

    private static func readNote(_ id: UUID, directory: URL) throws -> Note {
        let bytes = try BackupFiles.read(directory.appendingPathComponent(id.uuidString + ".json"), maxBytes: 2 * 1024 * 1024)
        let note = try JSONDecoder().decode(Note.self, from: bytes)
        guard note.id == id, validFolder(note.folder), note.text.count <= 200_000,
              note.style.fontSize.isFinite, (8...72).contains(note.style.fontSize),
              note.frame.x.isFinite, note.frame.y.isFinite,
              note.frame.w.isFinite, (120...4_000).contains(note.frame.w),
              note.frame.h.isFinite, (120...4_000).contains(note.frame.h),
              note.created.timeIntervalSinceReferenceDate.isFinite,
              note.modified.timeIntervalSinceReferenceDate.isFinite,
              note.anchor == nil || (note.anchor!.dx.isFinite && note.anchor!.dy.isFinite) else {
            throw Failure.invalidStore
        }
        return note
    }

    private static func validateDirectory(_ directory: URL, ids: Set<UUID>) throws {
        let fm = FileManager.default
        guard fm.fileExists(atPath: directory.path) else {
            guard ids.isEmpty else { throw Failure.invalidStore }
            return
        }
        guard BackupFiles.isDirectory(directory) else { throw Failure.invalidStore }
        let actual = Set(try fm.contentsOfDirectory(atPath: directory.path))
        guard actual == Set(ids.map { $0.uuidString + ".json" }) else { throw Failure.invalidStore }
    }

    private static func dataRoot(in extracted: URL) throws -> URL {
        let fm = FileManager.default
        if fm.fileExists(atPath: extracted.appendingPathComponent("index.json").path) { return extracted }
        let children = try fm.contentsOfDirectory(at: extracted, includingPropertiesForKeys: nil)
        guard children.count == 1, let child = children.first, BackupFiles.isDirectory(child),
              fm.fileExists(atPath: child.appendingPathComponent("index.json").path) else { throw Failure.invalidStore }
        return child
    }

    private static func validFolder(_ folder: String) -> Bool {
        folder == normalizePath(folder) && SafeFolderAccess.isValidStoredFolder(folder)
    }

    private static func validSnippet(_ value: String) -> Bool {
        !value.isEmpty && value.count <= 60 && value.unicodeScalars.allSatisfy {
            $0.properties.generalCategory != .control && $0.properties.generalCategory != .format
        }
    }

    private static func snippet(_ text: String) -> String {
        for line in text.components(separatedBy: .newlines) {
            let scalars = line.unicodeScalars.filter {
                $0.properties.generalCategory != .control && $0.properties.generalCategory != .format
            }
            let clean = String(String.UnicodeScalarView(scalars)).trimmingCharacters(in: .whitespaces)
            if !clean.isEmpty { return String(clean.prefix(60)) }
        }
        return "Nota vazia"
    }

    private static func secureAndSyncTree(_ root: URL) throws {
        let fm = FileManager.default
        var info = stat()
        guard lstat(root.path, &info) == 0, info.st_uid == getuid() else { throw Failure.invalidStore }
        switch info.st_mode & S_IFMT {
        case S_IFDIR:
            guard chmod(root.path, 0o700) == 0 else { throw BackupArchive.Failure.ioFailure }
            for child in try fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) {
                try secureAndSyncTree(child)
            }
            try BackupFiles.syncDirectory(root)
        case S_IFREG:
            let fd = open(root.path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
            guard fd >= 0 else { throw BackupArchive.Failure.ioFailure }
            defer { close(fd) }
            guard fchmod(fd, 0o600) == 0, fsync(fd) == 0 else { throw BackupArchive.Failure.ioFailure }
        default:
            throw Failure.invalidStore
        }
    }

    private static func treeBytes(_ root: URL) throws -> Int64 {
        var info = stat()
        guard lstat(root.path, &info) == 0, info.st_uid == getuid() else { throw Failure.invalidStore }
        switch info.st_mode & S_IFMT {
        case S_IFDIR:
            return try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
                .reduce(Int64(0)) { try $0 + treeBytes($1) }
        case S_IFREG:
            return info.st_size
        default:
            throw Failure.invalidStore
        }
    }

    private static func recordRecovery(in work: URL, previousStore: URL, replacementStore: URL) {
        struct Manifest: Encodable {
            let previousStore: String
            let replacementStore: String
            let requiresManualReview = true
        }
        // Failure to write this diagnostic must never remove the retained stores.
        if let data = try? JSONEncoder().encode(Manifest(previousStore: previousStore.path,
                                                        replacementStore: replacementStore.path)) {
            try? BackupFiles.writeNew(data, to: work.appendingPathComponent("recovery.json"))
        }
    }

    private static func swap(_ a: URL, _ b: URL) -> Bool {
        renameatx_np(AT_FDCWD, a.path, AT_FDCWD, b.path, UInt32(RENAME_SWAP)) == 0
    }
}
