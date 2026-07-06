# The Styk — Arquitetura e Contrato de Módulos

Post-its digitais ancorados a pastas do Finder. A nota flutua na tela **somente enquanto
o usuário está dentro da pasta onde ela foi criada** (janela frontal do Finder). Ao sair
da pasta, a nota some — mas continua ancorada e reaparece quando ele volta.

## Decisões fixas (não renegociar)

- **App de barra de menus** (`LSUIElement = true`), sem ícone no Dock. Nome: **The Styk**. Bundle ID: `br.com.allanpscheidt.thestyk`.
- **AppKit puro, programático.** Sem SwiftUI, sem Combine, sem async/await, sem pacotes externos, sem storyboard/xib. GCD + Timer + NotificationCenter.
- **Target:** `arm64-apple-macos11.0` (todas as versões de macOS com Apple Silicon). Compilado com SDK 26.x. `-swift-version 5`.
- **Efeito de vidro:** `if #available(macOS 26.0, *)` → `NSGlassEffectView` (com `tintColor` da cor da nota, `cornerRadius: 12`); senão → `NSVisualEffectView` (material `.hudWindow`, `state: .active`) + camada de cor por cima. O SDK local tem o símbolo — o probe compilou.
- **Leveza é requisito:** índice minúsculo carregado no boot; JSON completo da nota só é lido quando o usuário entra na pasta. Polling do Finder **apenas** enquanto o Finder está frontal. Painéis são destruídos (não escondidos) ao sair da pasta. Meta: ~0% CPU ocioso, <30 MB RAM.
- **Detecção de pasta:** Apple Events para o Finder via `NSAppleScript` **com script constante** (nunca interpolar nada), executado na main thread, timer de 0,8 s **só com Finder ativo**. Requer `NSAppleEventsUsageDescription` no Info.plist.
- **Um módulo só:** todos os .swift em `Sources/`, compilados juntos (mesmo módulo → sem `import` entre arquivos; visibilidade `internal` basta). `import AppKit` no topo de cada arquivo.
- **UI em pt-BR.** Código e identificadores em inglês.
- **Segurança:** texto plano sempre (nota, export, menu). Nada de NSKeyedUnarchiver, nada de interpolação em AppleScript, nada de execução/interpretação de conteúdo de nota. Validação estrita no load (limites abaixo).
- Código enxuto: zero abstração especulativa, zero feature não pedida. Sem force-unwrap fora de invariante óbvia. Sem `print` (pode `NSLog` em erro real).

## Layout do projeto

```
The Styk/
  ARCHITECTURE.md
  Sources/
    Models.swift              ← Agente Backend
    NoteStore.swift           ← Agente Backend
    Theme.swift               ← Agente UI
    NoteWindowController.swift← Agente UI
    FinderObserver.swift      ← Agente Sistema
    NoteWindowManager.swift   ← Agente Sistema
    AppDelegate.swift         ← Agente Sistema
    main.swift                ← Agente Sistema
    StatusMenuController.swift← Agente Menu
    ExportService.swift       ← Agente Menu
```

Cada agente escreve SOMENTE os próprios arquivos. As assinaturas abaixo são contrato:
implemente exatamente estas (pode adicionar membros `private`).

## Dados em disco

`~/Library/Application Support/The Styk/`
- `index.json` — `{"version":1,"notes":[IndexEntry...]}` (única coisa lida no boot)
- `notes/<UUID>.json` — nota completa (`Note`)

Escrita sempre atômica (`.atomic`). IDs são UUIDs gerados pelo app — nome de arquivo
nunca deriva de conteúdo do usuário.

## Contrato — Backend (`Models.swift`, `NoteStore.swift`)

```swift
enum NoteColor: String, Codable, CaseIterable { case yellow, pink, blue, green, orange, purple }
enum NoteFontID: String, Codable, CaseIterable { case system, rounded, serif, mono, hand }

struct NoteStyle: Codable { var color: NoteColor; var fontID: NoteFontID; var fontSize: Double }
struct NoteFrame: Codable { var x: Double; var y: Double; var w: Double; var h: Double }

struct Note: Codable {
    let id: UUID
    var folder: String        // caminho POSIX normalizado
    var text: String
    var style: NoteStyle
    var frame: NoteFrame      // coordenadas de tela (origem AppKit, bottom-left)
    let created: Date
    var modified: Date
}

struct IndexEntry: Codable {
    let id: UUID
    var folder: String
    var snippet: String       // 1ª linha não vazia, sem chars de controle, máx 60 chars
    var color: NoteColor
    var modified: Date
}

/// Normaliza caminho POSIX: `(p as NSString).standardizingPath`, remove "/" final (exceto raiz).
func normalizePath(_ p: String) -> String
```

