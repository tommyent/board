import AVFoundation

struct AudioValidationError: LocalizedError {
    var message: String
    var errorDescription: String? { message }
}

enum AudioFiles {
    static let format = AVAudioFormat(standardFormatWithSampleRate:48000,channels:1)!
    static let maxFileSize = 25 * 1024 * 1024
    static let maxDecodedSize: Int64 = 64 * 1024 * 1024
    static func decode(_ url: URL, imported: Bool = false) throws -> AVAudioPCMBuffer {
        let size = try url.resourceValues(forKeys:[.fileSizeKey]).fileSize ?? 0
        guard size > 0, size <= maxFileSize else { throw AudioValidationError(message:"Audio must be nonempty and no larger than 25 MB.") }
        if imported, !["wav","aiff","aif","caf","m4a","mp3"].contains(url.pathExtension.lowercased()) { throw AudioValidationError(message:"Choose WAV, AIFF, CAF, M4A, or MP3 audio.") }
        let file = try AVAudioFile(forReading:url)
        let duration = Double(file.length)/file.processingFormat.sampleRate
        guard duration.isFinite, duration > 0, duration <= 30, file.processingFormat.channelCount <= 8 else { throw AudioValidationError(message:"Audio must contain 0–30 seconds and at most eight channels.") }
        // A small compressed file can decode to a huge high-rate multichannel buffer; bound the Float32 frames before allocating.
        guard file.length <= maxDecodedSize / 4 / Int64(max(1,file.processingFormat.channelCount)) else { throw AudioValidationError(message:"Audio is too large once decoded (64 MB limit).") }
        guard let source = AVAudioPCMBuffer(pcmFormat:file.processingFormat,frameCapacity:AVAudioFrameCount(file.length)) else { throw AudioValidationError(message:"Cannot allocate audio buffer.") }
        try file.read(into:source)
        guard let channels = source.floatChannelData else { throw AudioValidationError(message:"Cannot decode floating-point audio.") }
        for channel in 0..<Int(source.format.channelCount) {
            guard (0..<Int(source.frameLength)).allSatisfy({ channels[channel][$0].isFinite }) else { throw AudioValidationError(message:"Audio contains invalid samples.") }
        }
        guard let converter = AVAudioConverter(from:source.format,to:format), let result = AVAudioPCMBuffer(pcmFormat:format,frameCapacity:AVAudioFrameCount(ceil(duration*48000))+64) else { throw AudioValidationError(message:"Unsupported audio format.") }
        var supplied = false, error: NSError?
        converter.convert(to:result,error:&error) { _, state in
            if supplied { state.pointee = .endOfStream; return nil }
            supplied = true; state.pointee = .haveData; return source
        }
        if let error { throw error }
        guard result.frameLength > 0, let data = result.floatChannelData?[0] else { throw AudioValidationError(message:"Decoded audio is empty.") }
        let n = Int(result.frameLength)
        var mean: Float = 0
        for i in 0..<n { guard data[i].isFinite else { throw AudioValidationError(message:"Decoded audio is invalid.") }; mean += data[i]/Float(n) }
        let fade = min(48,n/2)
        for i in 0..<n {
            let envelope = fade > 0 ? min(1,Float(i)/Float(fade),Float(n-1-i)/Float(fade)) : 1
            data[i] = (data[i]-mean)*envelope
        }
        return result
    }
    static func managedURL(_ name: String, root: URL) throws -> URL {
        guard !name.isEmpty, name == URL(fileURLWithPath:name).lastPathComponent, !name.contains("..") else { throw AudioValidationError(message:"Invalid managed audio filename.") }
        return root.appendingPathComponent(name)
    }
    /// `afterCopy` runs between copying and validating; tests use it to swap a source file.
    static func importPair(press: URL, release: URL?, name: String, root: URL, afterCopy: () throws -> Void = {}) throws -> ImportedSound {
        // Read each source once into a bounded copy and validate that copy, so a source changed mid-import can't slip through.
        // Nothing references the copies until this returns, and any failure removes them all.
        let id = UUID().uuidString
        let sources = [("press",press)] + (release.map { [("release",$0)] } ?? [])
        let copies = sources.map { role, source in root.appendingPathComponent(id + "-" + role + "." + source.pathExtension.lowercased()) }
        do {
            try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
            for ((_,source),copy) in zip(sources,copies) {
                let handle = try FileHandle(forReadingFrom:source)
                defer { try? handle.close() }
                let data = try handle.read(upToCount:maxFileSize+1) ?? Data()
                guard data.count <= maxFileSize else { throw AudioValidationError(message:"Audio must be nonempty and no larger than 25 MB.") }
                try data.write(to:copy,options:.atomic)
            }
            try afterCopy()
            for copy in copies { _ = try decode(copy,imported:true) }
        } catch {
            for copy in copies { try? FileManager.default.removeItem(at:copy) }
            throw error
        }
        return ImportedSound(id:id,name:name,press:copies[0].lastPathComponent,release:release == nil ? nil : copies[1].lastPathComponent)
    }
}

