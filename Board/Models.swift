import Foundation
import CoreGraphics

struct PhysicalInputEvent: Equatable {
    enum Transition: String, Codable { case press, release }
    let key: Int
    let transition: Transition
    let modifiers: UInt64
    let timestamp: TimeInterval
    var isMouse: Bool { (1000..<1100).contains(key) }
}

struct InputNormalizer {
    private(set) var held = Set<Int>()
    mutating func accept(key: Int, down: Bool, repeatEvent: Bool = false, modifiers: UInt64 = 0, time: TimeInterval) -> PhysicalInputEvent? {
        guard !repeatEvent else { return nil }
        if down { guard held.insert(key).inserted else { return nil } }
        else { guard held.remove(key) != nil else { return nil } }
        return PhysicalInputEvent(key: key, transition: down ? .press : .release, modifiers: modifiers, timestamp: time)
    }
    mutating func clear() { held.removeAll() }
}

struct KeyGeometry: Identifiable {
    var id: Int
    var label: String
    var x: Double
    var row: Int
    var width: Double = 1
    var height: Double = 1
    private static let layouts = ["ANSI":buildKeys("ANSI"),"ISO":buildKeys("ISO"),"JIS":buildKeys("JIS")]
    static func keys(_ layout:String = "ANSI") -> [KeyGeometry] { layouts[layout] ?? layouts["ANSI"]! }
    private static func buildKeys(_ layout: String) -> [KeyGeometry] {
        let rows: [[(Int, String, Double)]] = [
            [(53,"esc",1),(122,"F1",1),(120,"F2",1),(99,"F3",1),(118,"F4",1),(96,"F5",1),(97,"F6",1),(98,"F7",1),(100,"F8",1),(101,"F9",1),(109,"F10",1),(103,"F11",1),(111,"F12",1),(117,"del",2)],
            [(50,"`",1),(18,"1",1),(19,"2",1),(20,"3",1),(21,"4",1),(23,"5",1),(22,"6",1),(26,"7",1),(28,"8",1),(25,"9",1),(29,"0",1),(27,"−",1),(24,"=",1),(51,"⌫",2)],
            [(48,"⇥",1.5),(12,"Q",1),(13,"W",1),(14,"E",1),(15,"R",1),(17,"T",1),(16,"Y",1),(32,"U",1),(34,"I",1),(31,"O",1),(35,"P",1),(33,"[",1),(30,"]",1),(42,"\\",1.5)],
            [(57,"⇪",1.75),(0,"A",1),(1,"S",1),(2,"D",1),(3,"F",1),(5,"G",1),(4,"H",1),(38,"J",1),(40,"K",1),(37,"L",1),(41,";",1),(39,"'",1),(36,"↩",2.25)],
            [(56,"⇧",2.25),(6,"Z",1),(7,"X",1),(8,"C",1),(9,"V",1),(11,"B",1),(45,"N",1),(46,"M",1),(43,",",1),(47,".",1),(44,"/",1),(60,"⇧",1.75),(126,"↑",1)],
            [(63,"fn",1),(59,"⌃",1),(58,"⌥",1),(55,"⌘",1.5),(49,"space",4.5),(54,"⌘",1.5),(61,"⌥",1.5),(123,"←",1),(125,"↓",1),(124,"→",1)]
        ]
        var result = rows.enumerated().flatMap { row, keys -> [KeyGeometry] in
            var x = 0.0
            return keys.map { id, label, width in
                defer { x += width }
                return KeyGeometry(id: id, label: label, x: x, row: row, width: width)
            }
        }
        if layout == "ISO" {
            result.removeAll { $0.id == 42 }
            if let i = result.firstIndex(where: { $0.id == 36 }) { result[i].x = 13.5; result[i].row = 2; result[i].width = 1.5; result[i].height = 2 }
            if let i = result.firstIndex(where: { $0.id == 56 }) { result[i].width = 1.25 }
            result.append(KeyGeometry(id: 10, label: "§", x: 1.25, row: 4))
            result.append(KeyGeometry(id: 42, label: "\\", x: 12.75, row: 3, width: 0.75))
        }
        if layout == "JIS" {
            if let i = result.firstIndex(where: { $0.id == 51 }) { result[i].width = 1; result[i].x = 14 }
            result.append(KeyGeometry(id: 93, label: "¥", x: 13, row: 1))
            if let i = result.firstIndex(where: { $0.id == 60 }) { result[i].width = 0.75; result[i].x = 13.25 }
            result.append(KeyGeometry(id: 94, label: "_", x: 12.25, row: 4))
            if let i = result.firstIndex(where: { $0.id == 49 }) { result[i].x = 5.5; result[i].width = 2.5 }
            result.append(KeyGeometry(id: 102, label: "英数", x: 4.5, row: 5))
            result.append(KeyGeometry(id: 104, label: "かな", x: 8, row: 5))
        }
        return result
    }
    static let home: Set<Int> = [0,1,2,3,38,40,37,41]
    static let modifierKeys: Set<Int> = [54,55,56,57,58,59,60,61,62,63]
    static func label(_ key: Int) -> String {
        if key >= 2000 { return [2000:"Volume +",2001:"Volume −",2007:"Mute",2016:"Play",2017:"Next",2018:"Previous",2002:"Brightness +",2003:"Brightness −"][key] ?? "Media \(key-2000)" }
        if key >= 1000 { return [1000:"Left click",1001:"Right click",1002:"Middle click"][key] ?? "Mouse \(key-999)" }
        return keys("JIS").first { $0.id == key }?.label ?? [10:"§",62:"⌃",76:"⌤",71:"clear",81:"=",67:"×",75:"/",78:"−",69:"+",65:".",82:"0",83:"1",84:"2",85:"3",86:"4",87:"5",88:"6",89:"7",91:"8",92:"9"][key] ?? "Key \(key)"
    }
    static func position(_ key: Int, layout: String) -> Double {
        let geometry = keys(layout).first { $0.id == key }
        return geometry.map { (($0.x + $0.width/2) / 15 * 2 - 1) } ?? 0
    }
    static func sampleName(_ key: Int, down: Bool) -> String {
        if key == 49 { return "SPACE" }
        if key == 36 || key == 76 { return "ENTER" }
        if key == 51 || key == 117 { return "BACKSPACE" }
        guard down else { return "GENERIC" }
        // R0–R4 are physical rows, not five interchangeable recordings.
        let row = keys().first { $0.id == key }?.row ?? 3
        return "GENERIC_R\(min(4, max(0, row - 1)))"
    }
    static func chord(_ event: PhysicalInputEvent) -> String {
        let flags = CGEventFlags(rawValue: event.modifiers)
        if modifierKeys.contains(event.key) { return label(event.key) }
        let prefix = [(CGEventFlags.maskControl,"⌃"),(.maskAlternate,"⌥"),(.maskShift,"⇧"),(.maskCommand,"⌘")].filter { flags.contains($0.0) }.map { $0.1 }.joined()
        return prefix.isEmpty ? label(event.key) : prefix + " " + label(event.key)
    }
}

