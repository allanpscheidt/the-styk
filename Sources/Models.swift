import Foundation

enum NoteColor: String, Codable, CaseIterable { case yellow, pink, blue, green, orange, purple }
enum NoteFontID: String, Codable, CaseIterable { case system, rounded, serif, mono, hand }

struct NoteStyle: Codable {
    var color: NoteColor
    var fontID: NoteFontID
    var fontSize: Double
}

struct NoteFrame: Codable {
    var x: Double
    var y: Double
    var w: Double
    var h: Double
}

/// Offset da nota em relação ao canto superior-esquerdo da janela do Finder —
/// é o que faz a nota "grudar" na janela quando ela é movida ou troca de monitor.
struct NoteAnchor: Codable {
    var dx: Double            // distância horizontal do canto esquerdo da janela
    var dy: Double            // distância vertical do topo da janela (positivo para baixo)
}

struct Note: Codable {
    let id: UUID
    var folder: String        // caminho POSIX normalizado
    var text: String
    var style: NoteStyle
    var frame: NoteFrame      // coordenadas de tela (origem AppKit, bottom-left)
    var anchor: NoteAnchor? = nil   // nil em notas antigas — calculado no primeiro show
    let created: Date
    var modified: Date
}

struct IndexEntry: Codable {
    let id: UUID
    var folder: String
    var snippet: String       // 1ª linha não vazia, sem chars de controle, máx 60 chars
    var color: NoteColor
    var modified: Date
    /// true quando a pasta original foi apagada — a nota vive na seção "Notas órfãs".
    /// Optional para compatibilidade com índices antigos (nil == false).
    var orphaned: Bool? = nil
}

/// Nota na Lixeira do app (o JSON completo fica em trash/<id>.json por 5 dias).
struct TrashEntry: Codable {
    let id: UUID
    var folder: String        // pasta original, para restaurar
    var snippet: String
    var color: NoteColor
    var deletedAt: Date
}

/// Normaliza caminho POSIX: standardizingPath + remove "/" final (exceto raiz).
func normalizePath(_ p: String) -> String {
    var s = (p as NSString).standardizingPath
    while s.count > 1 && s.hasSuffix("/") { s.removeLast() }
    return s
}
