import SwiftUI

@main struct BoardApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    var body: some Scene { Settings { EmptyView() } }
}
final class ActionMenuItem: NSMenuItem {
    var handler: (() -> Void)?
    init(_ title: String,key: String = "",handler:@escaping () -> Void) {
        self.handler = handler; super.init(title:title,action:#selector(activate),keyEquivalent:key); target = self
    }
    required init(coder:NSCoder) { fatalError("Not used") }
    @objc func activate() { handler?() }
}
@MainActor final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    let state = AppState()
    private var status: NSStatusItem?
    private var settingsWindow: NSWindow?
    private var practiceWindow: PracticeWindowController?
    private var overlays: OverlayController?
    private var menu = NSMenu()
    private var previewTask: DispatchWorkItem?
    private var previousDock: Bool?
    private var appliedIcon: String?
    func applicationDidFinishLaunching(_ notification:Notification) {
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil { return }
        NSApp.setActivationPolicy(.accessory)
        let appMenu = NSMenu(); let appItem = NSMenuItem(); appMenu.addItem(appItem)
        let main = NSMenu(); main.addItem(practiceMenuItem()); main.addItem(ActionMenuItem("Settings…",key:",") { [weak self] in self?.showSettings() }); main.addItem(.separator()); main.addItem(ActionMenuItem("Quit Board",key:"q") { NSApp.terminate(nil) }); appItem.submenu = main
        let fileItem = NSMenuItem(title:"File",action:nil,keyEquivalent:"")
        let fileMenu = NSMenu(title:"File")
        fileMenu.addItem(NSMenuItem(title:"Close Window",action:#selector(NSWindow.performClose(_:)),keyEquivalent:"w"))
        fileItem.submenu = fileMenu; appMenu.addItem(fileItem); NSApp.mainMenu = appMenu
        let edit = NSMenu(title:"Edit"), editItem = NSMenuItem(title:"Edit",action:nil,keyEquivalent:"")
        for (title, action, key) in [("Cut",#selector(NSText.cut(_:)),"x"),("Copy",#selector(NSText.copy(_:)),"c"),("Paste",#selector(NSText.paste(_:)),"v"),("Select All",#selector(NSText.selectAll(_:)),"a")] {
            edit.addItem(NSMenuItem(title:title,action:action,keyEquivalent:key))
        }
        editItem.submenu = edit; appMenu.addItem(editItem)
        overlays = OverlayController(app:state)
        state.showSettings = { [weak self] in self?.showSettings() }
        state.onPreferences = { [weak self] in self?.applyPreferences() }
        state.start(); applyPreferences()
        if Self.opensSettingsAtLaunch(onboardingComplete:state.settings.onboardingComplete,inputAllowed:CGPreflightListenEventAccess()) { showSettings() }
    }
    // A launch opens no window (login items and `open -g` start Board in the background), except to finish onboarding or to ask for Input Monitoring.
    nonisolated static func opensSettingsAtLaunch(onboardingComplete:Bool,inputAllowed:Bool) -> Bool { !onboardingComplete || !inputAllowed }
    // Opening Board again while it runs is the way into Settings only when no icon offers one; otherwise it does nothing.
    nonisolated static func opensSettingsOnReopen(showMenu:Bool,showDock:Bool) -> Bool { !showMenu && !showDock }
    func applicationShouldHandleReopen(_ sender:NSApplication,hasVisibleWindows:Bool) -> Bool {
        guard Self.opensSettingsOnReopen(showMenu:state.settings.showMenu,showDock:state.settings.showDock) else { return false }
        showSettings(); return true
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender:NSApplication) -> Bool { false }
    func applicationWillTerminate(_ notification:Notification) { state.audio.reset(); state.ai.stop() }
    func applyPreferences() {
        if previousDock != state.settings.showDock { NSApp.setActivationPolicy(state.settings.showDock ? .regular : .accessory); previousDock = state.settings.showDock; appliedIcon = nil }
        // applicationIconImage only overrides the running app's Dock tile; nil restores the bundled Porcelain icon.
        if appliedIcon != (state.settings.iconColor ?? "Porcelain") { NSApp.applicationIconImage = state.settings.iconColor.flatMap { state.iconImages[$0] }; appliedIcon = state.settings.iconColor ?? "Porcelain" }
        if state.settings.showMenu, status == nil {
            status = NSStatusBar.system.statusItem(withLength:NSStatusItem.squareLength)
            let image = NSImage(contentsOf:state.resources.appendingPathComponent("MenuIcon.pdf")) ?? NSImage(systemSymbolName:"keyboard",accessibilityDescription:"Board")!
            image.isTemplate = true; image.size = NSSize(width:18,height:18)
            status?.button?.image = image; status?.button?.setAccessibilityLabel("Board menu")
            menu.delegate = self; status?.menu = menu
        } else if !state.settings.showMenu, let status { NSStatusBar.system.removeStatusItem(status); self.status = nil }
        status?.button?.appearsDisabled = !state.settings.enabled || state.settings.muted
        overlays?.preferencesChanged()
    }
    func showSettings() {
        if settingsWindow == nil {
            // Full-size content lets the sidebar run to the top with the window buttons inside it, like other Mac apps.
            let window = NSWindow(contentRect:NSRect(x:0,y:0,width:890,height:740),styleMask:[.titled,.closable,.miniaturizable,.resizable,.fullSizeContentView],backing:.buffered,defer:false)
            window.titlebarAppearsTransparent = true; window.titleVisibility = .hidden
            window.toolbar = NSToolbar(identifier:"Settings"); window.toolbarStyle = .unified
            window.title = "Board — Settings"; window.contentView = NSHostingView(rootView:SettingsView(app:state)); window.isReleasedWhenClosed = false
            window.minSize = NSSize(width:850,height:650); settingsWindow = window
        }
        settingsWindow?.center(); settingsWindow?.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps:true)
    }
    private func practiceMenuItem() -> NSMenuItem {
        let item = ActionMenuItem("Practice…",key:"p") { [weak self] in
            guard let self else { return }
            if practiceWindow == nil { practiceWindow = PracticeWindowController(app:state) }
            practiceWindow?.open()
        }
        item.keyEquivalentModifierMask = [.command,.shift]
        return item
    }
    func menuNeedsUpdate(_ menu:NSMenu) { if menu === self.menu { buildMenu() } }
    func menu(_ menu:NSMenu,willHighlight item:NSMenuItem?) {
        previewTask?.cancel(); state.audio.cancelPreview()
        guard let identity = item?.representedObject as? String else { return }
        let task = DispatchWorkItem { [weak self] in
            if identity.hasPrefix("effect:") {
                let parts = identity.split(separator:":",maxSplits:2).map(String.init)
                guard parts.count == 3 else { return }
                self?.state.audio.preview(effect:parts[2],key:parts[1] == "Mouse" ? 1000 : 36)
            } else if SoundProfile.find(identity) != nil { self?.state.audio.preview(profile:identity) }
        }
        previewTask = task; DispatchQueue.main.asyncAfter(deadline:.now()+0.12,execute:task)
    }
    func menuDidClose(_ menu:NSMenu) { previewTask?.cancel(); state.audio.cancelPreview() }
    private func toggle(_ title:String,on:Bool,action:@escaping () -> Void) -> NSMenuItem {
        let item = ActionMenuItem(title,handler:action); item.state = on ? .on : .off; return item
    }
    private func submenu(_ title:String,in parent:NSMenu) -> NSMenu {
        let menu = NSMenu(title:title); menu.delegate = self; menu.minimumWidth = 260; menu.autoenablesItems = false
        let item = NSMenuItem(title:title,action:nil,keyEquivalent:""); item.submenu = menu; parent.addItem(item); return menu
    }
    private func addVolume(to menu:NSMenu,value:Double,action:Selector,label:String) {
        let item = NSMenuItem(); let view = NSView(frame:NSRect(x:0,y:0,width:260,height:38))
        let slider = NSSlider(value:value,minValue:0,maxValue:1,target:self,action:action); slider.frame = NSRect(x:14,y:7,width:230,height:24); slider.setAccessibilityLabel(label)
        view.addSubview(slider); item.view = view; menu.addItem(item)
    }
    @objc private func typingVolume(_ sender:NSSlider) { state.settings.sound.volume = sender.doubleValue }
    @objc private func mouseVolume(_ sender:NSSlider) { state.settings.sound.mouseVolume = sender.doubleValue }
    @objc private func enterVolume(_ sender:NSSlider) { state.settings.sound.enterVolume = sender.doubleValue }
    private func buildMenu() {
        menu.removeAllItems(); menu.minimumWidth = 270
        menu.addItem(toggle("Enable Board",on:state.settings.enabled) { [weak self] in self?.state.toggle() })
        menu.addItem(toggle("Mute Sounds",on:state.settings.muted) { [weak self] in self?.state.settings.muted.toggle() })
        addVolume(to:menu,value:state.settings.sound.volume,action:#selector(typingVolume),label:"Typing volume")
        menu.addItem(.separator())
        let profiles = submenu("Switches · \(state.selectedProfile.name)",in:menu)
        var group = ""
        for profile in SoundProfile.catalog {
            if profile.manufacturer != group { if !group.isEmpty { profiles.addItem(.separator()) }; let heading = NSMenuItem.sectionHeader(title:profile.manufacturer); profiles.addItem(heading); group = profile.manufacturer }
            let item = toggle(profile.name,on:state.settings.sound.profile == profile.id) { [weak self] in self?.state.select(profile) }
            item.representedObject = profile.id
            let image = NSImage(size:NSSize(width:16,height:16),flipped:false) { rect in
                NSColor(Color(hex:profile.color)).setFill(); NSBezierPath(roundedRect:rect.insetBy(dx:1,dy:1),xRadius:3,yRadius:3).fill()
                NSColor.white.setStroke(); let p = NSBezierPath(); p.lineWidth = 2; p.move(to:NSPoint(x:8,y:4)); p.line(to:NSPoint(x:8,y:12)); p.move(to:NSPoint(x:4,y:8)); p.line(to:NSPoint(x:12,y:8)); p.stroke(); return true
            }; item.image = image; profiles.addItem(item)
        }
        for name in ["Mouse","Enter"] {
            let effects = submenu(name+" Sound",in:menu)
            let current = name == "Mouse" ? state.settings.sound.mouse : state.settings.sound.enter
            for (id,label) in [("none","None"),("default","Default · keyboard profile")]+state.settings.imports.map({($0.id,$0.name)}) {
                let item = toggle(label,on:current == id) { [weak self, weak effects] in
                    guard let self else { return }
                    if name == "Mouse" { state.settings.sound.mouse = id } else { state.settings.sound.enter = id }
                    for option in effects?.items ?? [] {
                        let selected = option.representedObject as? String == "effect:"+name+":"+id
                        option.state = selected ? .on : .off
                        (option.view?.subviews.first as? NSButton)?.state = option.state
                    }
                    state.audio.preview(effect:id,key:name == "Mouse" ? 1000 : 36)
                }
                item.representedObject = "effect:"+name+":"+id
                let row = NSView(frame:NSRect(x:0,y:0,width:260,height:28))
                let button = NSButton(checkboxWithTitle:label,target:item,action:#selector(ActionMenuItem.activate))
                button.frame = NSRect(x:14,y:2,width:232,height:24); button.state = item.state
                button.setAccessibilityLabel("\(name) sound: \(label)")
                row.addSubview(button); item.view = row
                effects.addItem(item)
            }
            addVolume(to:effects,value:name == "Mouse" ? state.settings.sound.mouseVolume : state.settings.sound.enterVolume,action:name == "Mouse" ? #selector(mouseVolume) : #selector(enterVolume),label:name+" volume")
            effects.addItem(ActionMenuItem("Import sound…") { [weak self] in self?.state.importSound(target:name,pair:false) })
        }
        let favorites = submenu("Favorites",in:menu)
        for preset in state.settings.presets { favorites.addItem(ActionMenuItem(preset.name) { [weak self] in self?.state.settings.sound = preset.sound }) }
        favorites.addItem(ActionMenuItem("Save current configuration") { [weak self] in self?.state.savePreset(name:"") }); favorites.items.last?.isEnabled = state.settings.presets.count < 6
        menu.addItem(.separator())
        let visual = submenu("Visualizer",in:menu)
        visual.addItem(toggle("Enabled",on:state.settings.visualizer.enabled) { [weak self] in self?.state.settings.visualizer.enabled.toggle() })
        for style in ["Keyboard","Keystrokes","Combo","Bezel"] { visual.addItem(toggle(style,on:state.settings.visualizer.style == style) { [weak self] in self?.state.settings.visualizer.style = style; self?.state.settings.visualizer.enabled = true }) }
        let position = submenu("Position",in:menu)
        for place in ["Follow Cursor","Random"] { position.addItem(toggle(place,on:state.settings.visualizer.placement == place) { [weak self] in self?.state.settings.visualizer.placement = place; self?.state.settings.visualizer.enabled = true }) }
        position.addItem(.separator()); position.addItem(NSMenuItem.sectionHeader(title:"Pin to Screen"))
        for pin in ["Top Left","Top Center","Top Right","Bottom Left","Bottom Center","Bottom Right"] { position.addItem(toggle(pin,on:state.settings.visualizer.placement == "Pin to Screen" && state.settings.visualizer.pin == pin) { [weak self] in self?.state.settings.visualizer.pin = pin; self?.state.settings.visualizer.placement = "Pin to Screen"; self?.state.settings.visualizer.enabled = true }) }
        menu.addItem(.separator())
        menu.addItem(practiceMenuItem())
        menu.addItem(ActionMenuItem("Settings…",key:",") { [weak self] in self?.showSettings() })
        menu.addItem(ActionMenuItem("About Board") { [weak self] in self?.state.selectedSettingsSection = .about; self?.showSettings() })
        menu.addItem(ActionMenuItem("Quit Board",key:"q") { NSApp.terminate(nil) })
    }
}
