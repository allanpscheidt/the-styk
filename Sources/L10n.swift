import Foundation

/// Idiomas do app. pt-BR é o padrão e a língua-fonte: as chaves de tradução
/// SÃO os literais em português do código.
enum AppLanguage: String, CaseIterable {
    case ptBR = "pt-BR"
    case en = "en"
    case zhHans = "zh-Hans"
    case ja = "ja"
    case de = "de"
    case fr = "fr"

    var displayName: String {
        switch self {
        case .ptBR:   return "Português (Brasil)"
        case .en:     return "English"
        case .zhHans: return "简体中文"
        case .ja:     return "日本語"
        case .de:     return "Deutsch"
        case .fr:     return "Français"
        }
    }
}

enum L10n {
    static let didChange = Notification.Name("thestyk.languageDidChange")
    private static let defaultsKey = "thestyk.language"

    static var current: AppLanguage {
        AppLanguage(rawValue: UserDefaults.standard.string(forKey: defaultsKey) ?? "") ?? .ptBR
    }

    static func setCurrent(_ lang: AppLanguage) {
        UserDefaults.standard.set(lang.rawValue, forKey: defaultsKey)
        NotificationCenter.default.post(name: didChange, object: nil)
    }

    static func table(for lang: AppLanguage) -> [String: String] {
        switch lang {
        case .ptBR:   return [:]
        case .en:     return en
        case .zhHans: return zhHans
        case .ja:     return ja
        case .de:     return de
        case .fr:     return fr
        }
    }
}

/// Tradução: chave = literal pt-BR do código. Fallback = a própria chave.
/// Placeholders (%d, %@) são preservados — usar com String(format:) quando houver.
func L(_ key: String) -> String {
    let lang = L10n.current
    if lang == .ptBR { return key }
    return L10n.table(for: lang)[key] ?? key
}
