# Verification and acceptance ledger

Date: **2026-09-10**. Host: Apple Silicon MacBook Air, Xcode 27.0 (27A5252f), Swift 6.4; project language mode Swift 5, deployment target macOS 15. Tests ran on the current host, not a macOS 15 installation.

**Current scope: 11 bundled sound profiles.** The user removed unavailable sounds and recording dependencies from the requested app. Hardware, permission, and performance verification remains limited as detailed below; earlier catalog counts describe historical builds.

## Board 0.3.0 — available sounds only

Removed all twelve unavailable catalog entries, their thumbnails, pending-recording copy, and the unused novelty filter. Menus, settings, and key overrides use the same eleven-profile catalog. The asset manifest now lists actual assets only. Saved current/preset profiles that reference removed IDs fall back to Alpaca; missing per-key profile overrides inherit the global profile while preserving their tone, pitch, and volume.

Installed and signature-verified at `/Applications/Board.app` on this Mac and the configured Mac mini. Only the local Applications copy is running; it reports **Listening to physical input** and its sound count advances. The Mac mini still needs its own first-launch Input Monitoring approval. All seven tests pass. See `Docs/board-0.3.0-verification.txt`.

This update supersedes the recording dependency lists in earlier delivery notes. The original recording plan remains as historical source documentation, not an installation prerequisite.

## Board 0.2.0 update — 2026-09-10

The current package is `dist/Board.app`. Window, app menu, status-menu labels, About, and bundle display/executable names are Board. The internal bundle identifier and import folder are retained to preserve user data. Live launch preserved the previous sound/output preferences. macOS nevertheless reported **Input Monitoring required** for this rebuilt binary; access must be re-enabled before system-wide typing playback resumes.

Added **Classic · Typewriter** using four CC0 recordings by Cassie-OrbitGames. Complete strokes play on press only, with no synthetic release sound. Leading silence is trimmed while retaining a 2 ms attack margin and the full decay. The catalog now has ten mechanical packs plus Typewriter (eleven available profiles). Source originals, source-page capture, processing script, author/license, and hashes are preserved. Native tests pass, the signed Release package verifies, the picker exposes Typewriter, and a real-time production-pipeline probe measured nonzero output before and after idle. See `Docs/board-test-results.txt`. Other hardware acceptance items below remain unchanged.

## Automated evidence

The app builds in Debug and Release. The native XCTest target passes **seven tests**, covering:

1. Unique down/up transitions, repeat suppression, simultaneous modifier/button identifiers, reset, and repeated-key shortcut timing.
2. ANSI/ISO/JIS geometry uniqueness, bounds and overlap; physical labels, spatial sides, row-specific sample names, and combo/dismiss/shuffle timing.
3. Versioned settings/preset round-trip and bounded settings; managed import path validation.
4. Every acquired sound pack decoding and down/up key mapping; finite offline tone output and retained press-time release association.
5. Invalid audio and overlong import rejection before configuration replacement; managed copies, silent absent releases, and new seven-group recording mappings.
6. Offline spatial left/right energy separation, finite output and peak protection with 32 simultaneous voices.
7. App icon colors: settings saved before the picker still load, unknown colors are cleared, and all five bundled icons load.

2026-10-25: after the audit fixes the suite has eleven tests, adding a decoded-size bound, import copies (source swapped after copying, failed second copy), clamped saved presets, and keystroke labels cleared on a Space change. All eleven passed on the test Mac m1 (macOS 26.5.1), first as logic tests under Xcode 27's `xctest` (SwiftPM build of the same sources) while m1 had no Xcode. Later the same day AI mode and its hook installer brought the suite to seventeen tests, and the app-hosted `bash Scripts/test.sh` passed all 17 on m1 with Xcode 27.0 (27A5252f) at commit `42d4efb` (`** TEST SUCCEEDED **`). The Xcode test target compiles (`build-for-testing`). Against the pre-fix code, the new decoded-size, preset and Space tests fail.

