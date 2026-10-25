import AVFoundation
import CoreMotion
import AudioToolbox

final class KeyboardAudio {
    private final class Voice {
        let player = AVAudioPlayerNode()
        var until: TimeInterval = 0
        var generation = 0
    }
    private struct HeldSound {
        let bank: PreparedBank
        let gain: Float
        let pitch: Float
        let x: Float
    }
    let queue = DispatchQueue(label:"com.tommyent.Board.audio",qos:.userInteractive)
    private let worker = DispatchQueue(label:"com.tommyent.Board.prepare",qos:.userInitiated)
    private let root: URL
    private let importsRoot: URL
    private var engine = AVAudioEngine()
    private var environment = AVAudioEnvironmentNode()
    private var limiter: AVAudioUnitEffect?
    private var voices: [Voice] = []
    private var banks: [String: PreparedBank] = [:]
    private var held = PressReleaseStore<HeldSound>()
    private var activeSound = SoundConfiguration()
    private var preparation: DispatchWorkItem?
    private var configurationObserver: NSObjectProtocol?
    private var scheduledCount = 0
    var onPlayback: ((String) -> Void)?
    private var settings = AppSettings()
    private var preparedSignature = ""
    private var installedSignature = ""
    private var generation = 0
    private var previewGeneration = 0
    private var graphReady = false
    private var headphones = false
    private var lastActivity: TimeInterval = 0
    private var idleTimer: DispatchSourceTimer?
    private var orbitTimer: DispatchSourceTimer?
    private var deviceTimer: DispatchSourceTimer?
    private var deviceSignature = ""
    private let motion = CMHeadphoneMotionManager()
    private let motionQueue = OperationQueue()
    private var yawOffset = 0.0
    private var latestYaw = 0.0
    private var lastOrientation = AVAudio3DAngularOrientation(yaw:0,pitch:0,roll:0)
    var onStatus: ((String) -> Void)?
    var onDevices: (([AudioDevice]) -> Void)?
    var onMotion: ((String) -> Void)?
    var onMetrics: ((String) -> Void)?
    init(root: URL, importsRoot: URL) { self.root = root; self.importsRoot = importsRoot }
    private func bankKey(_ profile: String, _ tone: Double) -> String { profile+":"+String(format:"%.2f",tone) }
    func begin() {
        queue.async {
            let timer = DispatchSource.makeTimerSource(queue:self.queue)
            timer.schedule(deadline:.now(),repeating:2,leeway:.milliseconds(300))
            timer.setEventHandler { [weak owner = self] in owner?.checkDevices() }
            timer.resume(); self.deviceTimer = timer
        }
    }
    func configure(_ settings: AppSettings) {
        queue.async {
            let old = self.settings; self.settings = settings
            if old.enabled != settings.enabled || old.muted != settings.muted { self.held.clear(); self.previewGeneration += 1; self.fadeStop() }
            if old.outputUID != settings.outputUID || old.outputKind != settings.outputKind { self.deviceSignature = ""; self.checkDevices() }
            self.headphones = self.selectedDevice().map { self.isHeadphones($0) } ?? false
            if !settings.sound.headTracking || !settings.sound.spatial {
                self.motion.stopDeviceMotionUpdates()
                self.lastOrientation = .init(yaw:0,pitch:0,roll:0)
                self.environment.listenerAngularOrientation = self.lastOrientation
                self.onMotion?(settings.sound.spatial ? "Head tracking off" : "Spatial audio off")
            }
            if !settings.sound.orbit || !settings.sound.spatial { self.orbitTimer?.cancel(); self.orbitTimer = nil; self.environment.listenerAngularOrientation = self.lastOrientation }
            self.prepare(settings)
        }
    }
    private func prepare(_ snapshot: AppSettings) {
        var requests = [bankKey(snapshot.sound.profile,snapshot.sound.tone):(snapshot.sound.profile,snapshot.sound.tone)]
        for override in snapshot.sound.overrides.values {
            let profile = override.profile ?? snapshot.sound.profile, tone = override.tone ?? snapshot.sound.tone
            requests[bankKey(profile,tone)] = (profile,tone)
        }
        let customIDs = [snapshot.sound.mouse,snapshot.sound.enter].filter { $0 != "none" && $0 != "default" }
        let signature = requests.keys.sorted().joined(separator:"|")+customIDs.sorted().joined(separator:"|")+snapshot.imports.map { $0.id }.joined()
        guard signature != preparedSignature else { if signature == installedSignature { activeSound = snapshot.sound }; return }
        preparedSignature = signature; generation += 1
        let current = generation, existing = banks, root = self.root, importsRoot = self.importsRoot
        onStatus?("Preparing sound…")
        preparation?.cancel()
        let task = DispatchWorkItem {
            do {
                let processor = try ToneProcessor()
                var prepared: [String: PreparedBank] = [:]
                for (key,(profile,tone)) in requests {
                    guard SoundProfile.find(profile) != nil else { throw AudioValidationError(message:"Sound profile is unavailable.") }
                    prepared[key] = try existing[key] ?? PreparedBank.load(profile:profile,tone:tone,root:root,processor:processor)
                }
                for id in customIDs {
                    guard let item = snapshot.imports.first(where:{$0.id == id}) else { throw AudioValidationError(message:"Imported sound is unavailable.") }
                    prepared[id] = try PreparedBank.imported(item,root:importsRoot)
                }
                let bytes = prepared.values.reduce(0) { $0+$1.bytes }
                guard bytes < 256*1024*1024 else { throw AudioValidationError(message:"This configuration exceeds the 256 MB prepared sound limit.") }
                self.queue.async {
                    guard current == self.generation else { return }
                    self.preparation = nil
                    self.banks = prepared
                    self.activeSound = self.settings.sound
                    self.installedSignature = signature
                    self.onStatus?("Ready · \(prepared.count) prepared banks · \(bytes/1024/1024) MB")
                }
            } catch {
                self.queue.async { guard current == self.generation else { return }; self.preparation = nil; self.preparedSignature = ""; self.onStatus?(error.localizedDescription) }
            }
        }
        preparation = task
        worker.asyncAfter(deadline:.now()+0.08,execute:task)
    }
    private func selectedDevice() -> AudioDevice? {
        let devices = AudioDevice.list()
        return devices.first { $0.uid == settings.outputUID } ?? devices.first { $0.id == AudioDevice.defaultID }
    }
    private func isHeadphones(_ device: AudioDevice) -> Bool { settings.outputKind == "Headphones" || (settings.outputKind == "Auto" && device.headphones) }
    private func checkDevices() {
        let devices = AudioDevice.list()
        onDevices?(devices)
        guard let device = devices.first(where:{$0.uid == settings.outputUID}) ?? devices.first(where:{$0.id == AudioDevice.defaultID}) else { onStatus?("No audio output available"); return }
        let signature = "\(device.uid):\(device.sampleRate):\(settings.outputKind):\(device.headphones)"
        guard signature != deviceSignature else { return }
        deviceSignature = signature; headphones = isHeadphones(device)
        rebuild(device)
    }
    private func rebuild(_ device: AudioDevice) {
        if let configurationObserver { NotificationCenter.default.removeObserver(configurationObserver) }
        stopImmediately(); engine = AVAudioEngine(); environment = AVAudioEnvironmentNode(); graphReady = false
        lastOrientation = .init(yaw:0,pitch:0,roll:0)
        engine.attach(environment)
        let limiter = AVAudioUnitEffect(audioComponentDescription:.init(componentType:kAudioUnitType_Effect,componentSubType:kAudioUnitSubType_PeakLimiter,componentManufacturer:kAudioUnitManufacturer_Apple,componentFlags:0,componentFlagsMask:0))
        self.limiter = limiter; engine.attach(limiter)
        guard device.sampleRate.isFinite, device.sampleRate > 0,
              let stereo = AVAudioFormat(standardFormatWithSampleRate:device.sampleRate,channels:2) else {
            deviceSignature = ""; onStatus?("Audio output is changing; retrying…"); return
        }
        engine.connect(environment,to:limiter,format:stereo)
        engine.connect(limiter,to:engine.mainMixerNode,format:stereo)
        environment.distanceAttenuationParameters.rolloffFactor = 0
        environment.outputVolume = 0.8
        var id = device.id
        if let unit = engine.outputNode.audioUnit {
            let status = AudioUnitSetProperty(unit,kAudioOutputUnitProperty_CurrentDevice,kAudioUnitScope_Global,0,&id,UInt32(MemoryLayout.size(ofValue:id)))
            if status != noErr { onStatus?("Output selection failed (\(status)); retrying system output."); deviceSignature = ""; return }
        }
        voices = (0..<32).map { _ in
            let voice = Voice(); engine.attach(voice.player); engine.connect(voice.player,to:environment,format:AudioFiles.format)
            voice.player.sourceMode = .pointSource; voice.player.renderingAlgorithm = headphones ? .HRTFHQ : .equalPowerPanning
            return voice
        }
        let frames = AudioDevice.requestBuffer(device.id)
        engine.prepare(); graphReady = true
        let observedEngine = engine
        configurationObserver = NotificationCenter.default.addObserver(forName:.AVAudioEngineConfigurationChange,object:observedEngine,queue:nil) { [weak self] _ in
            self?.queue.async { [weak self] in
                guard let self, self.engine === observedEngine else { return }
                self.deviceSignature = ""; self.checkDevices()
            }
        }
        let fallback = !settings.outputUID.isEmpty && device.uid != settings.outputUID ? " · preferred output unavailable" : ""
        onMetrics?("\(device.name) · \(Int(device.sampleRate)) Hz · \(frames) frames\(fallback)")
    }
    func handle(_ event: PhysicalInputEvent) {
        queue.async { self.playEvent(event) }
    }
    private func playEvent(_ event: PhysicalInputEvent) {
        guard settings.enabled, !settings.muted, !(headphones && settings.pauseOnHeadphones) else { held.clear(); return }
        if event.transition == .release {
            guard let hit = held.release(key:event.key), let clip = hit.bank.sample(key:event.key,down:false) else { return }
            play(clip,gain:hit.gain,pitch:hit.pitch,x:hit.x); return
        }
        let sound = activeSound, override = sound.overrides[event.key]
        var profile = override?.profile ?? sound.profile
        let effect = event.isMouse ? sound.mouse : ([36,76].contains(event.key) ? sound.enter : "default")
        if effect == "none" { return }
        if effect != "default" { profile = effect }
        let key = effect != "default" ? effect : bankKey(profile,override?.tone ?? sound.tone)
        guard let bank = banks[key], let clip = bank.sample(key:event.key,down:true) else { return }
        let volume = event.isMouse ? sound.mouseVolume : ([36,76].contains(event.key) && effect != "default" ? sound.enterVolume : sound.volume)
        var gain = Float(volume * (override?.volume ?? 1)) * (sound.normalization ? bank.normalization : 1)
        if KeyGeometry.home.contains(event.key) { gain *= Float(1-sound.homeSoftness*0.65) }
        if sound.variation { gain *= Float.random(in:0.9...1.1) }
        let pitch = Float(pow(2,(override?.pitch ?? sound.pitch)/12)) * (sound.variation ? Float.random(in:0.98...1.02) : 1)
        let width = sound.width * (headphones ? 0.7 : 1)
        let x = sound.spatial ? Float(KeyGeometry.position(event.key,layout:settings.layout)*width) : 0
        held.remember(HeldSound(bank:bank,gain:gain,pitch:pitch,x:x),key:event.key)
        play(clip,gain:gain,pitch:pitch,x:x)
    }
    private func play(_ buffer: AVAudioPCMBuffer, gain: Float, pitch: Float = 1, x: Float = 0) {
        guard !settings.muted else { return }
        if !graphReady { checkDevices() }
        guard graphReady else { return }
        if !engine.isRunning {
            do { try engine.start() } catch { graphReady = false; deviceSignature = ""; onStatus?("Playback could not resume: \(error.localizedDescription)"); return }
        }
        let now = ProcessInfo.processInfo.systemUptime
        lastActivity = now
        startMotion()
        let voice = voices.first { $0.until <= now } ?? voices.min { $0.until < $1.until }!
        let stealing = voice.until > now
        voice.generation += 1
        let token = voice.generation
        voice.until = now + Double(buffer.frameLength)/buffer.format.sampleRate/Double(max(0.25,pitch)) + 0.01
        let start = {
            guard voice.generation == token else { return }
            voice.player.stop(); voice.player.volume = max(0,min(2,gain)); voice.player.rate = max(0.25,min(4,pitch)); voice.player.position = AVAudio3DPoint(x:x,y:0,z:-1)
            voice.player.scheduleBuffer(buffer); voice.player.play()
            self.scheduledCount += 1
            self.onPlayback?("Playing · \(self.scheduledCount) sounds scheduled")
        }
        if stealing {
            let volume = voice.player.volume
            voice.player.volume = volume*0.66
            queue.asyncAfter(deadline:.now()+0.001) { if voice.generation == token { voice.player.volume = volume*0.33 } }
            queue.asyncAfter(deadline:.now()+0.003,execute:start)
        } else { start() }
        idleTimer?.cancel()
        let timer = DispatchSource.makeTimerSource(queue:queue)
        let deadline = max(now+8,voices.map(\.until).max() ?? now)
        timer.schedule(deadline:.now()+max(0.1,deadline-now),leeway:.milliseconds(100))
        timer.setEventHandler { [weak self] in self?.suspendNow() }; timer.resume(); idleTimer = timer
    }
    private func startMotion() {
        guard settings.sound.spatial else { return }
        if settings.sound.headTracking && headphones && !motion.isDeviceMotionActive {
            guard motion.isDeviceMotionAvailable else {
                lastOrientation = .init(yaw:0,pitch:0,roll:0)
                environment.listenerAngularOrientation = lastOrientation
                onMotion?("Head tracking unavailable; ordinary spatial audio is active."); startOrbit(); return
            }
            motion.startDeviceMotionUpdates(to:motionQueue) { [weak self] data,error in
                guard let self else { return }
                self.queue.async {
                    guard self.settings.sound.headTracking else { return }
                    guard let data, error == nil else {
                        self.lastOrientation = .init(yaw:0,pitch:0,roll:0)
                        if !self.settings.sound.orbit { self.environment.listenerAngularOrientation = self.lastOrientation }
                        self.onMotion?("No headphone motion data; ordinary spatial audio is active."); return
                    }
                    self.latestYaw = data.attitude.yaw
                    self.lastOrientation = .init(yaw:Float((data.attitude.yaw-self.yawOffset)*180 / .pi),pitch:Float(data.attitude.pitch*180 / .pi),roll:Float(data.attitude.roll*180 / .pi))
                    if !self.settings.sound.orbit { self.environment.listenerAngularOrientation = self.lastOrientation }
                    self.onMotion?("Head tracking active")
                }
            }
        }
        startOrbit()
    }
    private func startOrbit() {
        guard settings.sound.orbit, orbitTimer == nil else { return }
        let timer = DispatchSource.makeTimerSource(queue:queue)
        timer.schedule(deadline:.now(),repeating:1.0/30,leeway:.milliseconds(5))
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            let degrees = Float(ProcessInfo.processInfo.systemUptime.truncatingRemainder(dividingBy:8)/8*360)
            self.environment.listenerAngularOrientation = .init(yaw:degrees+self.lastOrientation.yaw,pitch:0,roll:0)
        }; timer.resume(); orbitTimer = timer
    }
    func recenter() { queue.async { self.yawOffset = self.latestYaw; self.lastOrientation = .init(yaw:0,pitch:0,roll:0); self.environment.listenerAngularOrientation = self.lastOrientation } }
    func reset() { queue.async { self.previewGeneration += 1; self.held.clear(); self.fadeStop() } }
    func recover() { queue.async { self.deviceSignature = ""; self.checkDevices(); self.prepare(self.settings) } }
    private func fadeStop() {
        let activity = lastActivity
        let stopping = voices.map { ($0,$0.generation) }
        for voice in voices { voice.player.volume *= 0.3 }
        queue.asyncAfter(deadline:.now()+0.003) {
            if self.lastActivity <= activity { self.stopImmediately() }
            else { for (voice,generation) in stopping where voice.generation == generation { voice.player.stop(); voice.until = 0 } }
        }
    }
    private func stopImmediately() {
        for voice in voices { voice.generation += 1; voice.player.stop(); voice.until = 0 }
        held.clear(); engine.stop(); motion.stopDeviceMotionUpdates(); orbitTimer?.cancel(); orbitTimer = nil; idleTimer?.cancel(); idleTimer = nil
    }
    private func suspendNow() { stopImmediately(); onPlayback?("Audio suspended after idle · \(scheduledCount) sounds scheduled") }
    func cancelPreview() { queue.async { self.previewGeneration += 1 } }
    func preview(profile: String? = nil, effect: String? = nil, key: Int = 0) {
        queue.async {
            self.previewGeneration += 1
            let token = self.previewGeneration, snapshot = self.settings
            let override = profile == nil ? snapshot.sound.overrides[key] : nil
            let id = profile ?? override?.profile ?? snapshot.sound.profile
            let tone = override?.tone ?? snapshot.sound.tone
            if let effect, effect == "none" { return }
            if let effect, effect != "default" {
                if let bank = self.banks[effect] { self.previewBank(bank,key:key,token:token,effect:effect,override:override); return }
                guard let item = snapshot.imports.first(where:{$0.id == effect}) else { self.onStatus?("Imported preview is unavailable."); return }
                self.worker.async {
                    do {
                        let bank = try PreparedBank.imported(item,root:self.importsRoot)
                        self.queue.async { self.previewBank(bank,key:key,token:token,effect:effect,override:override) }
                    } catch { self.onStatus?(error.localizedDescription) }
                }
                return
            }
            let bankKey = self.bankKey(id,tone)
            if let bank = self.banks[bankKey] { self.previewBank(bank,key:key,token:token,effect:effect,override:override); return }
            guard SoundProfile.find(id) != nil else { return }
            self.worker.async {
                do {
                    let bank = try PreparedBank.load(profile:id,tone:tone,root:self.root,processor:ToneProcessor())
                    self.queue.async { self.previewBank(bank,key:key,token:token,effect:effect,override:override) }
                } catch { self.onStatus?(error.localizedDescription) }
            }
        }
    }
    private func previewBank(_ bank: PreparedBank, key: Int, token: Int, effect: String?, override: KeyOverride?) {
        guard token == previewGeneration else { return }
        let volume = effect == nil ? settings.sound.volume : (key >= 1000 ? settings.sound.mouseVolume : settings.sound.enterVolume)
        let gain = Float(volume*(override?.volume ?? 1)) * (settings.sound.normalization ? bank.normalization : 1)
        for i in 0..<3 {
            for down in [true,false] {
                queue.asyncAfter(deadline:.now()+Double(i)*0.22+(down ? 0 : 0.08)) {
                    guard token == self.previewGeneration, let clip = bank.sample(key:key,down:down) else { return }
                    self.play(clip,gain:gain,pitch:Float(pow(2,(override?.pitch ?? self.settings.sound.pitch)/12)),x:0)
                }
            }
        }
    }
    func cue(enabled: Bool) {
        worker.async {
            do {
                let clip = try AudioFiles.decode(self.root.appendingPathComponent("Cues/\(enabled ? "enable" : "disable").wav"))
                self.queue.asyncAfter(deadline:.now()+0.006) { self.play(clip,gain:0.15) }
            } catch { self.onStatus?(error.localizedDescription) }
        }
    }
}
