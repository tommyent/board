import AppKit
import Carbon

final class InputMonitor {
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var runLoop: CFRunLoop?
    private var normalizer = InputNormalizer()
    private var suspended = false
    var onEvent: ((PhysicalInputEvent) -> Void)?
    var onReset: (() -> Void)?
    var onStatus: ((String) -> Void)?
    private var previousStatus = ""

    func begin() {
        let thread = Thread { [weak self] in
            guard let self else { return }
            self.runLoop = CFRunLoopGetCurrent()
            let port = Port(); RunLoop.current.add(port, forMode: .default)
            self.refresh()
            let timer = Timer(timeInterval: 2, repeats: true) { [weak self] _ in self?.refresh() }
            RunLoop.current.add(timer, forMode: .common)
            RunLoop.current.run()
        }
        thread.name = "Board passive input"; thread.qualityOfService = .userInteractive; thread.start()
    }
    func refreshSoon() { perform { self.refresh() } }
    func setSuspended(_ value: Bool) { perform { self.suspended = value; self.refresh() } }
    private func perform(_ block: @escaping () -> Void) {
        guard let runLoop else { return }
        CFRunLoopPerformBlock(runLoop, CFRunLoopMode.commonModes.rawValue, block); CFRunLoopWakeUp(runLoop)
    }
    private func status(_ value: String) {
        guard value != previousStatus else { return }; previousStatus = value; onStatus?(value)
    }
    private func stop() {
        if let tap { CGEvent.tapEnable(tap: tap, enable: false); CFMachPortInvalidate(tap) }
        if let source, let runLoop { CFRunLoopRemoveSource(runLoop,source,.commonModes) }
        tap = nil; source = nil; normalizer.clear(); onReset?()
    }
    private func refresh() {
        if suspended { if tap != nil { stop() }; status("Paused while session is inactive"); return }
        if IsSecureEventInputEnabled() { if tap != nil { stop() }; status("Paused for Secure Input"); return }
        guard CGPreflightListenEventAccess() else { if tap != nil { stop() }; status("Input Monitoring required"); return }
        if let tap {
            if !CGEvent.tapIsEnabled(tap:tap) { normalizer.clear(); onReset?(); CGEvent.tapEnable(tap:tap,enable:true) }
            status(CGEvent.tapIsEnabled(tap:tap) ? "Listening to physical input" : "Input monitoring unavailable"); return
        }
        let types: [UInt32] = [CGEventType.keyDown.rawValue,CGEventType.keyUp.rawValue,CGEventType.flagsChanged.rawValue,CGEventType.leftMouseDown.rawValue,CGEventType.leftMouseUp.rawValue,CGEventType.rightMouseDown.rawValue,CGEventType.rightMouseUp.rawValue,CGEventType.otherMouseDown.rawValue,CGEventType.otherMouseUp.rawValue,14]
        let mask = types.reduce(UInt64(0)) { $0 | (UInt64(1) << $1) }
        tap = CGEvent.tapCreate(tap:.cgSessionEventTap,place:.headInsertEventTap,options:.listenOnly,eventsOfInterest:mask,callback: { _, type, event, context in
            guard let context else { return Unmanaged.passUnretained(event) }
            let monitor = Unmanaged<InputMonitor>.fromOpaque(context).takeUnretainedValue()
            monitor.receive(type,event)
            return Unmanaged.passUnretained(event)
        },userInfo:Unmanaged.passUnretained(self).toOpaque())
        guard let tap else { status("Input monitoring unavailable — quit and reopen Board"); return }
        source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault,tap,0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(),source,.commonModes)
        CGEvent.tapEnable(tap:tap,enable:true)
        status("Listening to physical input")
    }
    private func receive(_ type: CGEventType, _ event: CGEvent) {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput { normalizer.clear(); onReset?(); refresh(); return }
        guard !suspended, !IsSecureEventInputEnabled() else { normalizer.clear(); onReset?(); return }
        // Exclude process-posted synthetic events (including IME reconstruction), leaving the hardware path.
        guard event.getIntegerValueField(.eventSourceUnixProcessID) <= 0 else { return }
        var key = Int(event.getIntegerValueField(.keyboardEventKeycode))
        var down = type == .keyDown
        switch type {
        case .keyDown,.keyUp: break
        case .flagsChanged:
            let physicalMasks: [Int: UInt64] = [59:0x1,56:0x2,60:0x4,55:0x8,54:0x10,58:0x20,61:0x40,62:0x2000,63:CGEventFlags.maskSecondaryFn.rawValue,57:CGEventFlags.maskAlphaShift.rawValue]
            guard let mask = physicalMasks[key] else { return }
            down = event.flags.rawValue & mask != 0
        case .leftMouseDown,.leftMouseUp: key = 1000; down = type == .leftMouseDown
        case .rightMouseDown,.rightMouseUp: key = 1001; down = type == .rightMouseDown
        case .otherMouseDown,.otherMouseUp: key = 1000+Int(event.getIntegerValueField(.mouseEventButtonNumber)); down = type == .otherMouseDown
        default:
            guard type.rawValue == 14, let native = NSEvent(cgEvent:event), native.subtype.rawValue == 8 else { return }
            let flags = native.data1 & 0xFFFF
            guard flags & 1 == 0 else { return }
            key = 2000+((native.data1 >> 16) & 0xFFFF); down = ((flags >> 8) & 0xFF) == 0xA
        }
        if let normalized = normalizer.accept(key:key,down:down,repeatEvent:type == .keyDown && event.getIntegerValueField(.keyboardEventAutorepeat) != 0,modifiers:event.flags.rawValue,time:ProcessInfo.processInfo.systemUptime) { onEvent?(normalized) }
    }
}
