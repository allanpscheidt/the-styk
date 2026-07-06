import Foundation

let fm = FileManager.default
guard let root = ProcessInfo.processInfo.environment["THESTYK_TEST_ROOT"] else {
    fatalError("defina THESTYK_TEST_ROOT")
}
precondition(NoteStore.shared.dataDirectory.path.contains("thestyk-test-home"),
             "store não está isolado — defina THESTYK_DATA_DIR!")
let folderA = root + "/PastaA"
let folderB = root + "/PastaB"
try! fm.createDirectory(atPath: folderA, withIntermediateDirectories: true)

let store = NoteStore.shared

// 1. cria
var n = store.createNote(inFolder: folderA, frame: NoteFrame(x: 0, y: 0, w: 260, h: 240))
n.text = "teste lixeira"
store.save(n)
assert(store.entries(inFolder: folderA).count == 1, "criação falhou")

// 2. lixeira
store.moveToTrash(id: n.id)
assert(store.entries(inFolder: folderA).isEmpty && store.trash.count == 1, "lixeira falhou")

// 3. restaura
store.restoreFromTrash(id: n.id)
assert(store.entries(inFolder: folderA).count == 1 && store.trash.isEmpty, "restauração falhou")
assert(store.loadNote(id: n.id)?.text == "teste lixeira", "texto perdido no ciclo lixeira")

// 4. migração: pasta movida
try! fm.moveItem(atPath: folderA, toPath: folderB)
store.reconcileAnchors()
assert(store.entries(inFolder: folderB).count == 1, "migração falhou")
assert(store.orphans().isEmpty, "migração marcou órfã indevidamente")
assert(store.loadNote(id: n.id)?.folder == normalizePath(folderB), "arquivo da nota não migrou")

// 5. órfã: pasta apagada
try! fm.removeItem(atPath: folderB)
store.reconcileAnchors()
assert(store.orphans().count == 1, "órfã falhou")

// 6. des-órfã: pasta recriada
try! fm.createDirectory(atPath: folderB, withIntermediateDirectories: true)
store.reconcileAnchors()
assert(store.orphans().isEmpty, "des-órfã falhou")

// 7. reanexa a outra pasta
let folderC = root + "/PastaC"
try! fm.createDirectory(atPath: folderC, withIntermediateDirectories: true)
store.reattach(id: n.id, toFolder: folderC)
assert(store.entries(inFolder: folderC).count == 1, "reanexar falhou")

// 8. apagar definitivo
store.moveToTrash(id: n.id)
store.deletePermanently(id: n.id)
assert(store.trash.isEmpty && store.index.isEmpty, "apagar definitivo falhou")

// 9. persistência: recarrega do disco
store.reloadFromDisk()
assert(store.trash.isEmpty && store.index.isEmpty, "estado sujo após reload")

print("TODOS OS TESTES PASSARAM ✓")
