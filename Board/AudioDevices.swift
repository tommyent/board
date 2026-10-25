import Foundation
import CoreAudio
import AudioToolbox

struct AudioDevice: Identifiable, Equatable {
    var id: AudioDeviceID
    var uid: String
    var name: String
    var headphones: Bool
    var sampleRate: Double
    static func address(_ selector: AudioObjectPropertySelector, scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> AudioObjectPropertyAddress {
        .init(mSelector:selector,mScope:scope,mElement:kAudioObjectPropertyElementMain)
    }
    static func value<T: BitwiseCopyable>(_ id: AudioObjectID, _ selector: AudioObjectPropertySelector, default fallback: T, scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> T {
        var a = address(selector,scope:scope), result = fallback, size = UInt32(MemoryLayout<T>.size)
        _ = withUnsafeMutablePointer(to:&result) { AudioObjectGetPropertyData(id,&a,0,nil,&size,$0) }
        return result
    }
    static func string(_ id: AudioObjectID, _ selector: AudioObjectPropertySelector) -> String {
        var a = address(selector), string: CFString = "" as CFString, size = UInt32(MemoryLayout<CFString>.size)
        guard withUnsafeMutablePointer(to:&string, { AudioObjectGetPropertyData(id,&a,0,nil,&size,$0) }) == noErr else { return "" }
        return string as String
    }
    static var defaultID: AudioDeviceID { value(AudioObjectID(kAudioObjectSystemObject),kAudioHardwarePropertyDefaultOutputDevice,default:AudioDeviceID(0)) }
    static func list() -> [AudioDevice] {
        var a = address(kAudioHardwarePropertyDevices), size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject),&a,0,nil,&size) == noErr else { return [] }
        var ids = [AudioDeviceID](repeating:0,count:Int(size)/MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject),&a,0,nil,&size,&ids) == noErr else { return [] }
        return ids.compactMap { id in
            var streams = address(kAudioDevicePropertyStreams,scope:kAudioDevicePropertyScopeOutput), streamSize: UInt32 = 0
            guard AudioObjectGetPropertyDataSize(id,&streams,0,nil,&streamSize) == noErr, streamSize > 0 else { return nil }
            let name = string(id,kAudioObjectPropertyName)
            let transport = value(id,kAudioDevicePropertyTransportType,default:UInt32(0))
            let source = value(id,kAudioDevicePropertyDataSource,default:UInt32(0),scope:kAudioDevicePropertyScopeOutput)
            // Unknown USB/Bluetooth products can be corrected using the explicit output-kind override.
            let headphones = source == 0x6864706e || name.localizedCaseInsensitiveContains("headphone") || name.localizedCaseInsensitiveContains("airpods") || (transport == kAudioDeviceTransportTypeBluetooth && !name.localizedCaseInsensitiveContains("speaker"))
            return AudioDevice(id:id,uid:string(id,kAudioDevicePropertyDeviceUID),name:name,headphones:headphones,sampleRate:value(id,kAudioDevicePropertyNominalSampleRate,default:48000.0))
        }
    }
    static func requestBuffer(_ id: AudioDeviceID) -> UInt32 {
        var a = address(kAudioDevicePropertyBufferFrameSize), size = UInt32(MemoryLayout<UInt32>.size), frames: UInt32 = 128
        // The HAL keeps this per process: with Board-style 128 frames set, another process still read 512 and got its usual
        // callback size, and nothing persisted after exit (m1, macOS 26.5.1, built-in speakers, 2026-10-25). So no restore is needed.
        // A device may reject the request; report the read-back, never the requested value.
        _ = AudioObjectSetPropertyData(id,&a,0,nil,size,&frames)
        _ = AudioObjectGetPropertyData(id,&a,0,nil,&size,&frames)
        return frames
    }
}
