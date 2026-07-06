import AppKit
import Carbon

/// Observa qual pasta está aberta na janela frontal do Finder.
/// Polling (0,8 s) roda SOMENTE enquanto o Finder é o app ativo.
final class FinderObserver {

    /// (pasta normalizada, bounds da janela frontal do Finder em coordenadas AppKit) — ou nils.
    var onChange: ((String?, NSRect?) -> Void)?
    private(set) var currentFolder: String?
    private(set) var currentBounds: NSRect?

    // Script constante — nunca interpolar nada (guardrail de segurança).
    // Devolve "l,t,r,b" + linefeed + caminho (bounds primeiro: nome de pasta pode conter \n).
    private static let scriptSource = """
    tell application "Finder"
        if (count of Finder windows) is 0 then return ""
        try
            set w to front Finder window
            if collapsed of w is true then return ""
            set p to POSIX path of (target of w as alias)
            set b to bounds of w
            return ((item 1 of b) as text) & "," & ((item 2 of b) as text) & "," & \
                   ((item 3 of b) as text) & "," & ((item 4 of b) as text) & linefeed & p
        on error
            return ""
        end try
    end tell
    """

    private var script: NSAppleScript?
    private var timer: Timer?
    private var automationDenied = false
    private let alertShownKey = "thestyk.automationAlertShown"

    func start() {
        script = NSAppleScript(source: FinderObserver.scriptSource)
        script?.compileAndReturnError(nil)

        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(appDidActivate(_:)),
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil
        )

