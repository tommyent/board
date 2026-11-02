import AppKit
import SwiftUI

// NSTextView preserves native selection, accessibility, dead keys and input-method composition.
struct PracticeInput: NSViewRepresentable {
    @ObservedObject var session: PracticeSession
    let checkAvailability: () -> Void

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        let input = PracticeTextView()
        input.session = session
        input.checkAvailability = checkAvailability
        input.delegate = context.coordinator
        input.isRichText = false
        input.isAutomaticQuoteSubstitutionEnabled = false
        input.isAutomaticDashSubstitutionEnabled = false
        input.isAutomaticTextReplacementEnabled = false
        input.isAutomaticSpellingCorrectionEnabled = false
        input.isContinuousSpellCheckingEnabled = false
        input.isGrammarCheckingEnabled = false
        input.allowsUndo = false
        input.font = .monospacedSystemFont(ofSize: 18, weight: .regular)
        input.textContainerInset = NSSize(width: 12, height: 10)
        input.isVerticallyResizable = true
        input.isHorizontallyResizable = false
        input.autoresizingMask = [.width]
        input.textContainer?.widthTracksTextView = true
        input.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        input.setAccessibilityLabel("Practice typing area")
        input.setAccessibilityHelp("Type the passage above. Paste is disabled during a test. Tab inserts four spaces in code; Control-Tab moves focus. Escape pauses.")
        scroll.documentView = input
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let input = scroll.documentView as? PracticeTextView else { return }
        input.checkAvailability = checkAvailability
        if !session.acceptsInput, input.hasMarkedText() { input.unmarkText() }
        if !input.hasMarkedText(), input.string != session.typed {
            input.string = session.typed
            input.setSelectedRange(NSRange(location: (input.string as NSString).length, length: 0))
        }
        let becameEditable = !input.isEditable && session.acceptsInput
        input.isEditable = session.acceptsInput
        if context.coordinator.focusRequest != session.focusRequest || becameEditable {
            context.coordinator.focusRequest = session.focusRequest
            DispatchQueue.main.async { [weak input] in
                guard let input, input.session?.acceptsInput == true, input.window?.isKeyWindow == true else { return }
                input.window?.makeFirstResponder(input)
            }
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(session: session) }

    @MainActor final class Coordinator: NSObject, NSTextViewDelegate {
        let session: PracticeSession
        var focusRequest = -1
        init(session: PracticeSession) { self.session = session }
        func textDidEndEditing(_ notification: Notification) {
            guard let input = notification.object as? NSTextView, let window = input.window,
                  window.firstResponder !== input else { return }
            session.pause("Paused while typing area is inactive")
        }
        func textDidChange(_ notification: Notification) {
            (notification.object as? PracticeTextView)?.commitText()
        }
        func textView(_ textView: NSTextView, shouldChangeTextIn affectedCharRange: NSRange, replacementString: String?) -> Bool {
            guard let input = textView as? PracticeTextView else { return false }
            input.checkAvailability?()
            guard session.acceptsInput else { return false }
            let added = (replacementString ?? "") as NSString
            return textView.string.utf16.count - affectedCharRange.length + added.length <= PracticeSession.textLimit * 2
        }
    }
}

@MainActor final class PracticeTextView: NSTextView {
    weak var session: PracticeSession?
    var checkAvailability: (() -> Void)?

    func commitText() {
        guard !hasMarkedText(), let session else { return }
        checkAvailability?()
        if !session.replaceTyped(string) {
            string = session.typed
            setSelectedRange(NSRange(location: (string as NSString).length, length: 0))
        }
    }

    override func insertText(_ insertString: Any, replacementRange: NSRange) {
        checkAvailability?()
        guard session?.acceptsInput == true else { return }
        super.insertText(insertString, replacementRange: replacementRange)
        // IME textDidChange can precede clearing the marked range; commit after insertion returns.
        commitText()
    }

    override func keyDown(with event: NSEvent) {
        checkAvailability?()
        if event.keyCode == 53 { session?.pause(); return }
        if event.modifierFlags.contains(.control), event.keyCode == 48 {
            if event.modifierFlags.contains(.shift) { window?.selectPreviousKeyView(self) }
            else { window?.selectNextKeyView(self) }
            return
        }
        guard session?.acceptsInput == true else { return }
        if !event.isARepeat, !event.modifierFlags.contains(.command) {
            let physical = PhysicalInputEvent(key: Int(event.keyCode), transition: .press,
                                              modifiers: UInt64(event.modifierFlags.rawValue), timestamp: event.timestamp)
            session?.recordKey(KeyGeometry.chord(physical))
        }
        // Audio remains exclusively on InputMonitor's physical event path.
        super.keyDown(with: event)
    }

    override func insertTab(_ sender: Any?) {
        if session?.mode == .code { insertText("    ", replacementRange: selectedRange()) }
        else { window?.selectNextKeyView(self) }
    }
    override func insertBacktab(_ sender: Any?) { window?.selectPreviousKeyView(self) }
    override func paste(_ sender: Any?) { }
    override func pasteAsPlainText(_ sender: Any?) { }
    override func pasteAsRichText(_ sender: Any?) { }
    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool { false }
}
