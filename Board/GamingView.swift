import SwiftUI

struct GamingPracticeRoot: View {
    @ObservedObject var session: PracticeSession
    @ObservedObject var game: GamingPractice
    @ObservedObject var app: AppState
    let checkAvailability: () -> Void
    var body: some View {
        VStack(spacing: 0) {
            Picker("Practice tab", selection: $game.selected) {
                Text("Typing").tag(false); Text("Gaming").tag(true)
            }.pickerStyle(.segmented).labelsHidden().frame(width: 240).padding(12)
            Divider()
            if game.selected { GamingView(game: game, app: app, checkAvailability: checkAvailability) }
            else { PracticeView(session: session, app: app, checkAvailability: checkAvailability) }
        }.background(Color(nsColor: .windowBackgroundColor)).onChange(of: game.selected) {
            session.pause(); game.pause(); checkAvailability()
        }
    }
}

struct GamingView: View {
    @ObservedObject var game: GamingPractice
    @ObservedObject var app: AppState
    let checkAvailability: () -> Void
    @State private var historyVisible = false
    @State private var restartVisible = false
    @State private var clearVisible = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var phase: GamingSession.Phase { game.engine?.phase ?? .ready }
    private var score: GamingScore? { game.engine?.score }
    private var cue: GamingCue? { game.engine?.currentCue }
    private var cueVisible: Bool { cue.map { (game.engine?.elapsed ?? 0) >= $0.targetAt } ?? false }
    private var timingLabel: String {
        switch game.drill {
        case .reaction: return "median reaction"
        case .keyReversal: return "median release → press"
        default: return "median timing error"
        }
    }
    private func number(_ value: Double?, suffix: String = "") -> String { value.map { String(format: "%.0f", $0)+suffix } ?? "—" }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Gaming").font(.title2.bold()); Spacer()
                Button("History") { game.pause(); historyVisible = true }
                Toggle("Mute Board", isOn: $app.settings.muted).toggleStyle(.checkbox)
                Button("Sound…") { game.pause(); app.selectedSettingsSection = .sound; app.showSettings?() }
            }.padding(.horizontal, 26).padding(.vertical, 14)
            Divider()
            HStack {
                Picker("Drill", selection: $game.drill) {
                    ForEach(GamingDrill.allCases, id: \.self) { Text($0.title).tag($0) }
                }.frame(width: 210)
                if game.drill == .reaction {
                    Picker("Keys", selection: $game.keySet) {
                        Text("WASD").tag(0); Text("WASD + abilities").tag(1); Text("Abilities + mouse").tag(2)
                    }.frame(width: 225).help("Abilities: Q, E, R, F, Space, left Shift, and 1–5, plus WASD. Mouse adds left and right buttons.")
                } else {
                    Picker("BPM", selection: $game.tempo) { ForEach([60.0, 80, 100, 120, 160], id: \.self) { Text("\(Int($0))").tag($0) } }.frame(width: 120)
                    Picker("Window", selection: $game.timingWindow) {
                        Text(game.drill == .keyReversal ? "≤60 ms" : "±60 ms").tag(0.06)
                        Text(game.drill == .keyReversal ? "≤120 ms" : "±120 ms").tag(0.12)
                    }.frame(width: 150)
                }
                Spacer()
                Picker("Duration", selection: $game.duration) { Text("30s").tag(30.0); Text("60s").tag(60.0); Text("120s").tag(120.0) }.frame(width: 125)
            }.disabled(game.active).padding(.horizontal, 22).padding(.vertical, 12)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 30) {
                        metric(number(score?.medianMilliseconds, suffix: " ms"), timingLabel)
                        metric(number(score?.accuracyPercent, suffix: "%"), game.drill == .reaction ? "accuracy" : (game.drill == .keyReversal ? "within gap" : "on time"))
                        metric(number(score?.actionsPerMinute), "APM")
                        Spacer()
                        metric("\(Int(ceil(game.duration-(game.engine?.elapsed ?? 0))))s", "remaining")
                    }
                    ProgressView(value: game.engine?.elapsed ?? 0, total: game.duration).accessibilityLabel("Drill elapsed time")
                    HStack {
                        if let reason = game.unavailableReason { Label(reason, systemImage: "pause.circle") }
                        else { Text(instructions) }
                        Spacer()
                        if game.countdown != nil || phase == .running { Button("Pause") { game.pause() } }
                        else if phase == .paused { Button("Resume") { checkAvailability(); game.resume() }.disabled(game.unavailableReason != nil) }
                        else { Button(phase == .finished ? "Try again" : "Start") { checkAvailability(); game.start() }.buttonStyle(.borderedProminent).disabled(game.unavailableReason != nil) }
                        if phase == .paused { Button("Restart…") { restartVisible = true } }
                    }.font(.callout)
                    ZStack {
                        RoundedRectangle(cornerRadius: 16).fill(Color(nsColor: .textBackgroundColor))
                        VStack(spacing: 10) {
                            Text(cueHeading).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                            Text(target).font(.system(size: 54, weight: .semibold, design: .rounded))
                                .foregroundStyle(.primary).padding(.horizontal, 24)
                                .background(cueVisible ? Color(hex: app.selectedProfile.color).opacity(0.22) : .clear, in: RoundedRectangle(cornerRadius: 12))
                            Text(feedback).font(.callout.monospacedDigit()).foregroundStyle(.secondary)
                            if game.drill != .reaction, let cue {
                                ProgressView(value: max(0, min(1, ((game.engine?.elapsed ?? 0)-cue.startsAt)/(cue.targetAt-cue.startsAt))), total: 1)
                                    .frame(width: 260).accessibilityLabel("Time until beat")
                            }
                        }.padding(20).allowsHitTesting(false)
                        GamingInputView(game: game, checkAvailability: checkAvailability)
                            .accessibilityValue(target + ". " + feedback)
                    }.frame(height: 195)
                    if game.drill != .reaction, let engine = game.engine, phase == .running {
                        GamingBeatLane(engine: engine, color: Color(hex: app.selectedProfile.color), reduceMotion: reduceMotion)
                    }
                    Text("Physical QWERTY positions · Esc pauses · Tab leaves the input area · Click this area for mouse cues")
                        .font(.caption).foregroundStyle(.secondary)
                    HStack(alignment: .top, spacing: 30) {
                        GamingCluster(overlay: app.gamingOverlay)
                        VStack(alignment: .leading, spacing: 9) {
                            GamingOverlayToggle(overlay: app.gamingOverlay)
                            Text("WASD, left Shift/Ctrl, Space and mouse buttons. Hold times are temporary; gameplay is never scored.")
                                .font(.caption).foregroundStyle(.secondary)
                            Text(app.inputStatus).font(.caption).foregroundStyle(.secondary)
                            Text("Capture window: Board — Gaming Keys").font(.caption)
                            Text("Consistency: \(number(score?.madMilliseconds, suffix: " ms")) MAD")
                                .font(.callout).help("Median absolute deviation around the median response or signed timing error. Smaller is steadier.")
                            if let best = game.best { Text("Best: \(number(best.median, suffix: " ms")) · \(number(best.accuracy, suffix: "%"))").font(.callout) }
                            Text("Best requires ≥90% accuracy and no interrupted trials, with matching settings.").font(.caption).foregroundStyle(.secondary)
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }
                    if let error = game.historyError { Text(error).foregroundStyle(.red).font(.caption) }
                    if phase == .finished {
                        Text("\(score?.hits ?? 0) hits / \(score?.completedTrials ?? 0) trials · \(score?.extraPresses ?? 0) extra presses. Completed summary saved locally unless a history error is shown.")
                            .font(.callout)
                    }
                }.padding(22)
            }
            Divider()
            HStack {
                Text(app.selectedProfile.name + (!app.settings.enabled ? " · Board is off" : (app.settings.muted ? " · Muted" : "")))
                Spacer(); Text("Local summaries only · No game control")
            }.font(.caption).foregroundStyle(.secondary).padding(.horizontal, 26).padding(.vertical, 12)
        }.background(Color(nsColor: .windowBackgroundColor))
            .onChange(of: game.drill) { game.reset() }
            .onChange(of: game.duration) { game.reset() }
            .onChange(of: game.tempo) { game.reset() }
            .onChange(of: game.timingWindow) { game.reset() }
            .onChange(of: game.keySet) { game.reset() }
            .sheet(isPresented: $historyVisible) { historyView }
            .confirmationDialog("Discard this unfinished drill?", isPresented: $restartVisible) {
                Button("Restart", role: .destructive) { game.reset() }
                Button("Cancel", role: .cancel) { }
            }
    }
    private func metric(_ value: String, _ title: String) -> some View {
        VStack(alignment: .leading, spacing: 3) { Text(value).font(.title2.monospacedDigit().weight(.semibold)); Text(title).font(.caption).foregroundStyle(.secondary) }
    }
    private var instructions: String {
        switch game.drill {
        case .reaction: return "Wait for a key, then press it once."
        case .strafeRhythm: return "Alternate D and A on the beat. Release between presses."
        case .keyReversal: return "Hold the setup key; on GO, release it, then press the opposite key."
        case .holdTap: return "Hold left Shift and tap Space on each beat."
        }
    }
    private var cueHeading: String {
        if game.countdown != nil { return "GET READY" }
        if phase == .finished { return "DRILL COMPLETE" }
        if phase == .paused { return "PAUSED · CHOOSE RESUME" }
        if phase == .ready { return "\(game.drill.title.uppercased())" }
        return cueVisible ? "GO" : (game.drill == .reaction ? "WAIT FOR THE CUE" : "PREPARE FOR THE BEAT")
    }
    private var target: String {
        if let countdown = game.countdown { return "\(countdown)" }
        guard phase == .running else { return phase == .finished ? "Finished" : (phase == .paused ? "Paused" : "Ready") }
        guard let cue else {
            if game.drill == .holdTap { return "Hold Shift" }
            if game.drill == .keyReversal, let engine = game.engine, let last = engine.results.last, last.verdict == .hit {
                return "Hold " + engine.cues[last.cueID].input.label
            }
            return "Release"
        }
        if game.drill == .reaction { return cueVisible ? cue.input.label : "…" }
        if let release = cue.requiredRelease { return cueVisible ? "\(release.label) → \(cue.input.label)" : "Hold \(release.label)" }
        return (cue.requiredHold == nil ? "" : "Shift + ") + cue.input.label
    }
    private var feedback: String {
        guard let verdict = game.engine?.lastFeedback else {
            if game.drill == .reaction { return "Accuracy counts early, wrong and missed cues." }
            return "\(Int(game.tempo)) BPM · \(game.drill == .keyReversal ? "≤" : "±")\(Int(game.timingWindow*1000)) ms \(game.drill == .keyReversal ? "release → press" : "window")"
        }
        let label: String
        switch verdict {
        case .hit: label = "Hit"
        case .early: label = "Early"
        case .late: label = "Late"
        case .wrongKey: label = "Wrong key"
        case .missingHold: label = "Hold left Shift first"
        case .wrongOrder: label = "Release the setup key after GO, before pressing"
        case .timeout: label = "Missed cue"
        case .extra: label = "Extra press"
        case .interrupted: label = "Interrupted cue excluded"
        }
        let ms = game.engine?.results.last?.milliseconds
        return label + ((verdict != .extra && ms != nil) ? String(format: " · %+.0f ms", ms!) : "")
    }
    private var historyView: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack { Text("Gaming history").font(.title2.bold()); Spacer(); Button("Done") { historyVisible = false } }
            Text("Completed summaries only. MAD measures consistency; APM excludes releases and autorepeat.").font(.callout).foregroundStyle(.secondary)
            List(game.history) { result in
                VStack(alignment: .leading, spacing: 4) {
                    Text(result.category).font(.headline)
                    Text("\(number(result.median, suffix: " ms")) · \(number(result.accuracy, suffix: "%")) · \(number(result.mad, suffix: " ms MAD")) · \(number(result.apm, suffix: " APM"))")
                    Text(result.date, style: .date).font(.caption).foregroundStyle(.secondary)
                }.padding(.vertical, 4)
            }.overlay { if game.history.isEmpty { Text("Complete a drill to see it here.").foregroundStyle(.secondary) } }
            if let error = game.historyError { Text(error).font(.caption).foregroundStyle(.red) }
            Button("Clear gaming history…", role: .destructive) { clearVisible = true }
                .confirmationDialog("Delete all gaming summaries on this Mac?", isPresented: $clearVisible) {
                    Button("Clear history", role: .destructive) { game.clearHistory() }
                    Button("Cancel", role: .cancel) { }
                }
        }.padding(24).frame(width: 680, height: 470)
    }
}

