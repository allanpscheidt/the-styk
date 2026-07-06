import AppKit

// Modo utilitário para teste/automação: liga/desliga/consulta o item de início e sai.
if let flag = CommandLine.arguments.first(where: { $0.hasPrefix("--login-item=") }) {
    switch flag {
    case "--login-item=on":  print(LoginItem.setEnabled(true) ?? "on ok")
    case "--login-item=off": print(LoginItem.setEnabled(false) ?? "off ok")
    default:                 print("enabled: \(LoginItem.isEnabled)")
    }
    exit(0)
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let delegate = AppDelegate()
app.delegate = delegate
app.run()
