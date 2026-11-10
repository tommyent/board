import SwiftUI

struct PracticeView: View {
    @ObservedObject var session: PracticeSession
    @ObservedObject var app: AppState
    let checkAvailability: () -> Void
    @State private var historyVisible = false
    @State private var textVisible = false
    @State private var customDraft = ""
    @State private var restartConfirmation = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Practice").font(.title2.bold())
                Spacer()
                Button("History") { session.pause(); historyVisible = true }
                Button("Sound…") {
                    session.pause(); app.selectedSettingsSection = .sound; app.showSettings?()
                }
            }.padding(.horizontal, 26).padding(.vertical, 16)
            Divider()
            HStack(spacing: 16) {
                Picker("Passage", selection: $session.mode) {
                    ForEach(PracticeMode.allCases) { Text($0.rawValue).tag($0) }
                }.pickerStyle(.segmented).frame(maxWidth: 330)
                if session.mode == .code {
                    Picker("Language", selection: $session.language) {
                        ForEach(PracticePassages.languages, id: \.self) { Text($0).tag($0) }
                    }.labelsHidden().frame(width: 130)
                }
                if session.mode == .custom { Button("Edit text…") { textVisible = true } }
                Spacer(minLength: 0)
                Picker("Duration", selection: $session.duration) {
                    Text("30 seconds").tag(30); Text("1 minute").tag(60); Text("2 minutes").tag(120)
                }.frame(width: 175)
            }.disabled(session.phase == .running || session.phase == .paused)
                .padding(.horizontal, 26).padding(.vertical, 16)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .firstTextBaseline, spacing: 30) {
                        metric(String(format: "%.0f", session.wpm), "WPM")
                        metric(String(format: "%.1f%%", session.accuracy), "accuracy")
                        Spacer()
                        Text(String(format: "%d:%02d", session.remaining / 60, session.remaining % 60)).font(.title.monospacedDigit())
                        Text("left").foregroundStyle(.secondary)
                        if session.phase == .running { Button("Pause") { session.pause() }.keyboardShortcut(.cancelAction) }
                        else if session.phase == .paused {
                            Button("Resume") { checkAvailability(); session.resume() }.buttonStyle(.borderedProminent)
                                .disabled(session.unavailableReason != nil)
                        }
                        if session.phase == .running || session.phase == .paused { Button("Restart…") { session.pause(); restartConfirmation = true } }
                    }
                    ProgressView(value: session.elapsed, total: Double(session.duration)).accessibilityLabel("Time elapsed")
                    if session.phase == .finished { resultView }
                    else {
                        if let reason = session.unavailableReason {
                            Label(reason, systemImage: "pause.circle").foregroundStyle(.secondary)
                        } else if session.phase == .paused {
                            Label(session.pauseReason + " — choose Resume to continue", systemImage: "pause.circle")
                        } else {
                            Text(session.phase == .ready ? "Type the passage below. Your first character starts the clock." : "Keep a steady pace. Esc pauses.")
                                .foregroundStyle(.secondary)
                        }
                        if session.target.isEmpty {
                            ContentUnavailableView("Add a passage", systemImage: "text.alignleft", description: Text("Choose Edit text to paste your own text. It stays on this Mac and is cleared when you close Practice."))
                        } else {
                            ScrollView {
                                Text(markedPassage).font(session.mode == .code ? .system(size: 20, design: .monospaced) : .system(size: 23))
                                .lineSpacing(6).frame(maxWidth: .infinity, alignment: .leading)
                                .accessibilityLabel("Expected passage: " + visiblePassage)
                            }.frame(height: 112).padding(12).background(.background, in: RoundedRectangle(cornerRadius: 8))
                            Text(errorHint).font(.caption).foregroundStyle(.secondary)
                            PracticeInput(session: session, checkAvailability: checkAvailability).frame(height: 64)
                            Text(session.mode == .code ? "Type here · Tab inserts 4 spaces · Control-Tab leaves the field · Paste disabled" : "Type here · Delete corrects mistakes · Paste disabled")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    if session.showTrail && session.phase != .finished {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack { Text("KEY TRAIL").font(.caption); Spacer(); Text("Practice only").font(.caption) }.foregroundStyle(.secondary)
                            HStack(spacing: 8) {
                                Spacer()
                                ForEach(session.strokes) { stroke in
                                    Text(stroke.label).font(.system(size: 15, weight: .medium, design: .rounded))
                                        .frame(minWidth: 34, minHeight: 34).padding(.horizontal, 5)
                                        .background(app.accent.tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 7))
                                        .overlay(RoundedRectangle(cornerRadius: 7).stroke(app.accent.tint.opacity(0.35)))
                                        .transition(.opacity)
                                }
                                if session.strokes.isEmpty { Text("Your keys appear here as you type").font(.callout).foregroundStyle(.secondary) }
                                Spacer()
                            }.frame(height: 40).accessibilityHidden(true)
                                .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: session.strokes.map(\.id))
                        }.padding(10).background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 8))
                    }
                    HStack {
                        Toggle("Show key trail", isOn: $session.showTrail).toggleStyle(.checkbox)
                        Spacer()
                        if let best = session.best { Text(String(format: "Best: %.0f WPM · %@ · %ds", best, session.mode == .code ? session.language : session.mode.rawValue, session.duration)).foregroundStyle(.secondary) }
                    }.font(.caption)
                    if let error = session.historyError { Text(error).font(.callout).foregroundStyle(.red) }
                }.padding(22)
            }
            Divider()
            HStack {
                Text(app.selectedProfile.name)
                Text("·")
                Text(soundStatus)
                Spacer()
                Label("On this Mac. Offline.", systemImage: "lock.shield")
            }.font(.caption).foregroundStyle(.secondary).padding(.horizontal, 26).padding(.vertical, 12)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .onChange(of: session.mode) { _, mode in session.reset(); if mode == .custom && session.customText.isEmpty { textVisible = true } }
        .onChange(of: session.language) { session.reset() }
        .onChange(of: session.duration) { session.reset() }
        .sheet(isPresented: $historyVisible) { PracticeHistoryView(session: session) }
        .sheet(isPresented: $textVisible) { customEditor.onAppear { customDraft = session.customText }.onDisappear { customDraft = "" } }
        .confirmationDialog("Restart this attempt?", isPresented: $restartConfirmation) {
            Button("Restart", role: .destructive) { session.reset() }
            Button("Cancel", role: .cancel) { }
        } message: { Text("This unfinished attempt will not be saved to history.") }
    }

    private var soundStatus: String {
        if !app.settings.enabled { return "Board is off" }
        if app.settings.muted { return "Muted" }
        return app.inputStatus.hasPrefix("Listening") ? "Sound uses physical input" : app.inputStatus
    }
    private func metric(_ value: String, _ label: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 7) {
            Text(value).font(.system(size: 32, weight: .medium)).monospacedDigit()
            Text(label).font(.caption).foregroundStyle(.secondary)
        }.accessibilityElement(children: .combine)
    }
    private var visibleRange: Range<Int> {
        let cursor = session.typed.count
        let start = max(0, cursor - (session.mode == .code ? 35 : 65))
        return start..<min(session.target.count, start + (session.mode == .code ? 170 : 240))
    }
    private var visiblePassage: String { String(session.target[visibleRange]) }
    private var markedPassage: AttributedString { markedText(in: visibleRange) }
    private func markedText(in range: Range<Int>) -> AttributedString {
        let typed = Array(session.typed)
        var marked = AttributedString()
        for index in range {
            var character = AttributedString(String(session.target[index]))
            if index < typed.count {
                character.foregroundColor = typed[index] == session.target[index] ? .primary : .red
                if typed[index] != session.target[index] { character.underlineStyle = .single; character.backgroundColor = .red.opacity(0.12) }
            } else {
                character.foregroundColor = .secondary
                if index == typed.count { character.backgroundColor = .accentColor.opacity(0.2); character.underlineStyle = .single }
            }
            marked.append(character)
        }
        return marked
    }
    private var errorHint: String {
        let typed = Array(session.typed)
        if let index = typed.indices.first(where: { typed[$0] != session.target[$0] }) {
            return "Character \(index + 1): expected \(name(session.target[index])), typed \(name(typed[index])). Underlined text shows what to type."
        }
        return "The highlighted character is next. WPM counts correct characters; accuracy includes corrected mistakes."
    }
    private func name(_ character: Character) -> String {
        character == " " ? "space" : character == "\n" ? "a new line" : "“\(character)”"
    }
    private var resultView: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Practice complete").font(.title.bold())
            Text(String(format: "%.0f WPM · %.1f%% accuracy · %.1f seconds", session.wpm, session.accuracy, session.elapsed)).font(.title3)
            Text("\(session.correct) correct characters · \(session.attempts - session.correctAttempts) mistaken attempts").foregroundStyle(.secondary)
            if session.mode == .custom { Text("Custom passages are saved as results only, without their text. They have no shared personal best.").font(.callout).foregroundStyle(.secondary) }
            DisclosureGroup("Review errors") {
                Text(markedText(in: 0..<session.typed.count)).font(.system(size: 18, design: session.mode == .code ? .monospaced : .default)).frame(maxWidth: .infinity, alignment: .leading)
                Text(errorHint).font(.caption)
                Text("Underlines mark remaining mistakes. Corrected mistakes still count in accuracy.").font(.caption).foregroundStyle(.secondary)
            }
            Button("Try again") { session.reset() }.buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
        }.padding(20).frame(maxWidth: .infinity, alignment: .leading).background(.background, in: RoundedRectangle(cornerRadius: 10))
    }
    private var customEditor: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Your text").font(.title2.bold())
            Text("Paste up to 10,000 characters. Tabs become four spaces. Text stays in memory and is cleared when Practice closes.").foregroundStyle(.secondary)
            TextEditor(text: $customDraft).font(.system(.body, design: .monospaced)).border(.separator).accessibilityLabel("Custom practice passage")
            Text("\(PracticeSession.normalized(customDraft).count) / 10,000 characters").font(.caption).foregroundStyle(.secondary)
            HStack {
                Button("Cancel") { textVisible = false }.keyboardShortcut(.cancelAction)
                Spacer()
                Button("Use text") { session.customText = customDraft; session.reset(); textVisible = false }.buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
                    .disabled(customDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || PracticeSession.normalized(customDraft).count > PracticeSession.textLimit)
            }
        }.padding(24).frame(width: 580, height: 400)
    }
}