struct SoundProfile: Identifiable, Codable, Hashable {
    let id: String
    let manufacturer: String
    let name: String
    let color: String
    var hasReleaseSamples = true
    var title: String { manufacturer + " · " + name }
    static let catalog: [SoundProfile] = [
        .init(id:"typewriter",manufacturer:"Classic",name:"Typewriter",color:"BAA58B",hasReleaseSamples:false),
        .init(id:"alpaca",manufacturer:"Durock",name:"Alpaca",color:"E5A4B1"),
        .init(id:"blackink",manufacturer:"Gateron",name:"Ink Black",color:"42434C"),
        .init(id:"redink",manufacturer:"Gateron",name:"Ink Red",color:"CD5051"),
        .init(id:"turquoise",manufacturer:"Gateron",name:"Turquoise Tealios",color:"65C9C6"),
        .init(id:"cream",manufacturer:"NovelKeys",name:"Cream",color:"EEDBB2"),
        .init(id:"holypanda",manufacturer:"Drop",name:"Holy Panda",color:"ECAE5B"),
        .init(id:"boxnavy",manufacturer:"Kailh",name:"Box Navy",color:"5371A0"),
        .init(id:"buckling",manufacturer:"IBM",name:"Buckling Spring",color:"A7A5A0"),
        .init(id:"topre",manufacturer:"Topre",name:"Classic",color:"9C85BD"),
        .init(id:"bluealps",manufacturer:"Alps",name:"SKCM Blue",color:"6FA8D5"),
    ]
    static func find(_ id: String) -> SoundProfile? { catalog.first { $0.id == id } }
}

