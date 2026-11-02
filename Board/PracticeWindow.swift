import AppKit
import Carbon
import SwiftUI

@MainActor final class PracticeWindowController: NSWindowController, NSWindowDelegate {
    let session: PracticeSession
    let game: GamingPractice
    private var timer: Timer?
    private var observers: [NSObjectProtocol] = []
    private var sessionActive = true

    init(app: AppState, defaults: UserDefaults = .standard) {
        session = PracticeSession(defaults: defaults)
        game = GamingPractice(defaults: defaults)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 920, height: 720),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        super.init(window: window)
        window.title = "Board — Practice"
        window.minSize = NSSize(width: 760, height: 640)
        window.isReleasedWhenClosed = false
        window.setFrameAutosaveName("Board Practice")
        window.delegate = self
        window.contentView = NSHostingView(rootView: GamingPracticeRoot(session: session, game: game, app: app, checkAvailability: { [weak self] in self?.refreshAvailability() }))
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: NSApplication.didResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.session.updateAvailability(active: false, secureInput: IsSecureEventInputEnabled()); self?.game.updateAvailability(active: false, secureInput: IsSecureEventInputEnabled()) }
        })
        let workspace = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.willSleepNotification, NSWorkspace.sessionDidResignActiveNotification] {
            observers.append(workspace.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.sessionActive = false; self?.refreshAvailability() }
            })
        }
        for name in [NSWorkspace.didWakeNotification, NSWorkspace.sessionDidBecomeActiveNotification] {
            observers.append(workspace.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.sessionActive = true; self?.refreshAvailability() }
            })
        }
    }
    required init?(coder: NSCoder) { fatalError("Not used") }
    deinit {
        timer?.invalidate()
        for observer in observers {
            NotificationCenter.default.removeObserver(observer)
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
    }
    func open() {
        if timer == nil {
            let timer = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.refreshAvailability(); self?.session.tick() }
            }
            RunLoop.main.add(timer, forMode: .common)
            self.timer = timer
        }
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        refreshAvailability()
        session.focusRequest += 1
    }
    func refreshAvailability() {
        session.updateAvailability(active: sessionActive && NSApp.isActive && window?.isKeyWindow == true && window?.attachedSheet == nil,
                                   secureInput: IsSecureEventInputEnabled())
        game.updateAvailability(active: game.selected && sessionActive && NSApp.isActive && window?.isKeyWindow == true && window?.attachedSheet == nil,
                                secureInput: IsSecureEventInputEnabled())
    }
    func windowDidResignKey(_ notification: Notification) {
        session.updateAvailability(active: false, secureInput: IsSecureEventInputEnabled())
        game.updateAvailability(active: false, secureInput: IsSecureEventInputEnabled())
    }
    func windowDidBecomeKey(_ notification: Notification) { refreshAvailability(); session.focusRequest += 1 }
    func windowWillClose(_ notification: Notification) { timer?.invalidate(); timer = nil; session.close(); game.reset(); game.updateAvailability(active: false, secureInput: false) }
}
