import AppKit

let fm = FileManager.default
guard let suite = ProcessInfo.processInfo.environment["THESTYK_DEFAULTS_SUITE"],
      suite.hasPrefix("thestyk-test-access-"), let defaults = UserDefaults(suiteName: suite) else {
    fatalError("teste exige preferências isoladas")
}
defaults.removePersistentDomain(forName: suite)
defer { defaults.removePersistentDomain(forName: suite) }
guard let temporaryPath = ProcessInfo.processInfo.environment["THESTYK_EXPORT_TEMP_DIR"],
      temporaryPath.contains("thestyk-access-test") else { fatalError("teste exige diretório isolado") }
let root = URL(fileURLWithPath: temporaryPath, isDirectory: true).resolvingSymlinksInPath()
let ordinary = root.appendingPathComponent("pasta")
try fm.createDirectory(at: ordinary, withIntermediateDirectories: true)
assert(SafeFolderAccess.validatedURL(for: ordinary.path) != nil)
assert(SafeFolderAccess.isValidStoredFolder(root.appendingPathComponent("pasta-ausente").path))
assert(SafeFolderAccess.validatedURL(for: root.appendingPathComponent("pasta-ausente").path) == nil)
assert(!SafeFolderAccess.isValidStoredFolder("relative/path"))
assert(!SafeFolderAccess.isValidStoredFolder(ordinary.path + "/../pasta"))

let document = root.appendingPathComponent("documento.txt")
try Data("documento".utf8).write(to: document)
assert(SafeFolderAccess.validatedURL(for: document.path) == nil)
let application = root.appendingPathComponent("Aplicativo.app")
try fm.createDirectory(at: application, withIntermediateDirectories: true)
assert(SafeFolderAccess.validatedURL(for: application.path) == nil)
let link = root.appendingPathComponent("link")
try fm.createSymbolicLink(at: link, withDestinationURL: ordinary)
assert(SafeFolderAccess.validatedURL(for: link.path) == nil)
assert(!SafeFolderAccess.isValidStoredFolder(link.appendingPathComponent("ausente").path))

let file = try TemporaryExports.create(text: "texto confidencial", fileName: "nota.txt")
let exportedText = try String(contentsOf: file, encoding: .utf8)
assert(exportedText == "texto confidencial")
let parentMode = try fm.attributesOfItem(atPath: TemporaryExports.directory.path)[.posixPermissions] as! NSNumber
let fileMode = try fm.attributesOfItem(atPath: file.path)[.posixPermissions] as! NSNumber
assert(parentMode.intValue == 0o700)
assert(fileMode.intValue == 0o600)
TemporaryExports.remove(file.deletingLastPathComponent())
assert(!fm.fileExists(atPath: file.path))

// Simula saída antes do callback e relaunch imediatamente, sem esperar 24 h.
let leftover = try TemporaryExports.create(text: "sobra recente", fileName: "nota.txt")
let legacy = root.appendingPathComponent("TheStyk-" + UUID().uuidString)
try fm.createDirectory(at: legacy, withIntermediateDirectories: true)
try Data("export antigo".utf8).write(to: legacy.appendingPathComponent("nota.txt"))
let stage = root.appendingPathComponent("TheStyk-stage-" + UUID().uuidString)
try fm.createDirectory(at: stage, withIntermediateDirectories: true)
TemporaryExports.purgeLeftovers()
assert(!fm.fileExists(atPath: leftover.path))
assert(!fm.fileExists(atPath: legacy.path))
assert(fm.fileExists(atPath: stage.path))

// Um painel autorizado aberto perde o arquivo e sua sessão ao bloquear.
let pending = try TemporaryExports.create(text: "export pendente", fileName: "nota.txt")
let session = ExportPickerSession(fileURL: pending, anchorWindow: nil,
                                  tempDir: pending.deletingLastPathComponent())
session.retainUntilFinished()
assert(PasswordService.setPassword("secret"))
assert(PasswordService.isLocked)
assert(!fm.fileExists(atPath: pending.path), "export pendente sobreviveu ao bloqueio")
assert(PasswordService.unlock(withPassword: "secret"))
let idleFile = try TemporaryExports.create(text: "export ocioso", fileName: "nota.txt")
let idleSession = ExportPickerSession(fileURL: idleFile, anchorWindow: nil,
                                     tempDir: idleFile.deletingLastPathComponent())
idleSession.retainUntilFinished()
PasswordService.expireSessionIfNeeded(now: Date().addingTimeInterval(PasswordService.inactivityTimeout + 1))
assert(!fm.fileExists(atPath: idleFile.path), "export sobreviveu ao timeout da sessão")

// Um link no nome do diretório privado nunca é seguido.
try fm.removeItem(at: TemporaryExports.directory)
try fm.createSymbolicLink(at: TemporaryExports.directory, withDestinationURL: ordinary)
do {
    _ = try TemporaryExports.create(text: "não gravar", fileName: "nota.txt")
    fatalError("diretório symlink aceito")
} catch {}
assert(!fm.fileExists(atPath: ordinary.appendingPathComponent("nota.txt").path))
print("Pasta segura e limpeza de exports: testes passaram")
