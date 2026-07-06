import Foundation
import CryptoKit

enum PasswordService {
    static let passwordHashKey = "thestyk.passwordHash"
    static let isLockedKey = "thestyk.isLocked"
    static let lockStateDidChangeNotification = Notification.Name("thestyk.lockStateDidChange")
    
    static var hasPassword: Bool {
        UserDefaults.standard.string(forKey: passwordHashKey) != nil
    }
    
    static var isLocked: Bool {
        get {
            if !hasPassword { return false }
            // Por padrão, se houver senha cadastrada, inicia bloqueado (segurança básica)
            if UserDefaults.standard.object(forKey: isLockedKey) == nil {
                return true
            }
            return UserDefaults.standard.bool(forKey: isLockedKey)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: isLockedKey)
            NotificationCenter.default.post(name: lockStateDidChangeNotification, object: nil)
        }
    }
    
    static func setPassword(_ raw: String) {
        if raw.isEmpty {
            UserDefaults.standard.removeObject(forKey: passwordHashKey)
            isLocked = false
        } else {
            let data = Data(raw.utf8)
            let hash = SHA256.hash(data: data)
            let hashString = hash.map { String(format: "%02x", $0) }.joined()
            UserDefaults.standard.set(hashString, forKey: passwordHashKey)
            isLocked = true
        }
    }
    
    static func verifyPassword(_ raw: String) -> Bool {
        guard let savedHash = UserDefaults.standard.string(forKey: passwordHashKey) else { return true }
        let data = Data(raw.utf8)
        let hash = SHA256.hash(data: data)
        let hashString = hash.map { String(format: "%02x", $0) }.joined()
        return hashString == savedHash
    }
}
