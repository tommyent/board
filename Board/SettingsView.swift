import SwiftUI
import ServiceManagement

enum SettingsSection: String, CaseIterable, Identifiable {
    case general = "General", sound = "Sound", keyboard = "Your Keyboard", visualizer = "Visualizer", extras = "Extras", about = "About"
    var id: String { rawValue }
    var icon: String { switch self { case .general:"slider.horizontal.3"; case .sound:"waveform"; case .keyboard:"keyboard"; case .visualizer:"sparkles.rectangle.stack"; case .extras:"sparkles"; case .about:"info.circle" } }
}
extension Color {
    init(hex: String) { let value = UInt64(hex,radix:16) ?? 0xF1913D; self.init(red:Double((value>>16)&255)/255,green:Double((value>>8)&255)/255,blue:Double(value&255)/255) }
}
// Brand colors for the chosen icon color (Board Keycap package): the strong accent with white on it for light backgrounds,
// the pale finish with its face color on it for dark ones. Strong accents are unreadable on dark backgrounds and pale ones on light.
struct Accent {
    let strong: Color, pale: Color, face: Color
    init(_ iconColor: String?) {
        let hex = ["Sage":("465C49","C8D5C5","27362B"),"Blue":("35566F","C4D7E9","25394A"),"Lilac":("625178","D9CEEB","3E334B"),"Graphite":("424743","F3EFE8","424743")][iconColor ?? ""] ?? ("262826","F3EFE8","262826")
        strong = Color(hex:hex.0); pale = Color(hex:hex.1); face = Color(hex:hex.2)
    }
    func fill(light: Bool) -> Color { light ? strong : pale }
    func text(light: Bool) -> Color { light ? .white : face }
    var tint: Color { dynamic(strong,pale) }
    var onTint: Color { dynamic(.white,face) }
    private func dynamic(_ light: Color,_ dark: Color) -> Color { Color(nsColor:NSColor(name:nil) { $0.bestMatch(from:[.aqua,.darkAqua]) == .darkAqua ? NSColor(dark) : NSColor(light) }) }
}
struct SwitchMark: View {
    var color: Color
    var body: some View { ZStack { RoundedRectangle(cornerRadius:5).fill(color.opacity(0.2)); RoundedRectangle(cornerRadius:2).fill(color).frame(width:15,height:15); Image(systemName:"plus").font(.system(size:9,weight:.heavy)).foregroundStyle(.white) }.frame(width:28,height:28) }
}
struct SettingsView: View {
    @ObservedObject var app: AppState
    private var section: SettingsSection? { app.selectedSettingsSection }
    var body: some View {
        HStack(spacing:0) {
            VStack(alignment:.leading,spacing:18) {
                HStack(spacing:10) {
                    Image(nsImage:app.iconImage).resizable().frame(width:46,height:46)
                    VStack(alignment:.leading,spacing:3) { Text("Board").font(.headline); Text("A little joy in every key.").font(.caption).foregroundStyle(.secondary) }
                }.padding(.horizontal,14).padding(.top,20)
                // Rows draw their own selection: a sidebar List's selection always uses the macOS accent and ignores tint.
                List(SettingsSection.allCases) { item in
                    let selected = (section ?? .general) == item
                    Button { app.selectedSettingsSection = item } label: { Label(item.rawValue,systemImage:item.icon).padding(.vertical,5).frame(maxWidth:.infinity,alignment:.leading).contentShape(Rectangle()) }
                        .buttonStyle(.plain).foregroundStyle(selected ? app.accent.onTint : .primary).listItemTint(.fixed(selected ? app.accent.onTint : app.accent.tint))
                        .listRowBackground(RoundedRectangle(cornerRadius:8).fill(selected ? app.accent.tint : .clear).padding(.horizontal,10))
                        .accessibilityAddTraits(selected ? .isSelected : [])
                }.listStyle(.sidebar).focusable().onKeyPress(keys:[.upArrow,.downArrow]) { press in
                    let all = SettingsSection.allCases, index = all.firstIndex(of:section ?? .general)! + (press.key == .downArrow ? 1 : -1)
                    if all.indices.contains(index) { app.selectedSettingsSection = all[index] }
                    return .handled
                }
                Label("On this Mac. Offline.",systemImage:"lock.shield").font(.caption).foregroundStyle(.secondary).padding(18)
            }.frame(width:210).background(.ultraThinMaterial)
            Divider()
            VStack(alignment:.leading,spacing:0) {
                HStack {
                    VStack(alignment:.leading,spacing:4) { Text((section ?? .general).rawValue).font(.system(size:25,weight:.bold)); Text(subtitle).font(.callout).foregroundStyle(.secondary) }
                    Spacer()
                    Toggle("Board",isOn:Binding(get:{app.settings.enabled},set:{_ in app.toggle()})).toggleStyle(.switch).fixedSize()
                }.padding(24)
                Divider()
                ScrollView {
                    VStack(alignment:.leading,spacing:18) {
                        switch section ?? .general {
                        case .general: GeneralSettings(app:app)
                        case .sound: SoundSettings(app:app)
                        case .keyboard: KeyboardSettings(app:app)
                        case .visualizer: VisualizerPreferences(app:app)
                        case .extras: ExtrasSettings(app:app)
                        case .about: AboutSettings(app:app)
                        }
                    }.padding(24).frame(maxWidth:.infinity,alignment:.leading)
                }
            }.background(Color(nsColor:.windowBackgroundColor))
        }.tint(app.accent.tint).frame(minWidth:850,minHeight:650)
            .alert("Board",isPresented:Binding(get:{app.error != nil},set:{if !$0 { app.error = nil }})) { Button("OK") { app.error = nil } } message: { Text(app.error ?? "") }
    }
    var subtitle: String {
        switch section ?? .general {
        case .general:"Make yourself at home."
        case .sound:"Find your favorite thock."
        case .keyboard:"Every key can have its own character."
        case .visualizer:"See the rhythm of your typing."
        case .extras:"A few things just for fun."
        case .about:"Built for your Mac."
        }
    }
}
struct SettingsCard<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment:.leading,spacing:14) { Text(title.uppercased()).font(.system(size:10,weight:.semibold)).tracking(1.2).foregroundStyle(.secondary); content }.padding(18).frame(maxWidth:.infinity,alignment:.leading).background(.background,in:RoundedRectangle(cornerRadius:12)).overlay(RoundedRectangle(cornerRadius:12).stroke(.primary.opacity(0.06)))
    }
}
struct LabeledSlider: View {
    var title: String
    @Binding var value: Double
    var range: ClosedRange<Double> = 0...1
    var suffix = "%"
    var body: some View {
        VStack(spacing:6) {
            HStack { Text(title); Spacer(); Text(suffix == "%" ? "\(Int(value*100))%" : String(format:"%.1f",value)+suffix).monospacedDigit().foregroundStyle(.secondary) }
            Slider(value:$value,in:range).accessibilityLabel(title)
        }
    }
}
struct GeneralSettings: View {
    @ObservedObject var app: AppState
    var body: some View {
        SettingsCard(title:"Physical input") {
            Label(app.inputStatus,systemImage:app.inputStatus.hasPrefix("Listening") ? "checkmark.shield.fill" : "hand.raised.fill").foregroundStyle(app.inputStatus.hasPrefix("Listening") ? .green : .orange)
            Text("Board responds to physical key positions and mouse buttons. It does not read, record, or transmit typed text. Secure Input pauses monitoring. Local sound previews work without permission.").font(.callout).foregroundStyle(.secondary)
            if app.inputStatus.hasPrefix("Input Monitoring required") {
                if app.inputRequested { Button("Open Input Monitoring Settings") { app.openInputSettings() }.buttonStyle(.borderedProminent) }
                else { Button("Request Input Monitoring") { app.requestInput() }.buttonStyle(.borderedProminent) }
                Text("After turning Board on, choose Quit & Reopen when macOS asks.").font(.caption).foregroundStyle(.secondary)
            }
            if !app.settings.onboardingComplete { Button("Got it — continue") { app.settings.onboardingComplete = true } }
        }
        SettingsCard(title:"Application") {
            Toggle("Launch at login",isOn:Binding(get:{app.loginEnabled},set:{app.setLogin($0)}))
            Text(app.loginStatus).font(.caption).foregroundStyle(.secondary)
            if app.loginStatus.hasPrefix("Approval") { Button("Open Login Items") { SMAppService.openSystemSettingsLoginItems() } }
            Divider()
            Toggle("Show in Dock and Command–Tab",isOn:$app.settings.showDock)
            Toggle("Show menu bar icon",isOn:$app.settings.showMenu)
            Text("Reopen Board from Finder or Spotlight to reveal Settings, even when both icons are hidden.").font(.caption).foregroundStyle(.secondary)
        }
        SettingsCard(title:"App icon") {
            HStack(spacing:14) {
                ForEach(AppSettings.iconColors,id:\.self) { color in
                    let selected = (app.settings.iconColor ?? "Porcelain") == color
                    Button { app.settings.iconColor = color == "Porcelain" ? nil : color } label: {
                        VStack(spacing:6) {
                            Image(nsImage:app.iconImages[color] ?? NSImage()).resizable().frame(width:56,height:56).padding(4)
                                .overlay(RoundedRectangle(cornerRadius:16).stroke(selected ? app.accent.tint : .clear,lineWidth:2))
                                .overlay(alignment:.topTrailing) { if selected { Image(systemName:"checkmark.circle.fill").foregroundStyle(app.accent.onTint,app.accent.tint) } }
                            Text(color).font(.caption)
                        }
                    }.buttonStyle(.plain).accessibilityLabel("\(color) app icon").accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
            Text(app.settings.showDock ? "Changes Board's icon in Settings, About and the Dock. Finder and Launchpad keep Porcelain." : "Changes Board's icon in Settings and About. Turn on Show in Dock and Command–Tab to see it in the Dock too. Finder and Launchpad keep Porcelain.").font(.caption).foregroundStyle(.secondary)
        }
        SettingsCard(title:"Toggle shortcut") {
            HStack { Text(app.shortcutLabel).font(.system(.body,design:.monospaced)).padding(8).background(.quaternary,in:RoundedRectangle(cornerRadius:7)); Spacer(); Button(app.recordingShortcut ? "Cancel recording" : "Record shortcut") { app.recordingShortcut.toggle() } }
            if app.recordingShortcut { Text("Press a physical key combination. Input Monitoring must be granted.").font(.caption).foregroundStyle(app.accent.tint) }
            Stepper("Repeated-key gesture: \(app.settings.gestureTaps) tap(s)",value:$app.settings.gestureTaps,in:1...5)
            Text("Repeat the same combination within 0.6 seconds. Key repeats are ignored.").font(.caption).foregroundStyle(.secondary)
        }
    }
}
struct SoundSettings: View {
    @ObservedObject var app: AppState
    @State private var presetName = ""
    var body: some View {
        SettingsCard(title:"Profile") {
            HStack { SwitchMark(color:Color(hex:app.selectedProfile.color)); VStack(alignment:.leading) { Text(app.selectedProfile.title).font(.headline); Text(app.selectedProfile.hasReleaseSamples ? "Real press and release recordings" : "Four recorded typewriter keystrokes").font(.caption).foregroundStyle(.secondary) }; Spacer(); Button("Preview",systemImage:"play.fill") { app.audio.preview() } }
            Picker("Switch",selection:$app.settings.sound.profile) {
                ForEach(SoundProfile.catalog) { profile in Text(profile.title).tag(profile.id) }
            }
        }
        SettingsCard(title:"Volume & feel") {
            LabeledSlider(title:"Typing volume",value:$app.settings.sound.volume)
            Toggle("Mute sounds",isOn:$app.settings.muted)
            Toggle("Normalize profile loudness",isOn:$app.settings.sound.normalization)
            Toggle("Gentle pitch and gain variation",isOn:$app.settings.sound.variation)
            LabeledSlider(title:"Home-row softness",value:$app.settings.sound.homeSoftness)
        }
        SettingsCard(title:"Tone & pitch") {
            TonePad(tone:$app.settings.sound.tone,pitch:$app.settings.sound.pitch,color:app.accent.tint)
            LabeledSlider(title:"Tone · thock to clack",value:$app.settings.sound.tone,range:-1...1,suffix:"")
            LabeledSlider(title:"Pitch",value:$app.settings.sound.pitch,range:-12...12,suffix:" st")
            HStack { Button("Reset to Middle") { app.settings.sound.tone = 0; app.settings.sound.pitch = 0 }; Spacer(); Text(app.audioStatus).font(.caption).foregroundStyle(.secondary) }
        }
        SpatialSettings(app:app)
        EffectSettings(app:app,target:"Mouse")
        EffectSettings(app:app,target:"Enter")
        SettingsCard(title:"Favorites · \(app.settings.presets.count) of 6") {
            ForEach(app.settings.presets) { preset in HStack { Button(preset.name) { app.settings.sound = preset.sound }; Spacer(); Button("Remove",systemImage:"trash") { app.settings.presets.removeAll { $0.id == preset.id } }.labelStyle(.iconOnly).accessibilityLabel("Remove \(preset.name)") } }
            HStack { TextField("Favorite name",text:$presetName); Button("Save current") { app.savePreset(name:presetName); presetName = "" }.disabled(app.settings.presets.count >= 6) }
        }
    }
}
struct TonePad: View {
    @Binding var tone: Double
    @Binding var pitch: Double
    let color: Color
    var body: some View {
        GeometryReader { geo in
            ZStack {
                RoundedRectangle(cornerRadius:14).fill(LinearGradient(colors:[color.opacity(0.06),color.opacity(0.25)],startPoint:.bottomLeading,endPoint:.topTrailing))
                Path { p in p.move(to:.init(x:geo.size.width/2,y:10)); p.addLine(to:.init(x:geo.size.width/2,y:geo.size.height-10)); p.move(to:.init(x:10,y:geo.size.height/2)); p.addLine(to:.init(x:geo.size.width-10,y:geo.size.height/2)) }.stroke(.primary.opacity(0.08),style:StrokeStyle(dash:[3,4]))
                Circle().stroke(color.opacity(0.4),lineWidth:2).frame(width:24,height:24)
                VStack { Text("SHARP"); Spacer(); HStack { Text("THOCK"); Spacer(); Text("CLACK") }; Spacer(); Text("DEEP") }.font(.system(size:9,weight:.semibold)).tracking(1).foregroundStyle(.secondary).padding(12)
                Circle().fill(color.gradient).frame(width:22,height:22).shadow(color:color.opacity(0.3),radius:6,y:2).position(x:22+(tone+1)/2*(geo.size.width-44),y:22+(1-(pitch+12)/24)*(geo.size.height-44))
            }.contentShape(Rectangle()).gesture(DragGesture(minimumDistance:0).onChanged { event in
                tone = min(1, max(-1, (event.location.x-22)/(geo.size.width-44)*2-1))
                pitch = min(12, max(-12, (1-(event.location.y-22)/(geo.size.height-44))*24-12))
            })
        }.frame(height:150).accessibilityHidden(true)
    }
}
struct SpatialSettings: View {
    @ObservedObject var app: AppState
    var body: some View {
        SettingsCard(title:"Spatial audio & output") {
            Toggle("Spatial audio",isOn:$app.settings.sound.spatial)
            LabeledSlider(title:"Stereo width",value:$app.settings.sound.width,range:0...2)
            Picker("Output",selection:$app.settings.outputUID) { Text("System Default").tag(""); ForEach(app.devices) { Text($0.name).tag($0.uid) }; if !app.settings.outputUID.isEmpty, !app.devices.contains(where:{$0.uid == app.settings.outputUID}) { Text("Preferred output (disconnected)").tag(app.settings.outputUID) } }
            Picker("Output kind",selection:$app.settings.outputKind) { ForEach(["Auto","Speakers","Headphones"],id:\.self) { Text($0) } }
            Toggle("Pause when selected output is headphones",isOn:$app.settings.pauseOnHeadphones)
            Toggle("Head tracking with supported headphones",isOn:$app.settings.sound.headTracking)
            HStack { Text(app.motionStatus).font(.caption).foregroundStyle(.secondary); Spacer(); Button("Recenter") { app.audio.recenter() } }
            Text(app.playbackStatus).font(.caption).foregroundStyle(.secondary)
            Text(app.audioMetrics).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
        }
    }
}
struct EffectSettings: View {
    @ObservedObject var app: AppState
    let target: String
    var selection: Binding<String> { target == "Mouse" ? $app.settings.sound.mouse : $app.settings.sound.enter }
    var volume: Binding<Double> { target == "Mouse" ? $app.settings.sound.mouseVolume : $app.settings.sound.enterVolume }
    var body: some View {
        SettingsCard(title:target+" sound") {
            Picker("Sound",selection:selection) { Text("None · silence").tag("none"); Text("Default · keyboard profile").tag("default"); ForEach(app.settings.imports) { Text($0.name).tag($0.id) } }
            LabeledSlider(title:target+" volume",value:volume)
            HStack { Button("Preview") { app.audio.preview(effect:selection.wrappedValue,key:target == "Mouse" ? 1000 : 36) }; Spacer(); Button("Import sound…") { app.importSound(target:target,pair:false) }; Button("Import press + release…") { app.importSound(target:target,pair:true) } }
            Text("WAV, AIFF, CAF, M4A, MP3 · up to 30 seconds / 25 MB per file").font(.caption2).foregroundStyle(.tertiary)
        }
    }
}
struct KeyboardSettings: View {
    @ObservedObject var app: AppState
    func value(_ path: WritableKeyPath<KeyOverride,Double?>, fallback: Double) -> Binding<Double> {
        Binding(get:{app.settings.sound.overrides[app.selectedKey]?[keyPath:path] ?? fallback},set:{var value = app.settings.sound.overrides[app.selectedKey] ?? KeyOverride(); value[keyPath:path] = $0; app.settings.sound.overrides[app.selectedKey] = value})
    }
    var body: some View {
        SettingsCard(title:"Your physical keyboard") {
            Picker("Layout",selection:$app.settings.layout) { ForEach(["ANSI","ISO","JIS"],id:\.self) { Text($0) } }.pickerStyle(.segmented)
            KeyboardView(layout:app.settings.layout,held:app.heldKeys,selected:app.selectedKey,theme:"Light",accent:app.accent) { app.selectedKey = $0; app.audio.preview(key:$0) }.frame(height:190)
            Picker("Physical key",selection:$app.selectedKey) { ForEach((KeyGeometry.keys(app.settings.layout).map(\.id)+[62,76,71,81,67,75,78,69,65,82,83,84,85,86,87,88,89,91,92]).sorted(),id:\.self) { Text("\(KeyGeometry.label($0)) · code \($0)").tag($0) } }
        }
        SettingsCard(title:"Key: \(KeyGeometry.label(app.selectedKey))") {
            Picker("Switch",selection:Binding(get:{app.settings.sound.overrides[app.selectedKey]?.profile ?? ""},set:{var override = app.settings.sound.overrides[app.selectedKey] ?? KeyOverride(); override.profile = $0.isEmpty ? nil : $0; app.settings.sound.overrides[app.selectedKey] = override})) {
                Text("Use global switch").tag(""); ForEach(SoundProfile.catalog) { Text($0.title).tag($0.id) }
            }
            LabeledSlider(title:"Key volume",value:value(\.volume,fallback:1))
            LabeledSlider(title:"Key tone",value:value(\.tone,fallback:app.settings.sound.tone),range:-1...1,suffix:"")
            LabeledSlider(title:"Key pitch",value:value(\.pitch,fallback:app.settings.sound.pitch),range:-12...12,suffix:" st")
            Button("Reset this key to global settings") { app.settings.sound.overrides.removeValue(forKey:app.selectedKey) }
        }
    }
}
struct VisualizerPreferences: View {
    @ObservedObject var app: AppState
    var body: some View {
        SettingsCard(title:"Display") {
            Toggle("Show visualizer",isOn:$app.settings.visualizer.enabled)
            Picker("Style",selection:$app.settings.visualizer.style) { ForEach(["Keyboard","Keystrokes","Combo","Bezel"],id:\.self) { Text($0) } }.onChange(of:app.settings.visualizer.style) { app.settings.visualizer.enabled = true }
            HStack { ForEach(["Dark","Light","Glass Dark","Glass Clear"],id:\.self) { theme in Button { app.settings.visualizer.theme = theme } label: { VStack { KeyboardView(layout:app.settings.layout,held:[0,1,2,3],theme:theme,accent:app.accent).frame(width:92,height:40); Text(theme).font(.caption2) }.padding(5).background(app.settings.visualizer.theme == theme ? app.accent.tint.opacity(0.18) : .clear,in:RoundedRectangle(cornerRadius:8)) }.buttonStyle(.plain).accessibilityLabel("\(theme) keyboard theme") } }
            Picker("Combo theme",selection:$app.settings.visualizer.comboTheme) { ForEach(["Monochrome","Amber","Neon"],id:\.self) { Text($0) } }
            Picker("Keystroke flow",selection:$app.settings.visualizer.flow) { ForEach(["Row","Column"],id:\.self) { Text($0) } }
            LabeledSlider(title:"Scale",value:$app.settings.visualizer.scale,range:0.5...2)
            Button("Preview visualizer") { app.demoVisualizer() }
        }
        SettingsCard(title:"Position & motion") {
            Picker("Placement",selection:$app.settings.visualizer.placement) { ForEach(["Follow Cursor","Pin to Screen","Random"],id:\.self) { Text($0) } }.onChange(of:app.settings.visualizer.placement) { app.settings.visualizer.enabled = true }
            Picker("Pinned position",selection:$app.settings.visualizer.pin) { ForEach(["Top Left","Top Center","Top Right","Bottom Left","Bottom Center","Bottom Right"],id:\.self) { Text($0) } }
            LabeledSlider(title:"Cursor offset",value:$app.settings.visualizer.offset,range:0...200,suffix:" pt")
            Picker("Movement",selection:$app.settings.visualizer.motion) { ForEach(["Pop","Slide","Bounce","Pulse"],id:\.self) { Text($0) } }
            Stepper("Shuffle every \(app.settings.visualizer.shuffleEvery) presses",value:$app.settings.visualizer.shuffleEvery,in:1...100)
            Text("Reduced Motion follows macOS Accessibility settings.").font(.caption).foregroundStyle(.secondary)
        }
        SettingsCard(title:"Timing") {
            LabeledSlider(title:"Dismiss after",value:$app.settings.visualizer.dismiss,range:0.3...5,suffix:" s")
            LabeledSlider(title:"Combo resets after",value:$app.settings.visualizer.comboReset,range:0.3...10,suffix:" s")
            Toggle("Preserve combo through pauses",isOn:$app.settings.visualizer.preserveCombo)
            Toggle("Keep combo visible when idle",isOn:$app.settings.visualizer.keepComboVisible)
        }
    }
}
struct ExtrasSettings: View {
    @ObservedObject var app: AppState
    var body: some View {
        SettingsCard(title:"Playful details") {
            Toggle("8D sound · orbit every eight seconds",isOn:$app.settings.sound.orbit)
            Toggle("Enable and disable sound cues",isOn:$app.settings.toggleCues)
        }
    }
}
struct AboutSettings: View {
    @ObservedObject var app: AppState
    var body: some View {
        SettingsCard(title:"Board · personal build") {
            HStack(spacing:20) { Image(nsImage:app.iconImage).resizable().frame(width:90,height:90); VStack(alignment:.leading,spacing:5) { Text("Good keys. Good company.").font(.title2.bold()); Text("Native macOS · Apple Silicon · Offline").foregroundStyle(.secondary) } }
            Text("Includes ten mechanical profiles and four recorded Typewriter variations.").font(.callout).foregroundStyle(.secondary)
        }
        SettingsCard(title:"Recordings & artwork") {
            Text("Mechanical samples: Thomas Lai and tplai/kbsim contributors, MIT license. Pinned source revision: ba103f3b0afa9dab80447aa2e7e2ed80b6bd80e4. Original geometric artwork and tonal cues are included in this project.").font(.callout)
            if let notice = try? String(contentsOf:app.resources.appendingPathComponent("THIRD-PARTY-NOTICES.txt"),encoding:.utf8) { Text(notice).font(.caption).foregroundStyle(.secondary).textSelection(.enabled) }
        }
        SettingsCard(title:"Diagnostics") { Text(app.inputStatus); Text(app.audioStatus); Text(app.audioMetrics); Text("Only aggregate status is shown. No event history or typed text is saved.").font(.caption).foregroundStyle(.secondary) }
    }
}
