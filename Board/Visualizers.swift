import SwiftUI
import AppKit

struct KeyboardView: View {
    var layout: String
    var held: Set<Int> = []
    var selected: Int? = nil
    var theme = "Dark"
    var accent: Accent
    var sound: SoundConfiguration? = nil
    var releases: [Int:TimeInterval] = [:]
    var motion: VisualizerMotion = .pop
    var action: ((Int) -> Void)? = nil
    private var light: Bool { theme == "Light" || theme == "Glass Clear" }
    var body: some View {
        GeometryReader { geo in
            let unit = geo.size.width/15
            let rowHeight = geo.size.height/6
            ZStack(alignment:.topLeading) {
                RoundedRectangle(cornerRadius:8).fill(light ? Color.white.opacity(theme.hasPrefix("Glass") ? 0.45 : 0.9) : Color.black.opacity(theme.hasPrefix("Glass") ? 0.4 : 0.85))
                ForEach(KeyGeometry.keys(layout)) { key in
                    let active = held.contains(key.id) || selected == key.id
                    let profile = sound.flatMap { SoundProfile.find($0.overrides[key.id]?.profile ?? $0.profile) }
                    let face = KeyFace(label:key.label,active:active,light:light,accent:accent,unit:unit,width:unit*key.width-3,height:rowHeight*key.height-3,stem:profile?.color,releasedAt:releases[key.id])
                        .modifier(VisualArrival(trigger:active ? 1 : 0,motion:motion,enabled:active && sound != nil))
                    Group {
                        if let action { Button { action(key.id) } label: { face }.buttonStyle(.plain).accessibilityLabel("\(KeyGeometry.label(key.id)), physical key \(key.id)").accessibilityAddTraits(selected == key.id ? .isSelected : []) }
                        else { face.accessibilityHidden(true) }
                    }.position(x:unit*(key.x+key.width/2),y:rowHeight*(Double(key.row)+key.height/2))
                }
            }
        }
    }
}
struct KeyFace: View {
    let label: String
    let active: Bool
    let light: Bool
    let accent: Accent
    let unit: Double
    let width: Double
    let height: Double
    var stem: String? = nil
    var releasedAt: TimeInterval? = nil
    var body: some View {
        let background: Color = active ? stem.map { Color(hex:$0) } ?? accent.fill(light:light) : (light ? .black.opacity(0.055) : .white.opacity(0.12))
        let foreground: Color = active ? stem.map(stemText) ?? accent.text(light:light) : (light ? .black.opacity(0.75) : .white.opacity(0.9))
        Text(label)
            .font(.system(size:max(5,min(11,unit*0.3)),weight:.medium,design:.rounded))
            .frame(width:max(2,width),height:max(2,height))
            .background(background,in:RoundedRectangle(cornerRadius:3))
            .background {
                if let releasedAt, !active {
                    KeyAfterglow(time:releasedAt,color:stem.map { Color(hex:$0) } ?? accent.fill(light:light))
                }
            }
            .foregroundStyle(foreground)
            .overlay(RoundedRectangle(cornerRadius:3).stroke(.primary.opacity(0.07)))
    }
}

private func stemText(_ hex: String) -> Color {
    let value = UInt64(hex,radix:16) ?? 0
    let brightness = (Double((value>>16)&255)*0.2126 + Double((value>>8)&255)*0.7152 + Double(value&255)*0.0722)/255
    return brightness > 0.55 ? .black.opacity(0.85) : .white
}

private struct KeyAfterglow: View {
    let time: TimeInterval
    let color: Color
    @State private var faded = false
    var body: some View {
        let remaining = max(0,VisualizerTrail.afterglow-(ProcessInfo.processInfo.systemUptime-time))
        RoundedRectangle(cornerRadius:3).fill(color)
            .opacity(faded ? 0 : 0.65*remaining/VisualizerTrail.afterglow)
            .task(id:time) {
                var transaction = Transaction(); transaction.disablesAnimations = true
                withTransaction(transaction) { faded = false }
                await Task.yield()
                guard !Task.isCancelled else { return }
                withAnimation(.easeOut(duration:remaining)) { faded = true }
            }
    }
}