        // Se o Finder já estiver frontal no boot, começa a poll imediatamente.
        if NSWorkspace.shared.frontmostApplication?.bundleIdentifier == "com.apple.finder" {
            startPolling()
        }
    }

    // MARK: - Ativação de apps

    @objc private func appDidActivate(_ notification: Notification) {
        guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey]
                as? NSRunningApplication else { return }

        if app.bundleIdentifier == "com.apple.finder" {
            // Permissão pode ter sido concedida nos Ajustes — voltar ao Finder tenta de novo.
            automationDenied = false
            startPolling()
        } else if app.processIdentifier == ProcessInfo.processInfo.processIdentifier {
            // Nós mesmos (alerta, share, menu): pausa o timer mas MANTÉM a pasta,
            // para as notas continuarem visíveis.
            stopPolling()
        } else {
            stopPolling()
            currentFolder = nil
            currentBounds = nil
            onChange?(nil, nil)
        }
    }

    // MARK: - Polling

    private func startPolling() {
        guard !automationDenied else { return }
        poll()
        if timer == nil {
            let t = Timer(timeInterval: 0.8, target: self,
                          selector: #selector(timerFired), userInfo: nil, repeats: true)
            RunLoop.main.add(t, forMode: .common)
            timer = t
        }
    }

    private func stopPolling() {
        timer?.invalidate()
        timer = nil
    }

    @objc private func timerFired() {
        poll()
    }

    private func poll() {
        guard let script = script else { return }
        var errorInfo: NSDictionary?
        let result = script.executeAndReturnError(&errorInfo)

        if let errorInfo = errorInfo {
            if (errorInfo[NSAppleScript.errorNumber] as? Int) == -1743 {
                // Automação negada: para de vez e explica uma única vez.
                automationDenied = true
                stopPolling()
                showAutomationDeniedAlertOnce()
            }
            return
        }

        let raw = result.stringValue ?? ""
        var folder: String?
        var bounds: NSRect?
        if !raw.isEmpty {
            let parts = raw.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false)
            if parts.count == 2 {
                folder = normalizePath(String(parts[1]))
                let nums = parts[0].split(separator: ",")
                    .compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
                if nums.count == 4, nums[2] > nums[0], nums[3] > nums[1] {
                    // Finder: origem no topo-esquerdo da tela primária, y para baixo.
                    // AppKit: origem embaixo-esquerda da primária, y para cima.
                    let primaryHeight = Double(NSScreen.screens.first?.frame.height ?? 0)
                    bounds = NSRect(x: nums[0], y: primaryHeight - nums[3],
                                    width: nums[2] - nums[0], height: nums[3] - nums[1])
                }
            } else {
                folder = normalizePath(raw)
            }
        }
        if folder != currentFolder || bounds != currentBounds {
            currentFolder = folder
            currentBounds = bounds
            onChange?(folder, bounds)
        }
    }

    // MARK: - Permissão de Automação

    private func showAutomationDeniedAlertOnce() {
        guard !UserDefaults.standard.bool(forKey: alertShownKey) else { return }
        UserDefaults.standard.set(true, forKey: alertShownKey)

        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = L("O The Styk precisa de permissão para ver o Finder")
        alert.informativeText = L("""
        Para saber qual pasta está aberta, o The Styk precisa controlar o Finder via Automação.

        Abra Ajustes do Sistema → Privacidade e Segurança → Automação, localize o The Styk e ative o Finder. Depois, volte à pasta no Finder — as notas aparecem sozinhas.
        """)
        alert.addButton(withTitle: L("Abrir Ajustes"))
        alert.addButton(withTitle: L("Agora não"))
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn,
           let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: - Permissão sob demanda (menu Configurações)

    /// 0 = concedida · -1743 = negada · -1744 = ainda não pedida ·
    /// nil = macOS sem TCC de automação (≤ 10.13, sempre permitido).
    func automationStatus() -> OSStatus? {
        guard #available(macOS 10.14, *) else { return nil }
        return FinderObserver.determinePermission(askIfNeeded: false)
    }

    /// Faz o aviso do sistema voltar a aparecer: se nunca foi pedido, pede agora;
    /// se foi negado, zera a decisão (tccutil, argumentos 100% constantes — nunca
    /// dados do usuário) e pede de novo.
    func requestAutomationPermission(completion: (() -> Void)? = nil) {
        guard #available(macOS 10.14, *) else { completion?(); return }
        DispatchQueue.global(qos: .userInitiated).async {
            if FinderObserver.determinePermission(askIfNeeded: false) == -1743 {
                let p = Process()
                p.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
                p.arguments = ["reset", "AppleEvents", "br.com.allanpscheidt.thestyk"]
                try? p.run()
                p.waitUntilExit()
            }
            // Bloqueia até o usuário responder ao aviso — por isso está fora da main.
            let status = FinderObserver.determinePermission(askIfNeeded: true)
            DispatchQueue.main.async {
                self.finishPermissionFlow(status)
                completion?()
            }
        }
    }

    @available(macOS 10.14, *)
    private static func determinePermission(askIfNeeded: Bool) -> OSStatus {
        var addr = AEAddressDesc()
        let bundleID = "com.apple.finder"
        let created = bundleID.utf8CString.withUnsafeBufferPointer { buf in
            AECreateDesc(typeApplicationBundleID, buf.baseAddress, buf.count - 1, &addr)
        }
        guard created == noErr else { return OSStatus(created) }
        defer { _ = AEDisposeDesc(&addr) }
        return AEDeterminePermissionToAutomateTarget(&addr, typeWildCard, typeWildCard, askIfNeeded)
    }

    private func finishPermissionFlow(_ status: OSStatus) {
        let alert = NSAlert()
        if status == noErr {
            automationDenied = false
            alert.messageText = L("Tudo certo")
            alert.informativeText = L("O The Styk já pode ver qual pasta está aberta no Finder. Volte à pasta e as notas aparecem.")
            alert.addButton(withTitle: L("OK"))
            NSApp.activate(ignoringOtherApps: true)
            alert.runModal()
        } else {
            alert.alertStyle = .warning
            alert.messageText = L("A permissão continua negada")
            alert.informativeText = L("Abra Ajustes do Sistema → Privacidade e Segurança → Automação, localize o The Styk e ative o Finder. Depois, volte à pasta no Finder.")
            alert.addButton(withTitle: L("Abrir Ajustes"))
            alert.addButton(withTitle: L("Agora não"))
            NSApp.activate(ignoringOtherApps: true)
            if alert.runModal() == .alertFirstButtonReturn,
               let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation") {
                NSWorkspace.shared.open(url)
            }
        }
    }
}