Run `bash Scripts/test.sh`. Full result bundle: `build/DerivedData/Logs/Test/` (path in `Docs/test-results.txt`); concise exported results: `Docs/test-results.txt`.

Build and bundle evidence: `Docs/build-results.txt`. The final packaged executable is arm64; all 121 shipped source clips and other manifest-listed bundle resources passed SHA-256 comparison.

Signing, updated 2026-10-24: `Scripts/build.sh` signs `dist/Board.app` with the keychain's Developer ID Application identity, hardened runtime and a secure timestamp. When it has to fall back to the local `NotAHotDog Signing` identity or an ad-hoc signature, it prints a warning. A 2026-10-24 check found the installed 0.3.0 app Developer ID-signed with a timestamp but not notarized. `bash Scripts/build.sh --notarize` adds notarization, stapling and the Gatekeeper check (see the README); it has not been run against Apple yet. The 2026-10-25 package built from this checkout (`dist/Board.app`) is Developer ID-signed with hardened runtime and a secure timestamp (`codesign -dvv`). The 2026-09-10 package was ad-hoc signed; `codesign --verify --deep --strict` reported it **valid on disk** and **satisfies its Designated Requirement**.

## Live checks performed

- Launched the Debug, Release and packaged app; Settings renders with the six requested sections.
- Permission absent: the UI says **Input Monitoring required** and shows one button: **Request Input Monitoring**, which becomes **Open Input Monitoring Settings** after one click. No buttons show while listening.
- Activated sidebar navigation, local preview and physical-key buttons through accessibility APIs. Selecting S changes the key editor and physical-key selection to S/code 1.
- Local preview without input permission schedules three press/release pairs. Diagnostics advanced to six sounds, then reported idle suspension. Another preview resumed scheduling after suspension.
- Built-in selected output read back **44,100 Hz and 128 frames**. These are device configuration values, not input-to-audible latency.
- Closed and reopened Settings with both Dock and menu icons disabled; Settings reappeared and both preferences remained disabled. Restored the menu icon afterwards.
- Rendered and inspected keyboard/combo theme previews from runtime views. Saved dated public App Store screenshots and icon references separately from shipped resources.
- Source inspection found no network client, Unicode/text extraction, input posting or input synthesis calls. The app's source never logs individual key events. This is a code audit; it is not a packet-capture claim about every system framework or daemon.

Accessibility activation was checked for representative controls; a complete VoiceOver and keyboard-only walkthrough remains pending. Dark/Light keyboard themes were rendered, but the entire native Settings interface has not been manually audited in both OS appearances.

## Performance

`Docs/idle-measurement.json` records a 30-second cumulative CPU-time measurement with overlays off, Settings visible, and Input Monitoring ungranted. The final packaged Release build used **0.066% average CPU** and **117.2 MB peak RSS** over 30.33 seconds. This meets the idle CPU target in this measured scenario; consult the JSON for the exact result.

Not established: active typing CPU under 5%, ten-minute audible dropout performance, display-rate animation, warm audible latency under 15 ms, or cold-resume audible latency. The offline render and resume scheduling checks do not prove these hardware targets. Bluetooth latency must be measured independently.

## Stage acceptance

| Stage | Delivered | Acceptance still needed |
| --- | --- | --- |
| 1 — Foundation | Onboarding, native menus, passive session tap, normalization, ten real packs | Real system-wide typing after user grants Input Monitoring; grant/revoke/restore and Secure Input behavior |
| 2 — Sound | 32 voices, tone preparation, spatial/device controls, imports, overrides, favorites, motion/orbit paths | Wired/USB/Bluetooth changes, motion headphones, sleep/wake, listening checks and actual microphone/loopback latency measurement |
| 3 — Interface | Six Settings sections, four overlays, positioning, themes, shortcuts, Dock/menu preferences | Fullscreen/Spaces/external-display reconnection, Reduced Motion, all keyboard/IME/media combinations, complete accessibility walkthrough |
| 4 — Assets | Brand-package app icons and menu glyph, original thumbnails and theme previews | Eleven authentic keyboard packs, mouse/Enter/Lizard Foley; full visual comparison and interaction matrix |
| 5 — Packaging | Reproducible Xcode project, Release app, source manifest, guides, native tests | Remaining hardware matrix, minimum-OS execution, performance/latency targets, final asset completion |