private struct VisualArrival: ViewModifier {
    let trigger: Int
    let motion: VisualizerMotion
    var enabled = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var settled = true
    func body(content: Content) -> some View {
        content
            .scaleEffect(settled || reduceMotion || !enabled ? 1 : motion.arrivalScale)
            .offset(x:settled || reduceMotion || !enabled ? 0 : motion.arrivalX,y:settled || reduceMotion || !enabled ? 0 : motion.arrivalY)
            .opacity(settled || !enabled ? 1 : 0.65)
            .task(id:trigger) {
                guard enabled else { return }
                var transaction = Transaction(); transaction.disablesAnimations = true
                withTransaction(transaction) { settled = false }
                await Task.yield()
                guard !Task.isCancelled else { return }
                withAnimation(reduceMotion ? .easeOut(duration:0.2) : .spring(response:0.32,dampingFraction:motion == .bounce ? 0.5 : 0.85)) { settled = true }
            }
    }
}

struct KeystrokeCap: View {
    let stroke: KeystrokeVisual
    let color: String
    let progress: Double
    let float: Bool
    let reduceMotion: Bool
    let light: Bool
    var body: some View {
        Text(stroke.label).font(.system(size:14,weight:.semibold,design:.rounded))
            .lineLimit(1).minimumScaleFactor(0.5)
            .frame(width:44,height:34)
            .foregroundStyle(light ? Color.black.opacity(0.85) : .white)
            .background(light ? Color.white.opacity(0.94) : Color(white:0.12).opacity(0.94),in:RoundedRectangle(cornerRadius:8))
            .overlay(RoundedRectangle(cornerRadius:8).stroke(Color(hex:color).opacity(0.85),lineWidth:1.5))
            .overlay(alignment:.bottom) { Capsule().fill(Color(hex:color)).frame(width:14,height:2).padding(.bottom,3) }
            .scaleEffect(reduceMotion ? 1 : 1-0.24*progress)
            .blur(radius:reduceMotion ? 0 : 1.5*progress*progress)
            .opacity(max(0,1-progress))
            .offset(x:float && !reduceMotion ? KeyGeometry.position(stroke.key,layout:"ANSI")*12*progress : 0,y:float && !reduceMotion ? -155*progress : 0)
    }
}

private struct FadingKeystroke: View {
    let stroke: KeystrokeVisual
    let color: String
    let settings: VisualizerSettings
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    // Seeds an animation's starting age; subsequent repeats restart it through the task.
    @State private var progress: Double
    init(stroke: KeystrokeVisual, color: String, settings: VisualizerSettings) {
        self.stroke = stroke; self.color = color; self.settings = settings
        _progress = State(initialValue:min(1,max(0,(ProcessInfo.processInfo.systemUptime-stroke.time)/VisualizerTrail.lifetime)))
    }
    var body: some View {
        KeystrokeCap(stroke:stroke,color:color,progress:progress,float:settings.movement == .float,reduceMotion:reduceMotion,light:settings.theme == "Light" || settings.theme == "Glass Clear")
            .modifier(VisualArrival(trigger:stroke.count,motion:settings.movement))
            .task(id:stroke.time) {
                let age = min(1,max(0,(ProcessInfo.processInfo.systemUptime-stroke.time)/VisualizerTrail.lifetime))
                var transaction = Transaction(); transaction.disablesAnimations = true
                withTransaction(transaction) { progress = age }
                await Task.yield()
                guard !Task.isCancelled else { return }
                withAnimation(.easeIn(duration:VisualizerTrail.lifetime*(1-age))) { progress = 1 }
            }
    }
}

private struct KeystrokeRibbon: View {
    @ObservedObject var app: AppState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        let settings = app.settings.visualizer
        let floating = settings.movement == .float && !reduceMotion
        let column = settings.flow == "Column" && settings.movement != .float
        let layout = floating ? AnyLayout(ZStackLayout()) : (column ? AnyLayout(VStackLayout(spacing:6)) : AnyLayout(HStackLayout(spacing:6)))
        layout {
            ForEach(app.visualTrail.strokes) { stroke in
                let profile = SoundProfile.find(app.settings.sound.overrides[stroke.key]?.profile ?? app.settings.sound.profile) ?? app.selectedProfile
                FadingKeystroke(stroke:stroke,color:profile.color,settings:settings)
                    .offset(x:floating ? KeyGeometry.position(stroke.key,layout:app.settings.layout)*300 : 0,y:floating ? 80 : 0)
                    .transition(.opacity)
            }
        }
        .animation(reduceMotion ? nil : .easeOut(duration:0.18),value:app.visualTrail.strokes.map(\.id))
        .padding(12)
    }
}

