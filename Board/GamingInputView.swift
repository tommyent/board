import AppKit
import SwiftUI

struct GamingInputView: NSViewRepresentable {
    @ObservedObject var game: GamingPractice
    let checkAvailability: () -> Void
    func makeNSView(context: Context) -> GamingInputSurface {
        let view = GamingInputSurface()
        view.setAccessibilityElement(true); view.setAccessibilityRole(.group)
        view.setAccessibilityLabel("Gaming input")
        view.setAccessibilityHelp("Physical QWERTY positions. Escape pauses. Control Tab moves to the next control.")
        return view
    }
    func updateNSView(_ view: GamingInputSurface, context: Context) {
        view.game = game; view.checkAvailability = checkAvailability
        if view.focusRequest != game.focusRequest {
            view.focusRequest = game.focusRequest
            DispatchQueue.main.async { [weak view] in
                guard let view, view.game?.selected == true, view.window?.isKeyWindow == true,
                      view.game?.unavailableReason == nil, view.game?.active == true else { return }
                view.window?.makeFirstResponder(view)
            }
        }
    }
}

final class GamingInputSurface: NSView {
    weak var game: GamingPractice?
    var checkAvailability: (() -> Void)?
    var focusRequest = -1
    override var acceptsFirstResponder: Bool { true }
    override func resignFirstResponder() -> Bool { game?.pause(); return super.resignFirstResponder() }
    override func keyDown(with event: NSEvent) {
        checkAvailability?()
        if event.keyCode == 53 { game?.pause(); return }
        if event.keyCode == 48 { game?.pause(); window?.selectNextKeyView(self); return }
        if event.modifierFlags.contains(.command) { game?.pause(); super.keyDown(with: event); return }
        game?.press(.key(event.keyCode), isRepeat: event.isARepeat)
    }
    override func keyUp(with event: NSEvent) { checkAvailability?(); game?.release(.key(event.keyCode)) }
    override func flagsChanged(with event: NSEvent) {
        checkAvailability?()
        let masks: [UInt16: UInt64] = [56: 0x2, 59: 0x1, 60: 0x4, 62: 0x2000]
        guard let mask = masks[event.keyCode] else { return }
        if event.modifierFlags.rawValue & UInt(mask) != 0 { game?.press(.key(event.keyCode)) }
        else { game?.release(.key(event.keyCode)) }
    }
    private func mouse(_ event: NSEvent, down: Bool) {
        checkAvailability?()
        if window?.firstResponder !== self { window?.makeFirstResponder(self); return }
        guard let button = UInt8(exactly: event.buttonNumber) else { return }
        if down { game?.press(.mouse(button)) } else { game?.release(.mouse(button)) }
    }
    override func mouseDown(with event: NSEvent) { mouse(event, down: true) }
    override func mouseUp(with event: NSEvent) { mouse(event, down: false) }
    override func rightMouseDown(with event: NSEvent) { mouse(event, down: true) }
    override func rightMouseUp(with event: NSEvent) { mouse(event, down: false) }
}