struct KeyOverride: Codable, Equatable {
    var profile: String? = nil
    var tone: Double? = nil
    var pitch: Double? = nil
    var volume: Double? = nil
}
struct ImportedSound: Codable, Equatable, Identifiable {
    var id: String
    var name: String
    var press: String
    var release: String?
}
struct SoundConfiguration: Codable, Equatable {
    var profile = "alpaca"
    var volume = 0.35
    var mouseVolume = 0.25
    var enterVolume = 0.35
    var mouse = "default"
    var enter = "none"
    var tone = 0.0
    var pitch = 0.0
    var variation = true
    var homeSoftness = 0.2
    var normalization = true
    var spatial = true
    var width = 1.0
    var headTracking = false
    var orbit = false
    var overrides: [Int: KeyOverride] = [:]
    private enum CodingKeys: String, CodingKey {
        case profile, volume, mouseVolume, enterVolume, mouse, enter, tone, pitch, variation, homeSoftness, normalization, spatial, width, headTracking, orbit, overrides
    }
    init() {}
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy:CodingKeys.self)
        profile = try c.decodeIfPresent(String.self,forKey:.profile) ?? profile
        volume = try c.decodeIfPresent(Double.self,forKey:.volume) ?? volume
        mouseVolume = try c.decodeIfPresent(Double.self,forKey:.mouseVolume) ?? mouseVolume
        enterVolume = try c.decodeIfPresent(Double.self,forKey:.enterVolume) ?? enterVolume
        mouse = try c.decodeIfPresent(String.self,forKey:.mouse) ?? mouse
        enter = try c.decodeIfPresent(String.self,forKey:.enter) ?? enter
        tone = try c.decodeIfPresent(Double.self,forKey:.tone) ?? tone
        pitch = try c.decodeIfPresent(Double.self,forKey:.pitch) ?? pitch
        variation = try c.decodeIfPresent(Bool.self,forKey:.variation) ?? variation
        homeSoftness = try c.decodeIfPresent(Double.self,forKey:.homeSoftness) ?? homeSoftness
        normalization = try c.decodeIfPresent(Bool.self,forKey:.normalization) ?? normalization
        spatial = try c.decodeIfPresent(Bool.self,forKey:.spatial) ?? spatial
        width = try c.decodeIfPresent(Double.self,forKey:.width) ?? width
        headTracking = try c.decodeIfPresent(Bool.self,forKey:.headTracking) ?? headTracking
        orbit = try c.decodeIfPresent(Bool.self,forKey:.orbit) ?? orbit
        overrides = try c.decodeIfPresent([Int:KeyOverride].self,forKey:.overrides) ?? overrides
    }
    // Applied to the active sound and to every saved preset, since selecting a preset copies it straight into the active sound.
    mutating func validate() {
        if SoundProfile.find(profile) == nil { profile = "alpaca" }
        volume = clamp(volume,0...1); mouseVolume = clamp(mouseVolume,0...1); enterVolume = clamp(enterVolume,0...1)
        tone = clamp(tone,-1...1); pitch = clamp(pitch,-12...12)
        homeSoftness = clamp(homeSoftness,0...1); width = clamp(width,0...2)
        for (key,var value) in overrides {
            if let id = value.profile, SoundProfile.find(id) == nil { value.profile = nil }
            if let x = value.volume { value.volume = clamp(x,0...1) }
            if let x = value.tone { value.tone = clamp(x,-1...1) }
            if let x = value.pitch { value.pitch = clamp(x,-12...12) }
            overrides[key] = value
        }
    }
}
private func clamp(_ x: Double, _ range: ClosedRange<Double>, fallback: Double = 0) -> Double { x.isFinite ? min(range.upperBound,max(range.lowerBound,x)) : fallback }
struct SoundPreset: Identifiable, Codable, Equatable {
    var id = UUID()
    var name: String
    var sound: SoundConfiguration
}
struct KeystrokeVisual: Identifiable, Equatable {
    let id = UUID()
    let key: Int
    let chord: String
    var count = 1
    var time: TimeInterval
    var label: String { chord + (count > 1 ? " ×\(count)" : "") }
}

