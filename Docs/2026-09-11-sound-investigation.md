# Intermittent sound investigation — 2026-09-11

Scope: this MacBook Air. User was asked which Mac and what preceded the recovery; no answer was available during this investigation.

## Established facts

- The sole running copy is `/Applications/Board.app`, version 0.3.0, PID 63087, started September 10 at 16:29:15 EDT.
- Its executable matches the previously verified 0.3.0 build (SHA-256 07119a85d6bdf96596662b9c44490189a32bc1c9641e21ace414c78c50dcb4e6).
- Power logs show a full wake at 04:18:15 EDT on September 11. The display turned off at 04:18:45 and on again at 04:19:09.
- Board stopped/rebuilt an already idle audio engine around wake. The first subsequent audio-engine start in the captured logs occurred at 04:32:28.471; speaker output started at 04:32:28.502. This is a roughly 14-minute gap after wake, not proof that the user typed continuously during that gap.
- Current UI: enabled, unmuted, Typewriter selected, volume approximately 50%, system-default MacBook Air Speakers, pause-on-headphones off, prepared bank ready.
- No Board audio-start failure or relevant TCC denial/approval message was found in the selected interval. Absence of a log entry does not prove absence of a fault.

## Mechanisms and limits

`InputMonitor.refresh()` checks every two seconds. It recreates/re-enables the event tap when permission, Secure Input, or session suspension allows it. Secure Input and sleep/session-inactive state stop monitoring. The audio engine separately suspends after eight idle seconds and starts on its next accepted sound. Audio devices are checked every two seconds.

The current build does not persist transitions of input status, enable/mute settings, or filtering decisions. Existing system logs therefore cannot distinguish a paused event tap, Secure Input, a setting change, or simply the first accepted physical input at 04:32. The successful 04:32 engine start is not itself evidence of a fourteen-minute audio-device failure.

Wake/input-monitoring recovery is a candidate, not a confirmed root cause. No code, app package, permissions, or audio settings were changed during this investigation. A timestamped, key-free state-transition diagnostic would be necessary to establish the next occurrence if the behavior cannot be reproduced on demand.

## Selected system evidence

```text
2026-09-11 04:18:15.256 Df Board[63087:1f4fdb] [com.apple.avfaudio:avae]          AVAudioEngine.mm:1345  Engine@0x74f6525850: stop, was running 0
2026-09-11 04:18:15.256 Df Board[63087:1f4fdb] [com.apple.avfaudio:avae]          AVAudioEngine.mm:1345  Engine@0x74f6525850: stop, was running 0
2026-09-11 04:32:28.471 Df Board[63087:1fa294] [com.apple.avfaudio:avae]          AVAudioEngine.mm:1282  Engine@0x74f6522520: start, was running 0
2026-09-11 04:32:28.502 Df Board[63087:1fa294] [com.apple.coreaudio:as_client] SessionCore_macOS_Legacy.mm:163   --> setPlayState Started  Output {BuiltInSpeakerDevice, 0x2b}
```