```swift
final class NoteStore {
    static let shared = NoteStore()
    static let indexDidChange = Notification.Name("thestyk.indexDidChange")

    private(set) var index: [IndexEntry]          // carregado no init (só o índice!)

    func entries(inFolder folder: String) -> [IndexEntry]   // compara caminhos normalizados
    func folders() -> [String]                    // únicos, ordenados
    func loadNote(id: UUID) -> Note?              // lazy: lê notes/<id>.json + valida
    func createNote(inFolder folder: String, frame: NoteFrame) -> Note
        // estilo padrão: yellow / system / 14. Salva arquivo + índice, posta indexDidChange.
    func save(_ note: Note)                       // atualiza modified, snippet, arquivo, índice; posta indexDidChange

    // Lixeira (trash/<id>.json, retenção de 5 dias; purge no boot):
    private(set) var trash: [TrashEntry]
    func moveToTrash(id: UUID)                    // apagar = mover p/ lixeira (sem alerta: reversível)
    func restoreFromTrash(id: UUID)               // pasta original sumiu → volta como órfã
    func deletePermanently(id: UUID)
    func emptyTrash()

    // Âncoras (folders.json guarda bookmark base64 por pasta):
    func orphans() -> [IndexEntry]                // entries com orphaned == true
    func reattach(id: UUID, toFolder: String)
    func reconcileAnchors()                       // movida→migra · apagada→órfã · recriada→des-órfã
    func reconcileAnchorsIfStale()                // idem, com throttle de 30 s (chamada no onChange do Finder)
}
```

Pasta no Lixo do Finder (`/.Trash`) conta como apagada, não movida. Testes
funcionais do ciclo completo: `tests/run_tests.sh` (armazenamento isolado via
env `THESTYK_DATA_DIR`).

```swift
```

**Validação obrigatória no load (guardrails):**
- Recusar arquivo de nota > 2 MB; `index.json` > 5 MB; máx 10.000 entradas (excedente ignorado).
- `text` truncado em 200.000 chars; `fontSize` clamp 8–72; `frame.w/h` clamp 120–4.000.
- `folder` precisa ser caminho absoluto (`hasPrefix("/")`); entrada inválida é descartada em silêncio (índice) ou retorna nil (nota).
- Decodificação só com `JSONDecoder`/`Codable` estrito. Erro de decode ⇒ descarta, nunca crasha.
- Snippet: remover `\n` e chars de controle (`unicodeScalars` com `properties.generalCategory` de controle → fora), máx 60 chars, fallback `"Nota vazia"`.
- Notificações postadas na main thread.

## Contrato — UI (`Theme.swift`, `NoteWindowController.swift`)

```swift
enum Theme {
    static func nsColor(_ c: NoteColor) -> NSColor      // pastel post-it, ver tabela
    static func font(_ s: NoteStyle) -> NSFont          // via NSFontDescriptor.SystemDesign quando der
    static func label(_ c: NoteColor) -> String         // "Amarelo", "Rosa", ...
}
```

Cores (base): yellow `#FFE066`, pink `#FFB3C7`, blue `#9AD1FF`, green `#B5E8A0`,
orange `#FFC97A`, purple `#D9BBFF`. Texto sempre escuro (`#1C1C1E`) — papel pastel.
Fontes: system = SF; rounded/serif/mono = `NSFontDescriptor.withDesign(.rounded/.serif/.monospaced)`;
hand = `NSFont(name: "Noteworthy", ...)` → fallback `"Marker Felt"` → system.

```swift
final class NoteWindowController: NSWindowController, NSWindowDelegate, NSTextViewDelegate {
    let noteID: UUID
    init(note: Note)
    func flushPendingSave()   // grava já qualquer texto/frame pendente via NoteStore.shared.save
    // close() também chama flushPendingSave()
}
```

**Comportamento do painel:**
- `NSPanel` com `[.titled, .fullSizeContentView, .nonactivatingPanel, .resizable]`,
  `titleVisibility = .hidden`, `titlebarAppearsTransparent = true`, botões padrão escondidos,
  `backgroundColor = .clear`, `isOpaque = false`, `hasShadow = true`,
  `level = .floating`, `hidesOnDeactivate = false`, `isFloatingPanel = true`,
  `becomesKeyOnlyIfNeeded = true`, `isMovableByWindowBackground = true`,
  `collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]`,
  `minSize = 160×140`. Cantos arredondados 12 pt (o vidro/camada cuida disso).