struct VisualizerTrail: Equatable {
    static let capacity = 15
    static let lifetime = 1.9
    static let afterglow = 1.4
    private(set) var strokes: [KeystrokeVisual] = []
    private(set) var releases: [Int:TimeInterval] = [:]

    mutating func press(_ event: PhysicalInputEvent) {
        expire(at:event.timestamp)
        releases[event.key] = nil
        guard !KeyGeometry.modifierKeys.contains(event.key) else { return }
        let chord = KeyGeometry.chord(event)
        if let last = strokes.last, last.key == event.key, last.chord == chord, event.timestamp-last.time < 0.3 {
            strokes[strokes.count-1].count += 1
            strokes[strokes.count-1].time = event.timestamp
        } else {
            strokes.append(KeystrokeVisual(key:event.key,chord:chord,time:event.timestamp))
            if strokes.count > Self.capacity { strokes.removeFirst(strokes.count-Self.capacity) }
        }
    }
    mutating func release(_ key: Int, at time: TimeInterval) { releases[key] = time }
    mutating func expire(at time: TimeInterval) {
        strokes.removeAll { time-$0.time >= Self.lifetime }
        releases = releases.filter { time-$0.value < Self.afterglow }
    }
    var nextExpiry: TimeInterval? {
        (strokes.map { $0.time+Self.lifetime } + releases.values.map { $0+Self.afterglow }).min()
    }
}

enum VisualizerMotion: String, CaseIterable {
    case pop = "Pop", slide = "Slide", bounce = "Bounce", pulse = "Pulse", float = "Float"
    var arrivalScale: Double { switch self { case .pop:0.82; case .pulse:1.12; default:1 } }
    var arrivalX: Double { self == .slide ? 22 : 0 }
    var arrivalY: Double { self == .bounce ? 14 : 0 }
}

