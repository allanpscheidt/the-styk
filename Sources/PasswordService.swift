import AppKit
import CryptoKit

/// Session authentication is never persisted. Store capabilities check this
/// service independently of whether their UI happens to be visible.
enum PasswordService {
    static let passwordHashKey = "thestyk.passwordHash"
    private static let legacyLockedKey = "thestyk.isLocked"
    static let lockStateDidChangeNotification = Notification.Name("thestyk.lockStateDidChange")
    static let willLockNotification = Notification.Name("thestyk.willLock")
    static let inactivityTimeout: TimeInterval = 5 * 60

    enum Operation: Hashable {
        case backup, restore, export, moveToTrash, restoreFromTrash
        case deletePermanently, emptyTrash, passwordChange
    }

    /// Short-lived, single-use proof for exactly one sensitive operation.
    struct Authorization {
        fileprivate let id: UUID
    }

    private struct Grant {
        let operation: Operation
        let expiresAt: Date
    }

    private static let stateLock = NSRecursiveLock()
    // Like THESTYK_DATA_DIR, this seam isolates functional tests only; a person
    // controlling the environment can already execute code as the local user.
    private static let defaults: UserDefaults = {
        if let suite = ProcessInfo.processInfo.environment["THESTYK_DEFAULTS_SUITE"], !suite.isEmpty,
           let isolated = UserDefaults(suiteName: suite) { return isolated }
        return .standard
    }()
    private static var authenticated = false
    private static var locking = false
    private static var grants: [UUID: Grant] = [:]
    private static var lastActivity = Date.distantPast
    private static var inactivityTimer: Timer?
    private static var activityMonitor: Any?
    private static var lifecycleObservers: [NSObjectProtocol] = []

    static var hasPassword: Bool {
        defaults.string(forKey: passwordHashKey) != nil
    }

    static var isLocked: Bool {
        expireSessionIfNeeded()
        stateLock.lock()
        defer { stateLock.unlock() }
        return hasPassword && (!authenticated || (locking && !Thread.isMainThread))
    }

    static var canAccessNotes: Bool { !isLocked }

    /// Called before any store/UI initialization on every application launch.
    static func beginSession() {
        defaults.removeObject(forKey: legacyLockedKey)
        lock()
    }