struct GamingBeatLane: View {
    let engine: GamingSession
    let color: Color
    let reduceMotion: Bool
    var body: some View {
        let beat = 60/engine.configuration.tempo
        let upcoming = engine.cues.filter { $0.targetAt >= engine.elapsed-beat && $0.targetAt <= engine.elapsed+beat*3 }
        return GeometryReader { geometry in
            let center = geometry.size.width*0.3
            ZStack(alignment: .topLeading) {
                if reduceMotion {
                    HStack(spacing: 16) {
                        Text("NEXT").font(.caption).foregroundStyle(.secondary)
                        ForEach(upcoming.filter { $0.deadline > engine.elapsed }.prefix(4), id: \.id) { cue in
                            Text(cue.input.label).font(.title3.monospaced()).padding(12)
                                .background(.quaternary, in: RoundedRectangle(cornerRadius: 7))
                        }
                    }
                } else {
                    Rectangle().fill(.secondary).frame(width: 2, height: 54).position(x: center, y: 27)
                    ForEach(upcoming, id: \.id) { cue in
                        Text(cue.input.label).font(.title3.monospaced()).frame(width: 72, height: 46)
                            .background(color.opacity(0.18), in: RoundedRectangle(cornerRadius: 7))
                            .position(x: center+(cue.targetAt-engine.elapsed)/beat*100, y: 27)
                    }
                }
            }.clipped()
        }.frame(height: 56).accessibilityElement(children: .ignore)
            .accessibilityLabel("Upcoming beats: " + upcoming.filter { $0.targetAt >= engine.elapsed }.map { $0.input.label }.joined(separator: ", "))
    }
}

private struct GamingOverlayToggle: View {
    @ObservedObject var overlay: GamingOverlay
    var body: some View { Toggle("Gaming keys overlay", isOn: $overlay.enabled) }
}