- Redimensionável pelo mouse nas bordas (vem de graça com `.titled + .resizable`).
- Se o frame salvo estiver fora de qualquer tela, reposicionar dentro de `NSScreen.main.visibleFrame`.
- **Editor:** `NSTextView` em `NSScrollView` sem borda, `isRichText = false`,
  `importsGraphics = false`, `allowsImageEditing = false`,
  `isAutomaticLinkDetectionEnabled = false`, `isAutomaticDataDetectionEnabled = false`,
  demais "isAutomatic*" desligados exceto quote/dash livres, `allowsUndo = true`,
  `drawsBackground = false`, insets confortáveis (~10 pt, topo 30 pt p/ barra).
- **Barra de ferramentas no hover** (NSTrackingArea; alpha animado 0→1, ~28 pt no topo):
  6 bolinhas de cor (clicável, muda `style.color` + tint ao vivo) · `A−`/`A+` (fontSize ±2,
  clamp 8–72) · botão "Aa" (cicla NoteFontID) · share (`square.and.arrow.up`, chama
  `ExportService.share(note:relativeTo:)` com a nota atual) · lixeira (`trash`) →
  `NSAlert` "Apagar esta nota?" (destrutivo, "Apagar"/"Cancelar") → `NoteStore.shared.delete(id:)`.
- **Persistência:** textDidChange → debounce 1,5 s → save; `windowDidMove`/`windowDidEndLiveResize`
  → save frame (sem debounce agressivo, pode 0,5 s). Tudo via `NoteStore.shared.save`.
- Fundo: função privada que devolve a view de vidro (26+) ou visual-effect+cor (fallback),
  com o tint da cor da nota (alpha ~0.55 sobre o vidro; no fallback, cor com alpha ~0.85).

## Contrato — Sistema (`FinderObserver.swift`, `NoteWindowManager.swift`, `AppDelegate.swift`, `main.swift`)

```swift
final class FinderObserver {
    /// (pasta normalizada, bounds da janela frontal em coords AppKit) — ou nils.
    var onChange: ((String?, NSRect?) -> Void)?
    private(set) var currentFolder: String?
    private(set) var currentBounds: NSRect?
    func start()
}
```

O script devolve `"l,t,r,b" + linefeed + caminho` (bounds primeiro — nome de pasta
pode conter \n). Finder usa origem topo-esquerdo/y-para-baixo; converter para AppKit
com a altura da tela primária. **Ancoragem:** cada nota guarda `anchor` (dx, dy do
canto superior-esquerdo da janela); quando os bounds mudam (janela movida,
redimensionada ou em outro monitor), o manager reposiciona os painéis pela âncora —
a nota "gruda" na janela. Arrasto manual da nota recalcula a âncora.

- `NSWorkspace.shared.notificationCenter` → `didActivateApplicationNotification`:
  - ativado == Finder (`com.apple.finder`) → poll imediato + timer 0,8 s (RunLoop `.common`).
  - ativado == nós mesmos → **pausa o timer mas mantém `currentFolder`** (não dispara nil) —
    isso mantém as notas visíveis durante alertas/painel de share/menu.
  - qualquer outro app → pausa timer, `currentFolder = nil`, `onChange(nil)`.
- Script constante (nunca interpolar):
  ```applescript
  tell application "Finder"
      if (count of Finder windows) is 0 then return ""
      try
          return POSIX path of (target of front Finder window as alias)
      on error
          return ""
      end try
  end tell
  ```
  `NSAppleScript` compilado uma vez, reutilizado, main thread. `""` ⇒ nil.
- Erro `-1743` (automação negada): parar o timer, mostrar **uma vez** (flag em UserDefaults)
  um NSAlert explicando: Ajustes do Sistema → Privacidade e Segurança → Automação → The Styk → Finder.
- No boot: se o Finder já estiver frontal, começar a poll imediatamente.

```swift
final class NoteWindowManager {
    static let shared = NoteWindowManager()
    func setVisibleFolder(_ folder: String?)   // reconcilia painéis: fecha os de fora, abre os da pasta
    func suggestedFrame() -> NoteFrame         // 260×240 perto do centro da tela, cascata +24pt por nota visível
    func flushAll()                            // flushPendingSave em todos os painéis abertos
}
```

