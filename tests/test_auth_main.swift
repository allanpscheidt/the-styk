import Foundation

guard let suite = ProcessInfo.processInfo.environment["THESTYK_DEFAULTS_SUITE"], suite.hasPrefix("thestyk-test-auth-"),
      let defaults = UserDefaults(suiteName: suite),
      let root = ProcessInfo.processInfo.environment["THESTYK_TEST_ROOT"], root.contains("thestyk-auth-test") else {
    fatalError("authentication tests must use isolated storage and preferences")
}
let store = NoteStore.shared
precondition(store.dataDirectory.path.hasPrefix(root))
let fm = FileManager.default
let folder = root + "/Folder"
try! fm.createDirectory(atPath: folder, withIntermediateDirectories: true)

if CommandLine.arguments.last == "relaunch" {
    defer { defaults.removePersistentDomain(forName: suite) }
    // The previous process was authenticated and left the old durable flag false.
    assert(PasswordService.hasPassword && PasswordService.isLocked)
    assert(store.index.isEmpty && store.trash.isEmpty && store.folders().isEmpty)
    PasswordService.beginSession()
    assert(defaults.object(forKey: "thestyk.isLocked") == nil)
    assert(PasswordService.isLocked)
    assert(PasswordService.unlock(withPassword: "secret"))
    assert(store.index.count == 1, "unlock reloads the protected index in a new process")
    assert(store.loadNote(id: store.index[0].id)?.text == "private content")
    PasswordService.lock()
    print("AUTH RELAUNCH TESTS PASSED")
} else {
    defaults.removePersistentDomain(forName: suite)
    PasswordService.beginSession()
    assert(PasswordService.canAccessNotes)
    var note = store.createNote(inFolder: folder, frame: NoteFrame(x: 0, y: 0, w: 260, h: 240))!
    note.text = "private content"
    store.save(note)
    let indexURL = store.dataDirectory.appendingPathComponent("index.json")
    let noteURL = store.dataDirectory.appendingPathComponent("notes").appendingPathComponent(note.id.uuidString + ".json")
    let originalIndex = try! Data(contentsOf: indexURL)
    let originalNote = try! Data(contentsOf: noteURL)

    assert(PasswordService.setPassword("secret"))
    assert(PasswordService.isLocked)
    assert(store.index.isEmpty && store.trash.isEmpty && store.folders().isEmpty)
    assert(store.entries(inFolder: folder).isEmpty && store.orphans().isEmpty)
    assert(store.loadNote(id: note.id) == nil)
    assert(store.createNote(inFolder: folder, frame: note.frame) == nil)
    note.text = "blocked write"
    store.save(note)
    store.moveToTrash(id: note.id)
    store.restoreFromTrash(id: note.id)
    store.deletePermanently(id: note.id)
    store.emptyTrash()
    store.reattach(id: note.id, toFolder: root)
    store.reconcileAnchors()
    store.reloadFromDisk()
    assert(try! Data(contentsOf: indexURL) == originalIndex)
    assert(try! Data(contentsOf: noteURL) == originalNote)
    assert(!PasswordService.setPassword(""), "password removal requires fresh credentials")
    assert(!PasswordService.unlock(withPassword: "wrong"))
    assert(PasswordService.unlock(withPassword: "secret"))
    assert(store.loadNote(id: note.id)?.text == "private content")

    // Unlocking a session does not authorize any bulk/destructive operation.
    store.moveToTrash(id: note.id)
    assert(store.index.count == 1)
    assert(!PasswordService.consumeAuthorization(nil, for: .backup))
    assert(!PasswordService.consumeAuthorization(nil, for: .restore))
    assert(!PasswordService.consumeAuthorization(nil, for: .export))
    let export = PasswordService.authorize(withPassword: "secret", for: .export)!
    assert(!PasswordService.consumeAuthorization(export, for: .backup))
    assert(!PasswordService.consumeAuthorization(export, for: .export), "wrong scope consumes the proof")
    let once = PasswordService.authorize(withPassword: "secret", for: .export)!
    assert(PasswordService.consumeAuthorization(once, for: .export))
    assert(!PasswordService.consumeAuthorization(once, for: .export))
    let revoked = PasswordService.authorize(withPassword: "secret", for: .backup)!
    PasswordService.lock()
    assert(!PasswordService.consumeAuthorization(revoked, for: .backup))
    assert(PasswordService.unlock(withPassword: "secret"))
    assert(!PasswordService.consumeAuthorization(revoked, for: .backup))

    let trash = PasswordService.authorize(withPassword: "secret", for: .moveToTrash)!
    store.moveToTrash(id: note.id, authorization: trash)
    assert(store.index.isEmpty && store.trash.count == 1)
    store.restoreFromTrash(id: note.id)
    assert(store.trash.count == 1)
    let restore = PasswordService.authorize(withPassword: "secret", for: .restoreFromTrash)!
    store.restoreFromTrash(id: note.id, authorization: restore)
    assert(store.index.count == 1 && store.trash.isEmpty)

    PasswordService.expireSessionIfNeeded(now: Date().addingTimeInterval(PasswordService.inactivityTimeout + 1))
    assert(PasswordService.isLocked)
    assert(PasswordService.unlock(withPassword: "secret"))
    defaults.set(false, forKey: "thestyk.isLocked")
    defaults.synchronize()
    assert(PasswordService.canAccessNotes)
    print("AUTH STORE AND CAPABILITY TESTS PASSED")
}
