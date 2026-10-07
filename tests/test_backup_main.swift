import Foundation
import Darwin
import zlib

// Service-level tests do not create AppKit windows. The real manager is exercised
// by the application; this seam records that the service closes it at commit.
final class NoteWindowManager {
    static let shared = NoteWindowManager()
    private(set) var prepareCount = 0
    func prepareForRestore() { prepareCount += 1 }
}

let fm = FileManager.default
guard let testPath = ProcessInfo.processInfo.environment["THESTYK_TEST_ROOT"],
      let livePath = ProcessInfo.processInfo.environment["THESTYK_DATA_DIR"],
      testPath.contains("thestyk-backup-tests-") else { fatalError("isolated test root required") }
let root = URL(fileURLWithPath: testPath, isDirectory: true)
let live = URL(fileURLWithPath: livePath, isDirectory: true)
let folder = root.appendingPathComponent("Folder", isDirectory: true)
try fm.createDirectory(at: folder, withIntermediateDirectories: true)
let activeID = UUID()
let trashID = UUID()
let date = Date()
let active = Note(id: activeID, folder: folder.path, text: "restored active",
                  style: NoteStyle(color: .yellow, fontID: .system, fontSize: 14),
                  frame: NoteFrame(x: 0, y: 0, w: 260, h: 240), created: date, modified: date)
let trashed = Note(id: trashID, folder: folder.path, text: "restored trash",
                   style: NoteStyle(color: .green, fontID: .system, fontSize: 14),
                   frame: NoteFrame(x: 0, y: 0, w: 260, h: 240), created: date, modified: date)
let encoder = JSONEncoder()
func indexData(notes: [IndexEntry], trash: [TrashEntry] = []) throws -> Data {
    struct Index: Encodable { let version = 1; let notes: [IndexEntry]; let trash: [TrashEntry] }
    return try encoder.encode(Index(notes: notes, trash: trash))
}
let entry = IndexEntry(id: activeID, folder: folder.path, snippet: active.text, color: .yellow, modified: date)
let trashEntry = TrashEntry(id: trashID, folder: folder.path, snippet: trashed.text, color: .green, deletedAt: date)
let goodIndex = try indexData(notes: [entry], trash: [trashEntry])

