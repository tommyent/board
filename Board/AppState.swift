import SwiftUI
import ServiceManagement
import UniformTypeIdentifiers

@MainActor final class AppState: ObservableObject {
    @Published var selectedSettingsSection: SettingsSection? = .general
    @Published var settings: AppSettings { didSet { persistAndApply() } }
    @Published var inputStatus = "Input Monitoring required"
    // macOS shows its permission prompt only once, so after one request the card offers System Settings instead.
    @Published var inputRequested = false
    @Published var audioStatus = "Preparing sound…"
    @Published var audioMetrics = ""
    @Published var playbackStatus = "Audio idle"
    @Published var motionStatus = "Head tracking off"
    @Published var devices: [AudioDevice] = []
    @Published var error: String?
    @Published var heldKeys = Set<Int>()
    @Published var combo = ComboState()
    @Published var visualTrail = VisualizerTrail()
    private var visualExpiry: DispatchWorkItem?
    @Published var selectedKey = 0
    @Published var recordingShortcut = false
    @Published var loginStatus = ""
    @Published var aiStatus = "Off"
    let monitor = InputMonitor()
    let audio: KeyboardAudio
    let ai = AIMode()
    private var sessionActive = true
    let resources: URL
    lazy var iconImages: [String:NSImage] = Dictionary(uniqueKeysWithValues:AppSettings.iconColors.compactMap { color in NSImage(contentsOf:resources.appendingPathComponent("AppIcons/Board-\(color).icns")).map { (color,$0) } })
    var iconImage: NSImage { iconImages[settings.iconColor ?? "Porcelain"] ?? NSImage() }
    var accent: Accent { Accent(settings.iconColor) }
    let storage: URL
    let importDirectory: URL
    private let defaults: UserDefaults
    private var shortcut = ShortcutState()
    private var observers: [NSObjectProtocol] = []
    private var started = false
    var onPreferences: (() -> Void)?
    var onVisualEvent: ((Bool) -> Void)?
    var onVisualReset: (() -> Void)?
    var showSettings: (() -> Void)?
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        resources = Bundle.main.resourceURL!.appendingPathComponent("Resources")
        storage = FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0].appendingPathComponent("Board")
        importDirectory = storage.appendingPathComponent("Imported Audio")
        audio = KeyboardAudio(root:resources,importsRoot:importDirectory)
        if let data = defaults.data(forKey:"appSettings.v1"), let decoded = try? JSONDecoder().decode(AppSettings.self,from:data), decoded.version == 1 { settings = decoded }
        else { settings = AppSettings() }
        settings.validate()
    }
    func start() {
        guard !started else { return }; started = true
        // Board 0.4.1's agent hooks used this folder (a "listening" marker and queued edits); 0.4.2 dropped them.
        try? FileManager.default.removeItem(at:storage.appendingPathComponent("AI Queue"))
        audio.onStatus = { [weak self] value in DispatchQueue.main.async { self?.audioStatus = value } }
        audio.onPlayback = { [weak self] value in DispatchQueue.main.async { self?.playbackStatus = value } }
        audio.onMetrics = { [weak self] value in DispatchQueue.main.async { self?.audioMetrics = value } }
        audio.onMotion = { [weak self] value in DispatchQueue.main.async { if self?.motionStatus != value { self?.motionStatus = value } } }
        audio.onDevices = { [weak self] devices in DispatchQueue.main.async { if self?.devices != devices { self?.devices = devices } } }
        monitor.onStatus = { [weak self] value in DispatchQueue.main.async { self?.inputStatus = value } }
        let engine = audio
        monitor.onEvent = { [weak self] event in
            engine.handle(event)
            DispatchQueue.main.async { self?.receive(event) }
        }
        monitor.onReset = { [weak self] in engine.reset(); DispatchQueue.main.async { self?.clearVisuals() } }
        // AI mode's keystrokes take the same path as physical ones, minus the toggle shortcut.
        ai.onEvent = { [weak self] event in engine.handle(event); self?.visualize(event) }
        ai.onStatus = { [weak self] value in self?.aiStatus = value }
        ai.canPlay = { [weak self] in self.map { $0.settings.enabled && !$0.settings.muted && $0.sessionActive } ?? false }
        audio.begin(); audio.configure(settings); configureAI(); monitor.begin(); refreshLogin()
        let workspace = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.willSleepNotification,NSWorkspace.sessionDidResignActiveNotification] {
            observers.append(workspace.addObserver(forName:name,object:nil,queue:.main) { [weak self] _ in MainActor.assumeIsolated { self?.sessionActive = false; self?.monitor.setSuspended(true); self?.audio.reset(); self?.clearVisuals() } })
        }
        for name in [NSWorkspace.didWakeNotification,NSWorkspace.sessionDidBecomeActiveNotification] {
            observers.append(workspace.addObserver(forName:name,object:nil,queue:.main) { [weak self] _ in MainActor.assumeIsolated { self?.sessionActive = true; self?.monitor.setSuspended(false); self?.audio.recover() } })
        }
        observers.append(NotificationCenter.default.addObserver(forName:NSApplication.didBecomeActiveNotification,object:nil,queue:.main) { [weak self] _ in MainActor.assumeIsolated { self?.monitor.refreshSoon(); self?.refreshLogin() } })
    }
    private func persistAndApply() {
        guard started else { return }
        do { defaults.set(try JSONEncoder().encode(settings),forKey:"appSettings.v1") }
        catch { self.error = "Settings could not be saved: \(error.localizedDescription)" }
        audio.configure(settings); configureAI()
        if !settings.enabled || !settings.visualizer.enabled { clearVisuals() }
        onPreferences?()
    }
    private func configureAI() { ai.configure(enabled:settings.aiMode ?? false,speed:settings.aiSpeed ?? 0.35,folder:settings.aiFolder) }
    private func receive(_ event: PhysicalInputEvent) {
        if recordingShortcut, event.transition == .press, !KeyGeometry.modifierKeys.contains(event.key), !event.isMouse {
            settings.shortcutKey = event.key
            let mask = CGEventFlags.maskCommand.rawValue | CGEventFlags.maskControl.rawValue | CGEventFlags.maskAlternate.rawValue | CGEventFlags.maskShift.rawValue
            settings.shortcutModifiers = event.modifiers & mask
            recordingShortcut = false; return
        }
        if shortcut.matches(event,settings:settings) { toggle(); clearVisuals(); return }
        visualize(event)
    }
    func visualize(_ event: PhysicalInputEvent) {
        guard settings.enabled, settings.visualizer.enabled else { return }
        guard !event.isMouse else { return }
        if event.transition == .release {
            guard heldKeys.remove(event.key) != nil else { return }
            visualTrail.release(event.key,at:event.timestamp)
            scheduleVisualExpiry()
            if settings.visualizer.style == "Keyboard" { onVisualEvent?(false) }
            return
        }
        heldKeys.insert(event.key)
        let shuffle = combo.press(at:event.timestamp,settings:settings.visualizer)
        visualTrail.press(event)
        scheduleVisualExpiry()
        onVisualEvent?(shuffle)
    }
    private func scheduleVisualExpiry() {
        visualExpiry?.cancel(); visualExpiry = nil
        guard let deadline = visualTrail.nextExpiry else { return }
        let task = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.visualTrail.expire(at:ProcessInfo.processInfo.systemUptime)
            self.scheduleVisualExpiry()
        }
        visualExpiry = task
        DispatchQueue.main.asyncAfter(deadline:.now()+max(0,deadline-ProcessInfo.processInfo.systemUptime),execute:task)
    }
    func clearVisualTail() { visualExpiry?.cancel(); visualExpiry = nil; visualTrail = VisualizerTrail() }
    func clearVisuals() { heldKeys.removeAll(); clearVisualTail(); combo.clear(); onVisualReset?() }
    func toggle() { settings.enabled.toggle(); if settings.toggleCues { audio.cue(enabled:settings.enabled) }; clearVisuals() }
    func requestInput() { _ = CGRequestListenEventAccess(); inputRequested = true; monitor.refreshSoon() }
    func openInputSettings() {
        let urls = [
            "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_ListenEvent",
            "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent"
        ]
        for item in urls {
            if let url = URL(string:item), NSWorkspace.shared.open(url) { return }
        }
    }
    func select(_ profile: SoundProfile) {
        guard SoundProfile.find(profile.id) != nil else { return }
        settings.sound.profile = profile.id; audio.preview(profile:profile.id)
    }
    var selectedProfile: SoundProfile { SoundProfile.find(settings.sound.profile) ?? SoundProfile.find("alpaca")! }
    var shortcutLabel: String { KeyGeometry.chord(.init(key:settings.shortcutKey,transition:.press,modifiers:settings.shortcutModifiers,timestamp:0)) + (settings.gestureTaps > 1 ? " ×\(settings.gestureTaps)" : "") }
    func savePreset(name: String) {
        guard settings.presets.count < 6 else { error = "Six favorites are already saved. Remove one to save another."; return }
        let name = name.trimmingCharacters(in:.whitespacesAndNewlines)
        settings.presets.append(SoundPreset(name:name.isEmpty ? selectedProfile.name : name,sound:settings.sound))
    }
    func setLogin(_ enabled: Bool) {
        do { if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }; refreshLogin() }
        catch { self.error = "Login item: \(error.localizedDescription)"; refreshLogin() }
    }
    var loginEnabled: Bool { SMAppService.mainApp.status == .enabled }
    func refreshLogin() {
        switch SMAppService.mainApp.status {
        case .enabled: loginStatus = "Enabled"
        case .requiresApproval: loginStatus = "Approval required in System Settings → Login Items"
        // A main app that was never registered reports notFound, not notRegistered (observed on macOS 27).
        case .notRegistered, .notFound: loginStatus = "Off"
        @unknown default: loginStatus = "Unavailable"
        }
    }
    func importSound(target: String, pair: Bool) {
        func choose(_ title: String) -> URL? {
            let panel = NSOpenPanel(); panel.title = title; panel.allowedContentTypes = [.wav,.aiff,.mp3,.mpeg4Audio,.audio]; panel.allowsMultipleSelection = false
            return panel.runModal() == .OK ? panel.url : nil
        }
        guard let press = choose("Choose the press sound") else { return }
        var release: URL?
        if pair { guard let selected = choose("Choose the release sound") else { return }; release = selected }
        let directory = importDirectory
        let releaseURL = release
        DispatchQueue.global(qos:.userInitiated).async {
            do {
                let imported = try AudioFiles.importPair(press:press,release:releaseURL,name:press.deletingPathExtension().lastPathComponent,root:directory)
                DispatchQueue.main.async {
                    self.settings.imports.append(imported)
                    if target == "Mouse" { self.settings.sound.mouse = imported.id } else { self.settings.sound.enter = imported.id }
                }
            } catch { DispatchQueue.main.async { self.error = error.localizedDescription } }
        }
    }
    func chooseAIFolder() {
        let panel = NSOpenPanel(); panel.title = "Choose a folder of code to type along from"; panel.canChooseDirectories = true; panel.canChooseFiles = false; panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url { settings.aiFolder = url.path }
    }
    func demoVisualizer() {
        settings.visualizer.enabled = true
        for (i,key) in [0,1,2,3].enumerated() {
            DispatchQueue.main.asyncAfter(deadline:.now()+Double(i)*0.15) {
                self.receive(.init(key:key,transition:.press,modifiers:0,timestamp:ProcessInfo.processInfo.systemUptime))
                DispatchQueue.main.asyncAfter(deadline:.now()+0.1) { self.visualize(.init(key:key,transition:.release,modifiers:0,timestamp:ProcessInfo.processInfo.systemUptime)) }
            }
        }
    }
}