## Hardware matrix to run with the user

| Case | Status / procedure |
| --- | --- |
| Input permission denied | Verified visible unavailable state and local previews |
| Granted/revoked/restored | Grant observed on a macOS 27.0.1 VM (2026-10-11, previous three-button build): the first request shows macOS's Keystroke Receiving prompt; after Deny, further requests show nothing; after granting, status changed only after Quit & Reopen (Retry and reactivation did not pick it up). Revoke/restore pending |
| ANSI/ISO/JIS | Geometry and mappings tested; physical hardware pending |
| Modifiers, Caps Lock, media keys, IME | Normalizer tested; real event sequences pending. Caps Lock flags reflect lock state and its actual physical release timing needs device verification |
| Built-in speakers | Output identification, 128-frame read-back, local playback scheduling and resume verified |
| Wired/USB output | Pending hardware; select by UID, unplug/replug, check fallback and remembered preference |
| Bluetooth without motion | Pending hardware; test pause policy, sample-rate changes and independent latency |
| Supported motion headphones | Pending hardware and motion permission; recenter, stop data, disable spatial, confirm neutral fallback |
| Lock/unlock, sleep/wake | Recovery paths implemented; repeated manual cycles pending |
| Displays/Spaces/fullscreen | Positioning and observer paths implemented; physical multi-display matrix pending |
| Brand accent | 2026-10-25: Settings moved to the standard macOS sidebar and grouped form, and its controls use the system accent color; the hand-drawn sidebar and its focus ring are gone. Only the visualizer's keys and Settings' keyboard drawings follow the chosen icon color. Live on the test Mac (macOS 26.5.1), light and dark: native sidebar 210 pt wide with the window buttons inside it and no sidebar toggle, the selected row in the system accent when the sidebar has focus and grey when it doesn't, no focus ring, Up/Down move between sections. Earlier offscreen renders of the brand-tinted controls no longer apply |
| Login item | Uses SMAppService. On macOS 27.2 a never-registered app reports `notFound` (seen with a throwaway test app), so Board shows it as "Off". Installed build, background AX presses: Off → checked "Enabled" → unchecked "Off", no errors. Startup at login itself not tested |
| Hidden menu and Dock | Reopening restored Settings; menu visibility returned to default |

## Remaining product differences and limits

- Ten of 21 mechanical profiles are available. Lizard and recorded Enter/mouse families are unavailable. The interim keyboard default is Alpaca; mouse Default deliberately uses the selected keyboard sample, and Enter None is silence.
- Mouse/Enter menus use native checkbox rows so pointer/accessibility auditions can stay open. A full keyboard-only menu walkthrough is still pending.
- The head-tracked renderer uses native Core Motion/AVAudioEnvironmentNode. No custom HRTF or undocumented system APIs are used; physical behavior remains to be validated.
- The bezel animation recreates the documented behavior with original geometry; pixel-identical artwork, original animation curves, and exact visual parity are not claimed.
- Prepared-bank limit is 256 MB; old banks remain referenced until corresponding releases and pending auditions finish. No process memory ceiling of 256 MB is claimed.
- Rebuilding an ad-hoc app can affect macOS permission identity. Grant access to the final app at a stable path, and recheck access after rebuilding.

## Complete the recording dependency

Follow `Docs/RECORDING.md`: 56 authentic clips per missing mechanical profile (616 total), 90 mouse clips, Enter Foley/vocals and eight Lizard clips. Update provenance and SHA-256 records before enabling any missing profile. Only then can full asset parity and the final acceptance gate pass.
