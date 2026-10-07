import Foundation
import Darwin

/// Arquivos de compartilhamento pertencem a um diretório privado do app.
/// A limpeza de inicialização não depende da idade dos arquivos.
enum TemporaryExports {
    private static var temporaryRoot: URL {
        // Mesmo isolamento usado pelo store: só o ambiente do próprio processo controla o teste.
        let path = ProcessInfo.processInfo.environment["THESTYK_EXPORT_TEMP_DIR"] ?? NSTemporaryDirectory()
        return URL(fileURLWithPath: path, isDirectory: true)
    }

    static var directory: URL {
        temporaryRoot
            .appendingPathComponent("TheStyk-Exports", isDirectory: true)
    }

    private static func ownedDirectory(_ url: URL) -> Bool {
        var info = stat()
        return lstat(url.path, &info) == 0 && info.st_uid == getuid()
            && (info.st_mode & S_IFMT) == S_IFDIR
    }

    private static func prepareDirectory() throws {
        let dir = directory
        if mkdir(dir.path, 0o700) != 0 && errno != EEXIST {
            throw CocoaError(.fileWriteNoPermission)
        }
        guard ownedDirectory(dir), chmod(dir.path, 0o700) == 0 else {
            throw CocoaError(.fileWriteNoPermission)
        }
    }

    static func create(text: String, fileName: String) throws -> URL {
        try prepareDirectory()
        let session = directory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        guard mkdir(session.path, 0o700) == 0 else { throw CocoaError(.fileWriteNoPermission) }
        let file = session.appendingPathComponent(fileName)
        let descriptor = Darwin.open(file.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, 0o600)
        guard descriptor >= 0 else {
            remove(session)
            throw CocoaError(.fileWriteNoPermission)
        }
        defer { Darwin.close(descriptor) }
        do {
            try Data(text.utf8).withUnsafeBytes { buffer in
                var offset = 0
                while offset < buffer.count {
                    let count = Darwin.write(descriptor, buffer.baseAddress!.advanced(by: offset), buffer.count - offset)
                    if count < 0 && errno == EINTR { continue }
                    guard count > 0 else { throw CocoaError(.fileWriteUnknown) }
                    offset += count
                }
            }
            guard fsync(descriptor) == 0 else { throw CocoaError(.fileWriteUnknown) }
            return file
        } catch {
            remove(session)
            throw error
        }
    }

    static func remove(_ session: URL) {
        guard session.deletingLastPathComponent().standardizedFileURL == directory.standardizedFileURL,
              UUID(uuidString: session.lastPathComponent) != nil,
              ownedDirectory(session) else { return }
        try? FileManager.default.removeItem(at: session)
    }

    static func purgeLeftovers() {
        guard (try? prepareDirectory()) != nil else { return }
        let fm = FileManager.default
        for session in (try? fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? [] {
            remove(session)
        }
        // Migra as cópias da versão anterior, sem atingir staging de backups.
        let temporary = directory.deletingLastPathComponent()
        for item in (try? fm.contentsOfDirectory(at: temporary, includingPropertiesForKeys: nil)) ?? [] {
            let name = item.lastPathComponent
            guard name.hasPrefix("TheStyk-"), UUID(uuidString: String(name.dropFirst(8))) != nil,
                  ownedDirectory(item) else { continue }
            try? fm.removeItem(at: item)
        }
    }
}
