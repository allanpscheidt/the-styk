import AppKit
import Darwin

/// Única fronteira para abrir caminhos persistidos. Links e aliases não dão
/// acesso indireto a documentos ou aplicativos.
enum SafeFolderAccess {
    static func validatedURL(for path: String) -> URL? {
        guard isValidStoredFolder(path),
              let values = try? URL(fileURLWithPath: path).resourceValues(
                forKeys: [.isDirectoryKey, .isPackageKey]),
              values.isDirectory == true, values.isPackage != true else { return nil }
        return URL(fileURLWithPath: path, isDirectory: true).standardizedFileURL
    }

    /// Pastas ausentes continuam válidas como âncoras de notas órfãs.
    /// Todo componente existente deve ser um diretório comum.
    static func isValidStoredFolder(_ path: String) -> Bool {
        guard path.hasPrefix("/"), !path.contains("\0"),
              path.utf8.count <= 4096, normalizePath(path) == path else { return false }
        var cursor = URL(fileURLWithPath: "/", isDirectory: true)
        for component in path.split(separator: "/") {
            cursor.appendPathComponent(String(component), isDirectory: true)
            var info = stat()
            if lstat(cursor.path, &info) != 0 {
                return errno == ENOENT
            }
            guard (info.st_mode & S_IFMT) == S_IFDIR,
                  let values = try? cursor.resourceValues(
                    forKeys: [.isAliasFileKey, .isPackageKey]),
                  values.isAliasFile != true, values.isPackage != true else { return false }
        }
        return true
    }

    @discardableResult
    static func open(_ path: String) -> Bool {
        guard PasswordService.canAccessNotes,
              let url = validatedURL(for: path) else { return false }
        // Validação acontece no clique, junto da chamada ao Workspace.
        return NSWorkspace.shared.open(url)
    }
}
