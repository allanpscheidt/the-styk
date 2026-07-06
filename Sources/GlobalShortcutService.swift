import Carbon
import AppKit

final class GlobalShortcutService {
    static let shared = GlobalShortcutService()
    
    private var hotKeyRef: EventHotKeyRef? = nil
    var onTrigger: (() -> Void)?
    
    func register() {
        var hotKeyID = EventHotKeyID()
        hotKeyID.signature = OSType(0x5354594B) // "STYK" em ASCII/HEX
        hotKeyID.id = 1
        
        // Atalho: Command (cmdKey) + Option (optionKey) + N
        let modifiers = UInt32(cmdKey | optionKey)
        let keyCode = UInt32(kVK_ANSI_N) // Tecla N (código 45)
        
        var eventType = EventTypeSpec()
        eventType.eventClass = OSType(kEventClassKeyboard)
        eventType.eventKind = OSType(kEventHotKeyPressed)
        
        let eventHandler: EventHandlerUPP = { (nextHandler, event, userData) -> OSStatus in
            DispatchQueue.main.async {
                GlobalShortcutService.shared.onTrigger?()
            }
            return noErr
        }
        
        InstallEventHandler(
            GetApplicationEventTarget(),
            eventHandler,
            1,
            &eventType,
            nil as UnsafeMutableRawPointer?,
            nil as UnsafeMutablePointer<EventHandlerRef?>?
        )
        
        RegisterEventHotKey(keyCode, modifiers, hotKeyID, GetApplicationEventTarget(), 0, &hotKeyRef)
    }
}