struct PracticeHistoryView: View {
    @ObservedObject var session: PracticeSession
    @Environment(\.dismiss) private var dismiss
    @State private var confirmClear = false
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack { Text("Practice history").font(.title2.bold()); Spacer(); Button("Done") { dismiss() }.keyboardShortcut(.cancelAction) }
            Text("The last 200 completed attempts, on this Mac only. Passage text and individual keystrokes are never saved.").foregroundStyle(.secondary)
            if let error = session.historyError { Text(error).foregroundStyle(.red) }
            if session.history.isEmpty { ContentUnavailableView("No completed attempts", systemImage: "clock", description: Text("Finish a practice session to see your results here.")) }
            else {
                List(session.history) { result in
                    HStack {
                        VStack(alignment: .leading, spacing: 4) { Text(result.category); Text(result.date, format: .dateTime.month().day().hour().minute()).font(.caption).foregroundStyle(.secondary) }
                        Spacer()
                        Text(String(format: "%.0f WPM", result.wpm)).monospacedDigit()
                        Text(String(format: "%.1f%%", result.accuracy)).monospacedDigit().frame(width: 65, alignment: .trailing)
                    }.padding(.vertical, 4)
                }
            }
            Button("Clear History…", role: .destructive) { confirmClear = true }.disabled(session.history.isEmpty && session.historyError == nil)
        }.padding(24).frame(width: 620, height: 460)
            .confirmationDialog("Clear all practice history?", isPresented: $confirmClear) {
                Button("Clear History", role: .destructive) { session.clearHistory() }
                Button("Cancel", role: .cancel) { }
            } message: { Text("This removes the saved results and personal bests from this Mac.") }
    }
}