struct VisualizerSettings: Codable, Equatable {
    var enabled = false
    var style = "Keyboard"
    var placement = "Follow Cursor"
    var pin = "Bottom Center"
    var offset = 35.0
    var scale = 1.0
    var dismiss = 1.0
    var theme = "Dark"
    var comboTheme = "Amber"
    var motion = "Pop"
    var flow = "Row"
    var shuffleEvery = 5
    var comboReset = 2.0
    var preserveCombo = false
    var keepComboVisible = false
    private enum CodingKeys: String, CodingKey {
        case enabled, style, placement, pin, offset, scale, dismiss, theme, comboTheme, motion, flow, shuffleEvery, comboReset, preserveCombo, keepComboVisible
    }
    init() {}
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy:CodingKeys.self)
        enabled = try c.decodeIfPresent(Bool.self,forKey:.enabled) ?? enabled
        style = try c.decodeIfPresent(String.self,forKey:.style) ?? style
        placement = try c.decodeIfPresent(String.self,forKey:.placement) ?? placement
        pin = try c.decodeIfPresent(String.self,forKey:.pin) ?? pin
        offset = try c.decodeIfPresent(Double.self,forKey:.offset) ?? offset
        scale = try c.decodeIfPresent(Double.self,forKey:.scale) ?? scale
        dismiss = try c.decodeIfPresent(Double.self,forKey:.dismiss) ?? dismiss
        theme = try c.decodeIfPresent(String.self,forKey:.theme) ?? theme
        comboTheme = try c.decodeIfPresent(String.self,forKey:.comboTheme) ?? comboTheme
        motion = try c.decodeIfPresent(String.self,forKey:.motion) ?? motion
        flow = try c.decodeIfPresent(String.self,forKey:.flow) ?? flow
        shuffleEvery = try c.decodeIfPresent(Int.self,forKey:.shuffleEvery) ?? shuffleEvery
        comboReset = try c.decodeIfPresent(Double.self,forKey:.comboReset) ?? comboReset
        preserveCombo = try c.decodeIfPresent(Bool.self,forKey:.preserveCombo) ?? preserveCombo
        keepComboVisible = try c.decodeIfPresent(Bool.self,forKey:.keepComboVisible) ?? keepComboVisible
    }
    var movement: VisualizerMotion { motion == "Float" && style != "Keystrokes" ? .pop : (VisualizerMotion(rawValue:motion) ?? .pop) }
    var tailDuration: TimeInterval { style == "Keystrokes" ? VisualizerTrail.lifetime : (style == "Keyboard" ? VisualizerTrail.afterglow : 0) }
    var panelSize: CGSize {
        switch style {
        case "Combo": CGSize(width:210,height:170)
        case "Keystrokes": movement == .float ? CGSize(width:840,height:230) : (flow == "Column" ? CGSize(width:180,height:640) : CGSize(width:840,height:90))
        default: CGSize(width:420,height:170)
        }
    }
}
struct AppSettings: Codable, Equatable {
    var version = 1
    var enabled = true
    var muted = false
    var sound = SoundConfiguration()
    var visualizer = VisualizerSettings()
    var layout = "ANSI"
    var outputUID = ""
    var outputKind = "Auto"
    var pauseOnHeadphones = false
    var showDock = false
    var showMenu = true
    var toggleCues = true
    var shortcutKey = 40
    var shortcutModifiers: UInt64 = CGEventFlags.maskControl.rawValue | CGEventFlags.maskAlternate.rawValue | CGEventFlags.maskCommand.rawValue
    var gestureTaps = 1
    var presets: [SoundPreset] = []
    var imports: [ImportedSound] = []
    var onboardingComplete = false
    // nil is Porcelain, the bundled primary icon. Optional so settings saved before this field still decode.
    var iconColor: String?
    // AI mode, optional for the same reason. A nil folder codes along from Board's own sources.
    var aiMode: Bool?
    var aiSpeed: Double?
    var aiFolder: String?
    private enum CodingKeys: String, CodingKey {
        case version, enabled, muted, sound, visualizer, layout, outputUID, outputKind, pauseOnHeadphones, showDock, showMenu, toggleCues, shortcutKey, shortcutModifiers, gestureTaps, presets, imports, onboardingComplete, iconColor, aiMode, aiSpeed, aiFolder
    }
    init() {}
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy:CodingKeys.self)
        version = try c.decodeIfPresent(Int.self,forKey:.version) ?? version
        enabled = try c.decodeIfPresent(Bool.self,forKey:.enabled) ?? enabled
        muted = try c.decodeIfPresent(Bool.self,forKey:.muted) ?? muted
        sound = try c.decodeIfPresent(SoundConfiguration.self,forKey:.sound) ?? sound
        visualizer = try c.decodeIfPresent(VisualizerSettings.self,forKey:.visualizer) ?? visualizer
        layout = try c.decodeIfPresent(String.self,forKey:.layout) ?? layout
        outputUID = try c.decodeIfPresent(String.self,forKey:.outputUID) ?? outputUID
        outputKind = try c.decodeIfPresent(String.self,forKey:.outputKind) ?? outputKind
        pauseOnHeadphones = try c.decodeIfPresent(Bool.self,forKey:.pauseOnHeadphones) ?? pauseOnHeadphones
        showDock = try c.decodeIfPresent(Bool.self,forKey:.showDock) ?? showDock
        showMenu = try c.decodeIfPresent(Bool.self,forKey:.showMenu) ?? showMenu
        toggleCues = try c.decodeIfPresent(Bool.self,forKey:.toggleCues) ?? toggleCues
        shortcutKey = try c.decodeIfPresent(Int.self,forKey:.shortcutKey) ?? shortcutKey
        shortcutModifiers = try c.decodeIfPresent(UInt64.self,forKey:.shortcutModifiers) ?? shortcutModifiers
        gestureTaps = try c.decodeIfPresent(Int.self,forKey:.gestureTaps) ?? gestureTaps
        presets = try c.decodeIfPresent([SoundPreset].self,forKey:.presets) ?? presets
        imports = try c.decodeIfPresent([ImportedSound].self,forKey:.imports) ?? imports
        onboardingComplete = try c.decodeIfPresent(Bool.self,forKey:.onboardingComplete) ?? onboardingComplete
        iconColor = try c.decodeIfPresent(String.self,forKey:.iconColor)
        aiMode = try c.decodeIfPresent(Bool.self,forKey:.aiMode)
        aiSpeed = try c.decodeIfPresent(Double.self,forKey:.aiSpeed)
        aiFolder = try c.decodeIfPresent(String.self,forKey:.aiFolder)
    }
    static let iconColors = ["Porcelain","Sage","Blue","Lilac","Graphite"]
    mutating func validate() {
        if let color = iconColor, color == "Porcelain" || !Self.iconColors.contains(color) { iconColor = nil }
        sound.validate()
        for index in presets.indices { presets[index].sound.validate() }
        visualizer.scale = clamp(visualizer.scale,0.5...2,fallback:1)
        visualizer.dismiss = clamp(visualizer.dismiss,0.3...5,fallback:1)
        visualizer.comboReset = clamp(visualizer.comboReset,0.3...10,fallback:2)
        visualizer.offset = clamp(visualizer.offset,0...200)
        visualizer.shuffleEvery = min(100,max(1,visualizer.shuffleEvery))
        gestureTaps = min(5,max(1,gestureTaps)); presets = Array(presets.prefix(6))
        if let speed = aiSpeed { aiSpeed = clamp(speed,0...1,fallback:0.35) }
    }
}