    /// Sleep, screen lock, user switch and inactivity all revoke grants.
    static func startSessionMonitoring() {
        guard Thread.isMainThread, inactivityTimer == nil else { return }
        let workspace = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.sessionDidResignActiveNotification, NSWorkspace.willSleepNotification] {
            lifecycleObservers.append(workspace.addObserver(forName: name, object: nil, queue: .main) { _ in lock() })
        }
        let distributed = DistributedNotificationCenter.default()
        for name in ["com.apple.screenIsLocked", "com.apple.sessionDidResignActive"] {
            lifecycleObservers.append(distributed.addObserver(forName: Notification.Name(name), object: nil, queue: .main) { _ in lock() })
        }
        activityMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .leftMouseDown, .rightMouseDown, .scrollWheel]) { event in
            recordActivity()
            return event
        }
        let timer = Timer(timeInterval: 5, repeats: true) { _ in expireSessionIfNeeded() }
        RunLoop.main.add(timer, forMode: .common)
        inactivityTimer = timer
    }

    static func recordActivity() {
        expireSessionIfNeeded()
        stateLock.lock()
        if authenticated { lastActivity = Date() }
        stateLock.unlock()
    }

    static func expireSessionIfNeeded(now: Date = Date()) {
        stateLock.lock()
        let expired = !locking && hasPassword && authenticated && now.timeIntervalSince(lastActivity) >= inactivityTimeout
        stateLock.unlock()
        if expired { lock() }
    }

    static func lock() {
        stateLock.lock()
        guard !locking else { stateLock.unlock(); return }
        locking = true
        stateLock.unlock()
        // Flush edits while the old session is valid, then revoke access.
        // A background guard cannot call AppKit on that thread.
        if Thread.isMainThread {
            NotificationCenter.default.post(name: willLockNotification, object: nil)
        }
        stateLock.lock()
        authenticated = false
        grants.removeAll()
        locking = false
        stateLock.unlock()
        notifyLockStateChanged()
    }

    @discardableResult
    static func unlock(withPassword raw: String) -> Bool {
        guard Thread.isMainThread, verifyPassword(raw) else { return false }
        expireSessionIfNeeded()
        stateLock.lock()
        let wasAuthenticated = authenticated
        authenticated = true
        lastActivity = Date()
        stateLock.unlock()
        if !wasAuthenticated { notifyLockStateChanged() }
        return true
    }

    @discardableResult
    static func authenticateForAccess() -> Bool {
        if canAccessNotes { return true }
        return promptForPassword(reason: L("Digite a senha para visualizar e editar suas notas."))
    }

    static func requestAuthorization(for operation: Operation, reason: String) -> Authorization? {
        guard Thread.isMainThread, hasPassword else { return nil }
        // Sensitive actions ask again even in an unlocked session.
        guard promptForPassword(reason: reason) else { return nil }
        return issueAuthorization(for: operation)
    }

    /// Authenticates a non-UI caller without introducing a bypass flag.
    static func authorize(withPassword raw: String, for operation: Operation) -> Authorization? {
        guard hasPassword, unlock(withPassword: raw) else { return nil }
        return issueAuthorization(for: operation)
    }

    private static func issueAuthorization(for operation: Operation) -> Authorization? {
        stateLock.lock()
        defer { stateLock.unlock() }
        guard authenticated, !locking else { return nil }
        grants = grants.filter { $0.value.expiresAt > Date() }
        let authorization = Authorization(id: UUID())
        grants[authorization.id] = Grant(operation: operation, expiresAt: Date().addingTimeInterval(60))
        return authorization
    }

    /// Enforced at the service/store boundary, never just in a button handler.
    static func consumeAuthorization(_ authorization: Authorization?, for operation: Operation) -> Bool {
        guard canAccessNotes else { return false }
        stateLock.lock()
        defer { stateLock.unlock() }
        guard hasPassword else { return true }
        guard authenticated, let authorization = authorization,
              let grant = grants.removeValue(forKey: authorization.id),
              grant.operation == operation, grant.expiresAt > Date() else { return false }
        return true
    }

    @discardableResult
    static func setPassword(_ raw: String, authorization: Authorization? = nil) -> Bool {
        guard !hasPassword || consumeAuthorization(authorization, for: .passwordChange) else { return false }
        lock()
        if raw.isEmpty {
            defaults.removeObject(forKey: passwordHashKey)
        } else {
            defaults.set(hash(raw), forKey: passwordHashKey)
        }
        defaults.removeObject(forKey: legacyLockedKey)
        notifyLockStateChanged()
        return true
    }

    static func verifyPassword(_ raw: String) -> Bool {
        guard let savedHash = defaults.string(forKey: passwordHashKey) else { return true }
        return hash(raw) == savedHash
    }

    private static func hash(_ raw: String) -> String {
        SHA256.hash(data: Data(raw.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    private static func promptForPassword(reason: String) -> Bool {
        guard Thread.isMainThread else { return false }
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = L("Desbloquear Notas")
        alert.informativeText = reason
        alert.addButton(withTitle: L("Confirmar"))
        alert.addButton(withTitle: L("Cancelar"))
        let input = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 220, height: 24))
        alert.accessoryView = input
        alert.window.initialFirstResponder = input
        guard alert.runModal() == .alertFirstButtonReturn else { return false }
        guard unlock(withPassword: input.stringValue) else {
            let error = NSAlert()
            error.messageText = L("Senha incorreta")
            error.informativeText = L("A senha digitada está incorreta. Operação cancelada.")
            error.addButton(withTitle: L("Ok"))
            error.runModal()
            return false
        }
        return true
    }

    private static func notifyLockStateChanged() {
        if Thread.isMainThread {
            NotificationCenter.default.post(name: lockStateDidChangeNotification, object: nil)
        } else {
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: lockStateDidChangeNotification, object: nil)
            }
        }
    }
}