struct OverlayContent: View {
    @ObservedObject var app: AppState
    private var comboColor: Color { app.settings.visualizer.comboTheme == "Amber" ? .orange : (app.settings.visualizer.comboTheme == "Neon" ? .mint : .white) }
    private var baseSize: CGSize { app.settings.visualizer.panelSize }
    var body: some View {
        GeometryReader { geometry in
            if app.settings.visualizer.style == "Bezel" { BezelView(count:app.combo.count,color:Color(hex:app.selectedProfile.color)).modifier(VisualArrival(trigger:app.combo.totalPresses,motion:app.settings.visualizer.movement)) }
            else {
                let size = baseSize
                let scale = min(geometry.size.width/size.width,geometry.size.height/size.height)
                content.frame(width:size.width,height:size.height).scaleEffect(scale).position(x:geometry.size.width/2,y:geometry.size.height/2)
            }
        }
    }
    private var content: some View {
        Group {
            switch app.settings.visualizer.style {
            case "Combo":
                VStack(spacing:0) { Text("\(app.combo.count)").font(.system(size:70,weight:.black,design:.rounded)).foregroundStyle(comboColor).shadow(color:comboColor.opacity(0.6),radius:app.settings.visualizer.comboTheme == "Neon" ? 18 : 4); Text("COMBO").font(.system(size:12,weight:.heavy,design:.rounded)).tracking(5).foregroundStyle(comboColor.opacity(0.9)) }.padding(20).background(.black.opacity(0.78),in:RoundedRectangle(cornerRadius:25)).overlay(RoundedRectangle(cornerRadius:25).stroke(comboColor.opacity(0.6),lineWidth:2))
            case "Keystrokes":
                KeystrokeRibbon(app:app)
            default: KeyboardView(layout:app.settings.layout,held:app.heldKeys,theme:app.settings.visualizer.theme,accent:app.accent,sound:app.settings.sound,releases:app.visualTrail.releases,motion:app.settings.visualizer.movement).padding(8).background(.ultraThinMaterial,in:RoundedRectangle(cornerRadius:14))
            }
        }.modifier(VisualArrival(trigger:app.combo.totalPresses,motion:app.settings.visualizer.movement,enabled:app.settings.visualizer.style == "Combo"))
    }
}
struct BezelView: View {
    let count: Int
    let color: Color
    var body: some View {
        GeometryReader { geo in
            ZStack {
                RoundedRectangle(cornerRadius:18).stroke(color.opacity(0.6),lineWidth:4).blur(radius:4)
                Canvas { context,size in
                    context.addFilter(.alphaThreshold(min:0.45,color:color))
                    context.addFilter(.blur(radius:12))
                    context.drawLayer { layer in
                        for i in 0..<6 {
                            let x = (Double((count*37+i*157)%997)/997)*size.width
                            let y = i%2 == 0 ? 0.0 : size.height
                            layer.fill(Path(ellipseIn:CGRect(x:x-26,y:y-26,width:52,height:52)),with:.color(.white))
                        }
                        layer.stroke(Path(roundedRect:CGRect(origin:.zero,size:size).insetBy(dx:3,dy:3),cornerRadius:18),with:.color(.white),lineWidth:8)
                    }
                }
            }.frame(width:geo.size.width,height:geo.size.height)
        }
    }
}
final class PassivePanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
@MainActor final class OverlayController {
    private let app: AppState
    private let panel: PassivePanel
    private var timer: Timer?
    private var dismissal: DispatchWorkItem?
    private var comboExpiry: DispatchWorkItem?
    private var screenObserver: NSObjectProtocol?
    private var spaceObserver: NSObjectProtocol?
    private var randomOrigin: NSPoint?
    private var currentScreenID: String?
    init(app: AppState) {
        self.app = app
        panel = Self.makePanel()
        panel.contentView = NSHostingView(rootView:OverlayContent(app:app))
        app.onVisualEvent = { [weak self] shuffle in self?.show(shuffle:shuffle) }
        app.onVisualReset = { [weak self] in self?.hide() }
        screenObserver = NotificationCenter.default.addObserver(forName:NSApplication.didChangeScreenParametersNotification,object:nil,queue:.main) { [weak self] _ in MainActor.assumeIsolated { self?.randomOrigin = nil; self?.updatePosition() } }
        spaceObserver = NSWorkspace.shared.notificationCenter.addObserver(forName:NSWorkspace.activeSpaceDidChangeNotification,object:nil,queue:.main) { [weak self] _ in MainActor.assumeIsolated { self?.hide() } }
    }
    static func makePanel() -> PassivePanel {
        let panel = PassivePanel(contentRect:.zero,styleMask:[.borderless,.nonactivatingPanel],backing:.buffered,defer:false)
        panel.level = .statusBar; panel.isOpaque = false; panel.backgroundColor = .clear; panel.hasShadow = false; panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces,.fullScreenAuxiliary,.stationary,.ignoresCycle]
        panel.isReleasedWhenClosed = false
        return panel
    }
    private var screen: NSScreen? { NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation,$0.frame,false) } ?? NSScreen.main ?? NSScreen.screens.first }
    func preferencesChanged() {
        if app.settings.visualizer.placement != "Follow Cursor" { timer?.invalidate(); timer = nil }
        if !app.settings.visualizer.enabled || !app.settings.enabled { hide() }
        else if panel.isVisible { updatePosition() }
    }
    func show(shuffle: Bool) {
        guard app.settings.visualizer.enabled, app.settings.enabled else { return }
        if shuffle { randomOrigin = nil }
        updatePosition()
        panel.orderFrontRegardless()
        dismissal?.cancel()
        let task = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.timer?.invalidate(); self.timer = nil
            if !(self.app.settings.visualizer.style == "Combo" && self.app.settings.visualizer.keepComboVisible) { self.panel.orderOut(nil); self.app.clearVisualTail() }
        }
        dismissal = task; DispatchQueue.main.asyncAfter(deadline:.now()+max(app.settings.visualizer.dismiss,app.settings.visualizer.tailDuration),execute:task)
        comboExpiry?.cancel()
        let expiry = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.app.combo.expire(at:ProcessInfo.processInfo.systemUptime,settings:self.app.settings.visualizer)
        }
        comboExpiry = expiry
        DispatchQueue.main.asyncAfter(deadline:.now()+app.settings.visualizer.comboReset,execute:expiry)
        if app.settings.visualizer.placement == "Follow Cursor", timer == nil {
            timer = Timer(timeInterval:1/60,repeats:true) { [weak self] _ in MainActor.assumeIsolated { self?.updatePosition() } }
            RunLoop.main.add(timer!,forMode:.common)
        }
    }
    func hide() { dismissal?.cancel(); comboExpiry?.cancel(); timer?.invalidate(); timer = nil; panel.orderOut(nil); app.heldKeys.removeAll(); app.clearVisualTail() }
    private func updatePosition() {
        guard let screen else { return }
        let settings = app.settings.visualizer
        if settings.style == "Bezel" { panel.setFrame(screen.frame,display:true); return }
        let base = settings.panelSize
        let bounds = screen.visibleFrame.insetBy(dx:12,dy:12)
        let size = NSSize(width:min(bounds.width,base.width*settings.scale),height:min(bounds.height,base.height*settings.scale))
        panel.contentView?.wantsLayer = true
        var origin = NSEvent.mouseLocation
        let id = String(describing:screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")])
        if currentScreenID != id { currentScreenID = id; randomOrigin = nil }
        if settings.placement == "Pin to Screen" {
            origin.x = settings.pin.hasSuffix("Left") ? bounds.minX : (settings.pin.hasSuffix("Right") ? bounds.maxX-size.width : bounds.midX-size.width/2)
            origin.y = settings.pin.hasPrefix("Top") ? bounds.maxY-size.height : bounds.minY
        } else if settings.placement == "Random" {
            if randomOrigin == nil { randomOrigin = NSPoint(x:Double.random(in:bounds.minX...max(bounds.minX,bounds.maxX-size.width)),y:Double.random(in:bounds.minY...max(bounds.minY,bounds.maxY-size.height))) }
            origin = randomOrigin!
        } else { origin.x += settings.offset; origin.y -= size.height+settings.offset }
        origin.x = min(max(bounds.minX,origin.x),bounds.maxX-size.width); origin.y = min(max(bounds.minY,origin.y),bounds.maxY-size.height)
        let frame = NSRect(origin:origin,size:size)
        guard frame != panel.frame else { return }
        panel.setFrame(frame,display:true)
    }
}