struct ComboState {
    private(set) var count = 0
    private(set) var totalPresses = 0
    private(set) var lastPress: TimeInterval?
    mutating func press(at time: TimeInterval, settings: VisualizerSettings) -> Bool {
        if let lastPress, time-lastPress >= settings.comboReset, !settings.preserveCombo { count = 0 }
        count += 1; totalPresses += 1; lastPress = time
        return totalPresses == 1 || totalPresses % settings.shuffleEvery == 0
    }
    mutating func expire(at time:TimeInterval,settings:VisualizerSettings) {
        if let lastPress, !settings.preserveCombo, time-lastPress >= settings.comboReset { count = 0 }
    }
    func visible(at time: TimeInterval, settings: VisualizerSettings) -> Bool {
        guard let lastPress else { return false }
        return (settings.style == "Combo" && settings.keepComboVisible) || time-lastPress < settings.dismiss
    }
    mutating func clear() { self = ComboState() }
}
struct ShortcutState {
    private var taps = 0
    private var last: TimeInterval = 0
    mutating func matches(_ event: PhysicalInputEvent, settings: AppSettings) -> Bool {
        guard event.transition == .press else { return false }
        let mask = CGEventFlags.maskCommand.rawValue | CGEventFlags.maskControl.rawValue | CGEventFlags.maskAlternate.rawValue | CGEventFlags.maskShift.rawValue
        guard event.key == settings.shortcutKey, event.modifiers & mask == settings.shortcutModifiers & mask else { if !KeyGeometry.modifierKeys.contains(event.key) { taps = 0 }; return false }
        taps = event.timestamp-last <= 0.6 ? taps+1 : 1; last = event.timestamp
        if taps >= settings.gestureTaps { taps = 0; return true }; return false
    }
}

struct PressReleaseStore<Value> {
    private var values: [Int:Value] = [:]
    mutating func remember(_ value: Value, key: Int) { values[key] = value }
    mutating func release(key: Int) -> Value? { values.removeValue(forKey:key) }
    mutating func clear() { values.removeAll() }
}
