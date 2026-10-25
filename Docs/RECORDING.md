# Recording and completion guide

## Outstanding authentic mechanical recordings

| ID | Required hardware |
| --- | --- |
| mq80 | IQUNIX MQ80 |
| surfer | Lofree Flow 2 Surfer |
| void | Lofree Flow 2 Void |
| pulse | Lofree Flow 2 Pulse |
| piano | Akko Piano Pro |
| jelly | Akko CS Jelly Black |
| yellow | Akko V3 Cream Yellow Pro |
| pink | Akko Clicky Pink |
| k2red | Keychron K2 Max with K Pro Red |
| k2brown | Keychron K2 Max with K Pro Brown |
| carrot | Aflion Carrot Orange |

Borrow matching hardware where possible; no equipment purchase is assumed. A loose-switch tester does not reproduce a complete keyboard's sound. Never relabel a different board's recording to fill these entries.

## Capture

Use a quiet room and a fixed microphone. Disable automatic gain and noise suppression. Record lossless 48 kHz / 24-bit when supported. Capture four isolated down/up pairs for each of these seven groups:

`GENERIC`, `SPACE`, `ENTER`, `BACKSPACE`, `TAB`, `SHIFT`, `MODIFIER`.

Hold each key long enough to separate downstroke from release. Capture a short natural typing sequence as a listening reference. Record board, switch, keycaps, microphone, microphone distance/angle, recorder settings, lubrication/modifications, date, owner/performer, and permission/license to reuse the recording. Retain the untouched source take.

This is **56 clips per new profile, 616 clips for eleven profiles**. Do not synthesize fake variants or duplicate existing clips to inflate coverage.

## Edit and name

Trim before the transient without removing the attack, retain natural decay, remove DC offset, and use short boundary fades. Preserve press/release relative loudness. Export mono PCM WAV. Do not individually normalize every sample; profile normalization must preserve the relative dynamics.

Use this directory layout inside `Board/Resources/Audio/<id>/`:

```text
press/GENERIC_1.wav ... GENERIC_4.wav
release/GENERIC_1.wav ... GENERIC_4.wav
press/SPACE_1.wav ... SPACE_4.wav
release/SPACE_1.wav ... SPACE_4.wav
... repeat for ENTER, BACKSPACE, TAB, SHIFT, MODIFIER
```

The loader supports these groups/variants. It chooses a real variant for each hit. Existing kbsim packs retain their original row-specific press files and generic releases. `GENERIC_R0`–`GENERIC_R4` represent rows, not fabricated random variants. Tab/Shift/modifier mappings in those existing packs use the original row press and generic release.

Before setting `available: true` for a catalog entry in `Models.swift`, validate all 56 files, update the per-file manifest, run the native tests and listen to the reference sequence. After `k2red` passes, change the initial `SoundConfiguration.profile` to `k2red`; existing user preferences remain unchanged.

The loader converts to mono 48 kHz Float32, removes DC and applies a 1 ms boundary fade while preparing playback. Tone uses a reusable offline two-shelf native EQ. Normalization measures a fixed 14-key down/up sequence at 250 ms per key and uses a 0.04 RMS target with bounded gain; this is an implementation reference, not a perceptual matching claim.

## Other source recordings

- **Mouse:** five distinct families across hard-to-soft and Kalabit-style character. Left, right, and middle, down/up, three variants each = **90 clips**. Record the device model and surface. These are not supplied by the keyboard packs.
- **Enter:** real stamp, borrowed typewriter carriage return, bell or toaster ding, and original Pho/Faah-style vocal performances. Do not lift someone else's voice or the original app's audio.
- **Lizard:** original tongue-click/chirp Foley, four down/up pairs = **8 clips**.
- **Toggle cues:** included; native sine-tone synthesis, two generated WAVs. Reproduce with `python3 Scripts/prepare_manifest.py`.

Enter and mouse custom imports already support one sound or separate press/release files via Settings. Imports accept WAV, AIFF, CAF, M4A and MP3; each must be nonempty, decode to finite samples, be at most 30 seconds, and be no larger than 25 MB. Failed validation leaves the previous setting intact.

## Source record template

For each prepared clip add a record to the asset manifest:

```json
{
  "path": "Board/Resources/Audio/k2red/press/SPACE_1.wav",
  "source": "original-takes/<recording>.wav, time range",
  "author": "recorder / performer",
  "date": "YYYY-MM-DD",
  "license": "explicit recording permission or license",
  "hardware": "board, switch, keycaps, modifications",
  "capture": "microphone and position, sample rate, bit depth",
  "processing": "trim range, DC removal, fade lengths, mono conversion",
  "sha256": "digest of prepared file"
}
```

A completed catalog requires actual distinct recordings and documented sources, not just enabled menu entries.