final class ToneProcessor {
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let eq = AVAudioUnitEQ(numberOfBands:2)
    init() throws {
        engine.attach(player); engine.attach(eq)
        engine.connect(player,to:eq,format:AudioFiles.format)
        engine.connect(eq,to:engine.mainMixerNode,format:AudioFiles.format)
        try engine.enableManualRenderingMode(.offline,format:AudioFiles.format,maximumFrameCount:4096)
        eq.bands[0].filterType = .lowShelf; eq.bands[0].frequency = 350; eq.bands[0].bypass = false
        eq.bands[1].filterType = .highShelf; eq.bands[1].frequency = 2500; eq.bands[1].bypass = false
    }
    func process(_ input: AVAudioPCMBuffer, tone: Double) throws -> AVAudioPCMBuffer {
        guard abs(tone) > 0.01 else { return input }
        engine.stop(); player.stop(); engine.reset()
        eq.bands[0].gain = Float(-tone*6); eq.bands[1].gain = Float(tone*6)
        guard let result = AVAudioPCMBuffer(pcmFormat:AudioFiles.format,frameCapacity:input.frameLength+2048), let scratch = AVAudioPCMBuffer(pcmFormat:AudioFiles.format,frameCapacity:4096) else { throw AudioValidationError(message:"Cannot prepare tone.") }
        player.scheduleBuffer(input); try engine.start(); player.play()
        var offset = 0, attempts = 0
        let count = Int(input.frameLength)+1024
        while offset < count {
            attempts += 1
            guard attempts < 10000 else { throw AudioValidationError(message:"Tone processing timed out.") }
            let frames = AVAudioFrameCount(min(4096,count-offset))
            let status = try engine.renderOffline(frames,to:scratch)
            if status == .success {
                result.floatChannelData![0].advanced(by:offset).update(from:scratch.floatChannelData![0],count:Int(frames)); offset += Int(frames)
            } else if status == .error { throw AudioValidationError(message:"Tone rendering failed.") }
        }
        result.frameLength = AVAudioFrameCount(offset); player.stop(); engine.stop()
        return result
    }
}

final class PreparedBank {
    let profile: String
    var samples: [String: AVAudioPCMBuffer]
    let normalization: Float
    let bytes: Int
    init(profile: String, samples: [String: AVAudioPCMBuffer], normalization: Float) {
        self.profile = profile; self.samples = samples; self.normalization = normalization
        bytes = samples.values.reduce(0) { $0+Int($1.frameLength)*4 }
    }
    static func options(in samples:[String:AVAudioPCMBuffer],key:Int,down:Bool) -> [AVAudioPCMBuffer] {
        let prefix = down ? "press/" : "release/"
        let group: String
        switch key {
        case 49: group = "SPACE"
        case 36,76: group = "ENTER"
        case 51,117: group = "BACKSPACE"
        case 48: group = "TAB"
        case 56,60: group = "SHIFT"
        case 54,55,57,58,59,61,62,63: group = "MODIFIER"
        default: group = "GENERIC"
        }
        let variants = (1...4).compactMap { samples[prefix+group+"_"+String($0)] }
        if !variants.isEmpty { return variants }
        if let exact = samples[prefix+KeyGeometry.sampleName(key,down:down)] { return [exact] }
        let genericVariants = (1...4).compactMap { samples[prefix+"GENERIC_"+String($0)] }
        if !genericVariants.isEmpty { return genericVariants }
        if let generic = samples[prefix+"GENERIC"] ?? (down ? samples[prefix+"GENERIC_R2"] : nil) { return [generic] }
        return []
    }
    func sample(key: Int, down: Bool) -> AVAudioPCMBuffer? {
        Self.options(in:samples,key:key,down:down).randomElement()
    }
    static func imported(_ item:ImportedSound,root:URL) throws -> PreparedBank {
        let press = try AudioFiles.decode(AudioFiles.managedURL(item.press,root:root))
        var clips = ["press/GENERIC":press]
        if let release = item.release { clips["release/GENERIC"] = try AudioFiles.decode(AudioFiles.managedURL(release,root:root)) }
        return PreparedBank(profile:item.id,samples:clips,normalization:1)
    }
    static func load(profile: String, tone: Double, root: URL, processor: ToneProcessor) throws -> PreparedBank {
        let directory = root.appendingPathComponent("Audio/\(profile)")
        var samples: [String: AVAudioPCMBuffer] = [:]
        for transition in ["press","release"] {
            if transition == "release", SoundProfile.find(profile)?.hasReleaseSamples == false { continue }
            let dir = directory.appendingPathComponent(transition)
            for url in try FileManager.default.contentsOfDirectory(at:dir,includingPropertiesForKeys:nil).sorted(by:{$0.path < $1.path}) where ["mp3","wav","caf","aiff"].contains(url.pathExtension.lowercased()) {
                samples[transition+"/"+url.deletingPathExtension().lastPathComponent] = try processor.process(AudioFiles.decode(url),tone:tone)
            }
        }
        guard samples["press/GENERIC_R2"] != nil || samples["press/GENERIC_1"] != nil,
              SoundProfile.find(profile)?.hasReleaseSamples == false || samples["release/GENERIC"] != nil || samples["release/GENERIC_1"] != nil else { throw AudioValidationError(message:"\(profile) is missing required keystroke samples.") }
        // Fixed physical reference sequence; gain preserves relative levels inside a profile.
        let sequence = [0,1,2,3,38,40,37,41,18,12,6,49,36,51]
        var energy: Double = 0
        for key in sequence {
            for down in [true,false] {
                let options = Self.options(in:samples,key:key,down:down)
                for b in options {
                    if let data = b.floatChannelData?[0] {
                        for i in 0..<Int(b.frameLength) { energy += Double(data[i]*data[i])/Double(options.count) }
                    }
                }
            }
        }
        let rms = sqrt(energy / (Double(sequence.count)*0.25*48000))
        let gain = Float(min(4,max(0.1,0.04/max(0.0001,rms))))
        return PreparedBank(profile:profile,samples:samples,normalization:gain)
    }
}