- Reconcile-based: guarda `[UUID: NoteWindowController]`. Em `setVisibleFolder` e em
  `NoteStore.indexDidChange`, compara controllers abertos × `entries(inFolder: atual)`:
  fecha (com flush) os que sobram, cria (via `loadNote` lazy) os que faltam. Nota criada
  na pasta atual aparece sozinha por esse caminho.

**AppDelegate:** monta `NSStatusItem` (símbolo `note.text`, template), instancia
`FinderObserver` + `StatusMenuController`, liga `observer.onChange` →
`NoteWindowManager.shared.setVisibleFolder`. `applicationWillTerminate` → `flushAll()`.
**main.swift:** `NSApplication.shared`, activation policy `.accessory`, delegate forte, `app.run()`.

## Contrato — Menu & Export (`StatusMenuController.swift`, `ExportService.swift`)

```swift
final class StatusMenuController: NSObject, NSMenuDelegate {
    init(statusItem: NSStatusItem, finder: FinderObserver)
    // constrói o menu em menuNeedsUpdate (sempre a partir do índice — nunca carrega nota p/ montar menu)
}
```

Estrutura do menu:
1. **"Nova nota nesta pasta"** — habilitado só se `finder.currentFolder != nil`
   (ao clicar: `NoteStore.shared.createNote(inFolder:, frame: NoteWindowManager.shared.suggestedFrame())`).
   Se nil: item desabilitado "Abra uma pasta no Finder para criar uma nota".
2. separador
3. Cabeçalho desabilitado "Notas (N)"; por pasta (ordenada): submenu com título
   abreviado (`(path as NSString).abbreviatingWithTildeInPath`), contendo:
   - "Abrir pasta no Finder" → **validar antes**: URL de arquivo existente, `isDirectory == true`
     e `isPackage != true` (senão item vira "Pasta não encontrada", desabilitado);
     abrir com `NSWorkspace.shared.open(url)`.
   - separador; por nota: item com snippet + submenu: "Abrir pasta no Finder" · "Exportar…"
     (`loadNote` → `ExportService.share(note:relativeTo: nil)`) · "Apagar…" (NSAlert de confirmação → delete).
   - Bolinha da cor da nota como `image` do item (10×10, `Theme.nsColor`).
4. separador · "Sobre o The Styk" (`orderFrontStandardAboutPanel`) · "Sair do The Styk" (`terminate`).

```swift
enum ExportService {
    /// Exporta SEMPRE texto Unicode puro (UTF-8, sem atributos).
    /// Escreve <nome>.txt em NSTemporaryDirectory()/subpasta única e mostra
    /// NSSharingServicePicker (inclui AirDrop) ancorado em `view`;
    /// se view == nil, cria mini janela-âncora transparente no mouse.
    static func share(note: Note, relativeTo view: NSView?)
}
```

- Nome do arquivo: `"The Styk – <snippet>.txt"` **sanitizado**: remover `/`, `:`, chars de
  controle e `\0`; máx 50 chars; fallback `"The Styk – Nota.txt"`.
- Conteúdo: `note.text` como `Data(utf8)`, escrita atômica. Nada de RTF/HTML/atributos.
- O picker precisa ficar retido enquanto aberto (guardar referência estática + delegate p/ soltar).

## Guardrails de segurança (valem para todos)

1. Conteúdo de nota é **dado inerte**: nunca vai para AppleScript, shell, URL, HTML,
   atributo de texto ou nome de arquivo sem sanitização (só o export sanitizado usa).
2. AppleScript: uma única string literal constante no binário.
3. Abrir pasta do índice: só depois de validar diretório-existente-e-não-pacote
   (impede índice adulterado de lançar um .app).
4. Sem rede, sem NSKeyedUnarchiver, sem eval de nada. `Process` tem DUAS exceções
   deliberadas, ambas com executável constante e argv explícito (sem shell, nenhum
   conteúdo de nota chega perto): `/usr/bin/tccutil reset AppleEvents <bundle-id>`
   (fluxo "Pedir permissão do Finder…") e `/usr/bin/ditto` (backup/restauração zip;
   caminhos só do nosso diretório de dados e de NSSave/OpenPanel).
5. Restauração de backup: extrai em tmp e copia SÓ arquivos esperados e validados
   (index.json + notes/<UUID>.json, regulares, com limite de tamanho) — anti
   zip-slip/symlink. Zip inválido não altera nada.
6. Hardened runtime exige `com.apple.security.automation.apple-events` no
   entitlements — sem ele o macOS bloqueia o Apple Event ANTES do TCC (aviso nunca
   aparece e o app não entra no painel de Automação).
7. Limites de tamanho/contagem no parse (anti-DoS por arquivo adulterado).