extension Data {
    mutating func u16(_ value: UInt16) { append(UInt8(value & 255)); append(UInt8(value >> 8)) }
    mutating func u32(_ value: UInt32) { u16(UInt16(value & 65_535)); u16(UInt16(value >> 16)) }
}
struct Member {
    var path: String
    var bytes: Data
    var method: UInt16 = 0
    var expandedOverride: Int? = nil
    var crcOverride: UInt32? = nil
    var mode: UInt32 = 0o100600
    var flags: UInt16 = 0
}
func rawDeflate(_ data: Data) throws -> Data {
    var stream = z_stream()
    assert(deflateInit2_(&stream, Z_DEFAULT_COMPRESSION, Z_DEFLATED, -MAX_WBITS, 8,
                        Z_DEFAULT_STRATEGY, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size)) == Z_OK)
    defer { deflateEnd(&stream) }
    let capacity = Int(compressBound(uLong(data.count))) + 64
    var output = [UInt8](repeating: 0, count: capacity)
    let status = data.withUnsafeBytes { input in
        stream.next_in = UnsafeMutablePointer<Bytef>(mutating: input.bindMemory(to: Bytef.self).baseAddress)
        stream.avail_in = uInt(data.count)
        return output.withUnsafeMutableBytes { buffer -> Int32 in
            stream.next_out = buffer.bindMemory(to: Bytef.self).baseAddress
            stream.avail_out = uInt(capacity)
            return deflate(&stream, Z_FINISH)
        }
    }
    assert(status == Z_STREAM_END)
    return Data(output.prefix(capacity - Int(stream.avail_out)))
}
func zip(_ members: [Member], name: String) throws -> URL {
    var bytes = Data()
    var central = Data()
    for member in members {
        let filename = Data(member.path.utf8)
        let payload = member.method == 8 ? try rawDeflate(member.bytes) : member.bytes
        let expanded = UInt32(member.expandedOverride ?? member.bytes.count)
        let checksum = member.crcOverride ?? member.bytes.withUnsafeBytes {
            UInt32(crc32(0, $0.bindMemory(to: Bytef.self).baseAddress, uInt(member.bytes.count)))
        }
        let offset = UInt32(bytes.count)
        bytes.u32(0x04034b50); bytes.u16(20); bytes.u16(member.flags); bytes.u16(member.method)
        bytes.u16(0); bytes.u16(0); bytes.u32(checksum); bytes.u32(UInt32(payload.count)); bytes.u32(expanded)
        bytes.u16(UInt16(filename.count)); bytes.u16(0); bytes.append(filename); bytes.append(payload)
        central.u32(0x02014b50); central.u16(0x0314); central.u16(20)
        central.u16(member.flags); central.u16(member.method); central.u16(0); central.u16(0)
        central.u32(checksum); central.u32(UInt32(payload.count)); central.u32(expanded)
        central.u16(UInt16(filename.count)); central.u16(0); central.u16(0); central.u16(0); central.u16(0)
        central.u32(member.mode << 16); central.u32(offset); central.append(filename)
    }
    let start = UInt32(bytes.count)
    bytes.append(central)
    bytes.u32(0x06054b50); bytes.u16(0); bytes.u16(0); bytes.u16(UInt16(members.count)); bytes.u16(UInt16(members.count))
    bytes.u32(UInt32(central.count)); bytes.u32(start); bytes.u16(0)
    let target = root.appendingPathComponent(name + ".zip")
    try bytes.write(to: target)
    return target
}
func members(_ index: Data = goodIndex) throws -> [Member] {
    [Member(path: "The Styk/index.json", bytes: index, method: 8),
     Member(path: "The Styk/notes/" + activeID.uuidString + ".json", bytes: try encoder.encode(active), method: 8),
     Member(path: "The Styk/trash/" + trashID.uuidString + ".json", bytes: try encoder.encode(trashed), method: 8),
     Member(path: "The Styk/folders.json", bytes: Data("{}".utf8))]
}
func snapshot(_ directory: URL) throws -> [String: Data] {
    var result: [String: Data] = [:]
    guard let enumerator = fm.enumerator(at: directory, includingPropertiesForKeys: [.isRegularFileKey]) else {
        fatalError("enumerator unavailable")
    }
    for case let file as URL in enumerator {
        if try file.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true {
            result[String(file.path.dropFirst(directory.path.count))] = try Data(contentsOf: file)
        }
    }
    return result
}
try fm.createDirectory(at: live.appendingPathComponent("notes"), withIntermediateDirectories: true)
try fm.createDirectory(at: live.appendingPathComponent("trash"), withIntermediateDirectories: true)
try fm.createDirectory(at: live.appendingPathComponent("Backups"), withIntermediateDirectories: true)
var oldNote = active
oldNote.text = "original live note"
try encoder.encode(oldNote).write(to: live.appendingPathComponent("notes/" + activeID.uuidString + ".json"))
var oldEntry = entry
oldEntry.snippet = oldNote.text
try indexData(notes: [oldEntry]).write(to: live.appendingPathComponent("index.json"))
try Data("{}".utf8).write(to: live.appendingPathComponent("folders.json"))
try Data("keep backup".utf8).write(to: live.appendingPathComponent("Backups/keep.zip"))
try Data("keep settings".utf8).write(to: live.appendingPathComponent("settings.txt"))
let original = try snapshot(live)
var tests = 0
func reject(_ archive: URL, limits: BackupArchive.Limits = .init(),
            fault: ((BackupRestoreTransaction.CommitStep) throws -> Void)? = nil) throws {
    var rejected = false
    do { _ = try BackupRestoreTransaction.restore(archive, to: live, limits: limits, fault: fault) }
    catch { rejected = true }
    assert(rejected, "unsafe backup accepted: \(archive.lastPathComponent)")
    let after = try snapshot(live)
    let children = try fm.contentsOfDirectory(atPath: root.path)
    assert(after == original, "failure changed live notes: \(archive.lastPathComponent)")
    assert(children.allSatisfy { !$0.hasPrefix(".TheStyk-restore-") },
           "partial restore remained")
    tests += 1
}

// Semantic corruption, missing and mismatched references must leave every live byte intact.
try reject(zip(try members(Data("{broken".utf8)), name: "malformed-index"))
try reject(zip([try members()[0]], name: "missing-notes"))
var malformedNote = try members(); malformedNote[1].bytes = Data("{}".utf8)
try reject(zip(malformedNote, name: "malformed-note"))
var wrongID = active; wrongID = Note(id: UUID(), folder: active.folder, text: active.text,
                                  style: active.style, frame: active.frame, created: date, modified: date)
