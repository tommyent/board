import SwiftUI
import AppKit

struct KeyboardView: View {
    var layout: String
    var held: Set<Int> = []
    var selected: Int? = nil
    var theme = "Dark"
    var accent: Accent
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
                    let face = KeyFace(label:key.label,active:active,light:light,accent:accent,unit:unit,width:unit*key.width-3,height:rowHeight*key.height-3)
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
    var body: some View {
        let background: Color = active ? accent.fill(light:light) : (light ? .black.opacity(0.055) : .white.opacity(0.12))
        let foreground: Color = active ? accent.text(light:light) : (light ? .black.opacity(0.75) : .white.opacity(0.9))
        Text(label)
            .font(.system(size:max(5,min(11,unit*0.3)),weight:.medium,design:.rounded))
            .frame(width:max(2,width),height:max(2,height))
            .background(background,in:RoundedRectangle(cornerRadius:3))
            .foregroundStyle(foreground)
            .overlay(RoundedRectangle(cornerRadius:3).stroke(.primary.opacity(0.07)))
    }
}
struct OverlayContent: View {
    @ObservedObject var app: AppState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var comboColor: Color { app.settings.visualizer.comboTheme == "Amber" ? .orange : (app.settings.visualizer.comboTheme == "Neon" ? .mint : .white) }
    private var baseSize: CGSize {
        switch app.settings.visualizer.style {
        case "Combo": return CGSize(width:210,height:170)
        case "Keystrokes": return app.settings.visualizer.flow == "Column" ? CGSize(width:180,height:330) : CGSize(width:540,height:80)
        default: return CGSize(width:420,height:170)
        }
    }
    var body: some View {
        GeometryReader { geometry in
            if app.settings.visualizer.style == "Bezel" { BezelView(count:app.combo.count,color:app.accent.tint) }
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
                let column = app.settings.visualizer.flow == "Column"
                let layout = column ? AnyLayout(VStackLayout(spacing:8)) : AnyLayout(HStackLayout(spacing:8))
                layout {
                    ForEach(Array(app.pills.enumerated()),id:\.offset) { _, key in Text(key).font(.system(size:17,weight:.semibold,design:.rounded)).lineLimit(1).minimumScaleFactor(0.6).padding(.horizontal,13).padding(.vertical,10).background(.ultraThinMaterial,in:RoundedRectangle(cornerRadius:10)).overlay(RoundedRectangle(cornerRadius:10).stroke(.white.opacity(0.2))) }
                }.padding(8)
            case "Bezel": BezelView(count:app.combo.count,color:app.accent.tint)
            default: KeyboardView(layout:app.settings.layout,held:app.heldKeys,theme:app.settings.visualizer.theme,accent:app.accent).padding(8).background(.ultraThinMaterial,in:RoundedRectangle(cornerRadius:14))
            }
        }.animation(reduceMotion ? nil : .easeOut(duration:0.12),value:app.heldKeys)
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
            if !(self.app.settings.visualizer.style == "Combo" && self.app.settings.visualizer.keepComboVisible) { self.panel.orderOut(nil); self.app.pills.removeAll() }
        }
        dismissal = task; DispatchQueue.main.asyncAfter(deadline:.now()+app.settings.visualizer.dismiss,execute:task)
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
    func hide() { dismissal?.cancel(); comboExpiry?.cancel(); timer?.invalidate(); timer = nil; panel.orderOut(nil) }
    private func updatePosition() {
        guard let screen else { return }
        let settings = app.settings.visualizer
        if settings.style == "Bezel" { panel.setFrame(screen.frame,display:true); return }
        let base: NSSize
        switch settings.style { case "Combo":base = NSSize(width:210,height:170); case "Keystrokes":base = settings.flow == "Column" ? NSSize(width:180,height:330) : NSSize(width:540,height:80); default:base = NSSize(width:420,height:170) }
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
        let animate = panel.isVisible && settings.placement == "Random" && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        if animate, ["Slide","Bounce"].contains(settings.motion) {
            NSAnimationContext.runAnimationGroup { context in context.duration = settings.motion == "Bounce" ? 0.35 : 0.2; context.timingFunction = CAMediaTimingFunction(name:.easeOut); panel.animator().setFrame(frame,display:true) }
            if settings.motion == "Bounce" {
                let bounce = CAKeyframeAnimation(keyPath:"transform.translation.y")
                bounce.values = [0,-14,5,0]; bounce.keyTimes = [0,0.45,0.75,1]; bounce.duration = 0.35
                panel.contentView?.layer?.add(bounce,forKey:"arrival")
            }
        } else {
            panel.setFrame(frame,display:true)
            if animate, settings.motion == "Pulse" {
                let pulse = CAKeyframeAnimation(keyPath:"transform.scale")
                pulse.values = [0.9,1.06,1]; pulse.keyTimes = [0,0.5,1]; pulse.duration = 0.25
                panel.contentView?.layer?.add(pulse,forKey:"arrival")
            }
        }
    }
}
