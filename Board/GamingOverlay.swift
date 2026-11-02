import SwiftUI
import AppKit

@MainActor final class GamingOverlay: ObservableObject {
    struct Hold { let start: Double; var released: Double? }
    static let keys = [13, 0, 1, 2, 56, 59, 49, 1000, 1001]
    @Published var enabled: Bool {
        didSet {
            defaults.set(enabled, forKey: "gaming.overlay.enabled")
            if enabled { present() } else { clear(); panel?.orderOut(nil) }
        }
    }
    @Published private(set) var holds: [Int: Hold] = [:]
    @Published private(set) var now = 0.0
    private(set) var available = false
    private(set) var timer: Timer?
    private var panel: PassivePanel?
    private let presentsWindow: Bool
    private let clock: () -> Double
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard, presentsWindow: Bool = true, clock: @escaping () -> Double = { ProcessInfo.processInfo.systemUptime }) {
        self.defaults = defaults
        enabled = defaults.bool(forKey: "gaming.overlay.enabled")
        self.presentsWindow = presentsWindow; self.clock = clock
    }
    deinit { timer?.invalidate() }
    func setAvailable(_ value: Bool) {
        guard available != value else { return }
        available = value
        if value { present() } else { clear(); panel?.orderOut(nil) }
    }
    func receive(_ event: PhysicalInputEvent) {
        guard enabled, available, Self.keys.contains(event.key) else { return }
        now = clock()
        if event.transition == .press {
            guard holds[event.key]?.released != nil || holds[event.key] == nil else { return }
            holds[event.key] = Hold(start: now)
        } else if holds[event.key] != nil { holds[event.key]?.released = now }
        guard timer == nil, !holds.isEmpty else { return }
        let timer = Timer(timeInterval: 0.05, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        self.timer = timer; RunLoop.main.add(timer, forMode: .common)
    }
    func tick() {
        now = clock()
        holds = holds.filter { $0.value.released.map { now-$0 < 0.35 } ?? true }
        if holds.isEmpty { timer?.invalidate(); timer = nil }
    }
    func clear() { timer?.invalidate(); timer = nil; holds = [:] }
    private func present() {
        guard enabled, available, presentsWindow else { return }
        if panel == nil {
            let panel = PassivePanel(contentRect: NSRect(x: 0, y: 0, width: 310, height: 214),
                                     styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            panel.title = "Board — Gaming Keys"
            panel.isReleasedWhenClosed = false; panel.isOpaque = false; panel.backgroundColor = .clear
            panel.hasShadow = false; panel.ignoresMouseEvents = true; panel.hidesOnDeactivate = false
            panel.level = .statusBar; panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            panel.contentView = NSHostingView(rootView: GamingCluster(overlay: self).padding(16)
                .background(Color(nsColor: .windowBackgroundColor).opacity(0.94), in: RoundedRectangle(cornerRadius: 16)))
            if let frame = NSScreen.main?.visibleFrame { panel.setFrameOrigin(NSPoint(x: frame.minX+24, y: frame.minY+24)) }
            self.panel = panel
        }
        panel?.orderFrontRegardless()
    }
}

struct GamingCluster: View {
    @ObservedObject var overlay: GamingOverlay
    private func key(_ code: Int, _ label: String, width: CGFloat = 48) -> some View {
        let hold = overlay.holds[code]
        let pressed = hold != nil && hold?.released == nil
        let tail = hold?.released.map { max(0, 1-(overlay.now-$0)/0.35) } ?? 0
        return VStack(spacing: 2) {
            Text(label).font(.system(size: 12, weight: .semibold, design: .rounded))
            Text(hold.map { String(format: "%.0f ms", (($0.released ?? overlay.now)-$0.start)*1000) } ?? " ")
                .font(.system(size: 9, design: .monospaced)).foregroundStyle(.secondary).opacity(pressed ? 1 : tail)
        }.frame(width: width, height: 42)
            .background(pressed ? Color.accentColor.opacity(0.3) : Color.primary.opacity(0.04+0.09*tail), in: RoundedRectangle(cornerRadius: 7))
            .overlay(RoundedRectangle(cornerRadius: 7).stroke(Color.primary.opacity(pressed ? 0.5 : 0.12)))
            .accessibilityLabel(label + (pressed ? " held" : " released"))
    }
    var body: some View {
        VStack(spacing: 7) {
            HStack(spacing: 7) { Color.clear.frame(width: 48, height: 42); key(13, "W"); Color.clear.frame(width: 48, height: 42); key(1000, "LMB"); key(1001, "RMB") }
            HStack(spacing: 7) { key(0, "A"); key(1, "S"); key(2, "D"); Spacer(minLength: 0) }
            HStack(spacing: 7) { key(56, "L Shift", width: 68); key(59, "L Ctrl", width: 68); key(49, "Space", width: 118) }
            Text("BOARD · GAMING KEYS").font(.system(size: 9, weight: .medium)).foregroundStyle(.secondary)
        }.frame(width: 268)
    }
}
