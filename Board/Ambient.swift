import AVFoundation
import Carbon

/// A background soundscape ("sound busy wherever you are"): a place built from looping layers, mixed by level.
/// Its own players, separate from the key-sound engine, so the key path is untouched.
struct AmbientPlace: Identifiable, Equatable {
    struct Layer: Identifiable, Equatable {
        let id: String
        let title: String
        let level: Double   // default slider position, 0–1
    }
    let id: String
    let title: String
    let layers: [Layer]
    /// Stand-in 15 s ElevenLabs layers until the owner approves the sound; files are Resources/Ambient/<place>-<layer>.m4a.
    static let all: [AmbientPlace] = [
        .init(id:"office-1950s",title:"Office, 1950s",layers:[.init(id:"room",title:"Room",level:0.7),.init(id:"activity",title:"Typewriters far off",level:0.5),.init(id:"murmur",title:"Murmur",level:0.4)]),
        .init(id:"office-1980s",title:"Office, 1980s",layers:[.init(id:"room",title:"Room",level:0.7),.init(id:"activity",title:"Phones and printers far off",level:0.45),.init(id:"murmur",title:"Murmur",level:0.4)]),
        .init(id:"office-2000s",title:"Office, 2000s",layers:[.init(id:"room",title:"Room",level:0.7),.init(id:"activity",title:"Copier and desks far off",level:0.45),.init(id:"murmur",title:"Murmur",level:0.4)]),
        .init(id:"office-modern",title:"Office, modern",layers:[.init(id:"room",title:"Room",level:0.7),.init(id:"activity",title:"Kitchen and chimes far off",level:0.45),.init(id:"murmur",title:"Murmur",level:0.4)]),
        .init(id:"coffee-shop",title:"Coffee shop",layers:[.init(id:"room",title:"Room",level:0.65),.init(id:"espresso",title:"Espresso machine",level:0.45)]),
        .init(id:"park",title:"Park",layers:[.init(id:"breeze",title:"Breeze and far traffic",level:0.65),.init(id:"birds",title:"Birds",level:0.55)]),
        .init(id:"beach",title:"Beach",layers:[.init(id:"waves",title:"Waves",level:0.4),.init(id:"music",title:"Steel pan",level:0.7)]),
    ]
    static func place(_ id: String?) -> AmbientPlace? { all.first { $0.id == id } }
    static let defaultVolume = 0.5
    func file(_ layer: Layer) -> String { "\(id)-\(layer.id).m4a" }
    func levelKey(_ layer: Layer) -> String { "\(id)/\(layer.id)" }
}

enum AmbientMix {
    /// Slider position (0–1) to gain, squared so the middle of a slider sounds like the middle.
    static func gain(_ level: Double) -> Float { Float(min(1,max(0,level))*min(1,max(0,level))) }
    /// Each layer's player volume: master × layer, both through the taper. Saved levels override the defaults.
    static func volumes(_ place: AmbientPlace, master: Double, levels: [String:Double]) -> [String:Float] {
        Dictionary(uniqueKeysWithValues:place.layers.map { ($0.id, gain(master)*gain(levels[place.levelKey($0)] ?? $0.level)) })
    }
}

/// Plays the chosen place's layers as endless loops, starting them together, and pauses or resumes them with Board's
/// pause rules. Secure Input has no notification, so while a place is chosen the rules are checked twice a second.
@MainActor final class AmbientPlayer {
    var canPlay: () -> Bool = { true }   // Board's own rules (off, muted, inactive session); Secure Input is checked here
    var onStatus: ((String) -> Void)?
    let root: URL
    private(set) var placeID: String?
    private var players: [String:AVAudioPlayer] = [:]
    private var timer: Timer?
    private var running = false   // our own state: a player scheduled with play(atTime:) may not report isPlaying yet
    init(root: URL) { self.root = root }
    var layerIDs: [String] { players.keys.sorted() }
    var isPlaying: Bool { players.values.contains { $0.isPlaying } }
    func volume(_ layer: String) -> Float? { players[layer]?.volume }
    func configure(place id: String?, master: Double, levels: [String:Double]) {
        guard let place = AmbientPlace.place(id) else { stop(); onStatus?("Off"); return }
        if place.id != placeID { load(place) }
        guard placeID != nil else { return }
        for (layer,volume) in AmbientMix.volumes(place,master:master,levels:levels) { players[layer]?.volume = volume }
        update()
    }
    func stop() {
        timer?.invalidate(); timer = nil
        players.values.forEach { $0.stop() }
        players = [:]; placeID = nil; running = false
    }
    private func load(_ place: AmbientPlace) {
        stop()
        do {
            for layer in place.layers {
                let player = try AVAudioPlayer(contentsOf:root.appendingPathComponent(place.file(layer)))
                player.numberOfLoops = -1; player.volume = 0; player.prepareToPlay()
                players[layer.id] = player
            }
        } catch { players = [:]; onStatus?("Can't load \(place.title): \(error.localizedDescription)"); return }
        placeID = place.id
        timer = Timer.scheduledTimer(withTimeInterval:0.5,repeats:true) { [weak self] _ in MainActor.assumeIsolated { self?.update() } }
    }
    /// Pauses or resumes every layer together. The first start schedules all layers on one device time, so they stay in step.
    private func update() {
        guard let first = players.values.first else { return }
        let play = canPlay() && !IsSecureEventInputEnabled()
        if play, !running {
            let start = first.deviceCurrentTime + 0.05
            players.values.forEach { $0.play(atTime:start) }
            running = true; onStatus?("Playing")
        } else if !play, running {
            players.values.forEach { $0.pause() }
            running = false; onStatus?("Paused while Board's sounds are paused")
        }
    }
}