var wrongReference = try members(); wrongReference[1].bytes = try encoder.encode(wrongID)
try reject(zip(wrongReference, name: "mismatched-note-id"))
try reject(zip(try members(indexData(notes: [entry, entry], trash: [trashEntry])), name: "duplicate-index-id"))
var extra = try members(); extra.append(Member(path: "The Styk/notes/" + UUID().uuidString + ".json", bytes: Data("{}".utf8)))
try reject(zip(extra, name: "unreferenced-note"))
var missingTrash = try members(); missingTrash.remove(at: 2)
try reject(zip(missingTrash, name: "legacy-missing-trash"))
let executable = root.appendingPathComponent("Payload.app", isDirectory: true)
try fm.createDirectory(at: executable, withIntermediateDirectories: false)
var executableEntry = entry; executableEntry.folder = executable.path
var executableNote = active; executableNote.folder = executable.path
var executableMembers = try members(indexData(notes: [executableEntry], trash: [trashEntry]))
executableMembers[1].bytes = try encoder.encode(executableNote)
try reject(zip(executableMembers, name: "application-folder"))

// Preflight limits and type/path checks happen before extraction can consume resources.
try reject(zip([Member(path: "../escape", bytes: Data("bad".utf8))], name: "path-traversal"))
try reject(zip([Member(path: "a/b/c/d", bytes: Data("bad".utf8))], name: "deep-path"))
try reject(zip([Member(path: "The Styk/index.json", bytes: Data("target".utf8), mode: 0o120777)], name: "symlink"))
let compressedBomb = Member(path: "index.json", bytes: Data(repeating: 65, count: 100_000), method: 8)
try reject(zip([compressedBomb], name: "compression-ratio"))
var oversized = try members(); oversized[0].expandedOverride = 6 * 1024 * 1024
try reject(zip(oversized, name: "oversized-metadata"))
var duplicate = try members(); duplicate.append(duplicate[0])
try reject(zip(duplicate, name: "duplicate-member"))
var countLimits = BackupArchive.Limits(); countLimits.entries = 2
let good = try zip(members(), name: "good")
try reject(good, limits: countLimits)
var totalLimits = BackupArchive.Limits(); totalLimits.totalBytes = 100
try reject(good, limits: totalLimits)
var archiveLimits = BackupArchive.Limits(); archiveLimits.archiveBytes = 100
try reject(good, limits: archiveLimits)
var timeoutLimits = BackupArchive.Limits(); timeoutLimits.seconds = -1
try reject(good, limits: timeoutLimits)

// Metadata can lie: streaming inflation must still stop at the declared quota.
var lying = try members(); lying[1].expandedOverride = 10
try reject(zip(lying, name: "inflation-exceeds-metadata"))
var crc = try members(); crc[1].crcOverride = 0
try reject(zip(crc, name: "crc-corruption"))
let fifo = root.appendingPathComponent("fifo.zip")
assert(mkfifo(fifo.path, 0o600) == 0)
try reject(fifo)

enum Injected: Error { case failure }
try reject(good, fault: { if $0 == .beforeSwap { throw Injected.failure } })
try reject(good, fault: { if $0 == .afterSwap { throw Injected.failure } })
try reject(good, fault: { if $0 == .afterDurability { throw Injected.failure } })

// A failed rollback cannot be reported as "unchanged". Both versions survive,
// with a private manifest that identifies their locations for manual recovery.
for rollbackStep in [BackupRestoreTransaction.CommitStep.beforeRollback, .afterRollback] {
    let recoveryLive = root.appendingPathComponent("recovery-live-" + UUID().uuidString, isDirectory: true)
    try fm.copyItem(at: live, to: recoveryLive)
    var recoveryDirectory: URL?
    do {
        _ = try BackupRestoreTransaction.restore(good, to: recoveryLive, fault: { step in
            if step == .afterSwap || step == rollbackStep { throw Injected.failure }
        })
    } catch {
        guard case BackupRestoreTransaction.Failure.rollbackFailed(let directory) = error else {
            fatalError("rollback error lost its recovery status: \(error)")
        }
        assert(BackupService.RestoreResult.fromFailure(error) == .recoveryRequired(directory))
        recoveryDirectory = directory
    }
    guard let recovery = recoveryDirectory else { fatalError("rollback failure unexpectedly succeeded") }
    assert(fm.fileExists(atPath: recovery.appendingPathComponent("recovery.json").path))
    var recoveryInfo = stat()
    assert(lstat(recovery.path, &recoveryInfo) == 0 && recoveryInfo.st_mode & 0o777 == 0o700)
    let priorLocation = rollbackStep == .beforeRollback ? recovery.appendingPathComponent("prepared") : recoveryLive
    let previousBytes = try snapshot(priorLocation)
    assert(previousBytes == original, "the prior store was lost after failed rollback")
    let newLocation = rollbackStep == .beforeRollback ? recoveryLive : recovery.appendingPathComponent("prepared")
    let replacementCount = try BackupRestoreTransaction.validateStore(newLocation, allowAncillaryFiles: true)
    assert(replacementCount == 1, "the replacement store was lost after failed rollback")
    tests += 1
}

let count = try BackupRestoreTransaction.restore(good, to: live)
assert(count == 1)
let validatedCount = try BackupRestoreTransaction.validateStore(live, allowAncillaryFiles: true)
let keptBackup = try Data(contentsOf: live.appendingPathComponent("Backups/keep.zip"))
let keptSettings = try Data(contentsOf: live.appendingPathComponent("settings.txt"))
assert(validatedCount == 1)
assert(keptBackup == Data("keep backup".utf8))
assert(keptSettings == Data("keep settings".utf8))
assert(fm.fileExists(atPath: live.appendingPathComponent("trash/" + trashID.uuidString + ".json").path))
var info = stat()
assert(lstat(live.path, &info) == 0 && info.st_mode & 0o777 == 0o700)
assert(lstat(live.appendingPathComponent("index.json").path, &info) == 0 && info.st_mode & 0o777 == 0o600)
tests += 1

// Exercise the actual ditto creation path and its complete store round trip.
let store = NoteStore.shared
store.reloadFromDisk()
let generated = root.appendingPathComponent("generated.zip")
assert(BackupService.makeBackup(to: generated), "the app generated a ZIP that its reader cannot restore")
assert(BackupService.restore(from: generated) == .restored(1))
assert(NoteWindowManager.shared.prepareCount == 1)
store.reloadFromDisk()
assert(store.loadNote(id: activeID)?.text == active.text && store.trash.count == 1)
tests += 1
// Outputs inside Backups use a private sibling, keeping rename sources stable
// across any live-store directory exchange. The completed destination restores.
let internalBackup = live.appendingPathComponent("Backups/internal.zip")
assert(BackupService.makeBackup(to: internalBackup))
assert(BackupService.restore(from: internalBackup) == .restored(1))
assert(NoteWindowManager.shared.prepareCount == 2)
tests += 1

// A highly repetitive, valid 200k-character note keeps the ZIP ratio policy by
// falling back to uncompressed creation, and preserves all of its text.
var repetitive = active
repetitive.text = String(repeating: "a", count: 200_000)
store.save(repetitive)
let repeatedBackup = root.appendingPathComponent("repeated.zip")
assert(BackupService.makeBackup(to: repeatedBackup))
assert(BackupService.restore(from: repeatedBackup) == .restored(1))
assert(store.loadNote(id: activeID)?.text == repetitive.text)
tests += 1

// Exercise the actual service boundary: a configured password requires a fresh
// proof even after unlock, and a proof cannot be reused for a second operation.
let beforeLocked = try snapshot(live)
assert(PasswordService.setPassword("backup-test-password"))
assert(!BackupService.makeBackup(to: root.appendingPathComponent("locked.zip")))
assert(BackupService.restore(from: good) == .unchanged)
let afterLocked = try snapshot(live)
assert(beforeLocked == afterLocked)
assert(PasswordService.unlock(withPassword: "backup-test-password"))
assert(!BackupService.makeBackup(to: root.appendingPathComponent("unproved.zip")))
assert(BackupService.restore(from: good) == .unchanged)
let restoreProof = PasswordService.authorize(withPassword: "backup-test-password", for: .restore)
assert(BackupService.restore(from: good, authorization: restoreProof) == .restored(1))
assert(BackupService.restore(from: good, authorization: restoreProof) == .unchanged)
let backupProof = PasswordService.authorize(withPassword: "backup-test-password", for: .backup)
assert(BackupService.makeBackup(to: root.appendingPathComponent("authorized.zip"), authorization: backupProof))
assert(!BackupService.makeBackup(to: root.appendingPathComponent("reused.zip"), authorization: backupProof))
tests += 1
print("BACKUP SECURITY: \(tests) isolated scenarios passed")
