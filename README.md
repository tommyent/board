# Board

A native, offline macOS app that plays mechanical keyboard and typewriter sounds as you type. Requires **Apple Silicon and macOS 15+**. No packages, account, server, purchase verification, or admin privileges are used.

**Current sound catalog: 11 complete profiles.** Ten mechanical keyboard packs plus Typewriter are included. Every listed profile has bundled audio; unavailable profiles and recording placeholders have been removed. Remaining hardware verification is tracked in [the acceptance ledger](Docs/VERIFICATION.md).

## Build and run

Open `Board.xcodeproj`, select the **Board** scheme and **My Mac**, then Run. The project has one app target and one XCTest target and uses only Apple frameworks. Xcode's own builds are ad-hoc signed.

From this checkout:

```sh
bash Scripts/build.sh
```

The packaged app is `dist/Board.app`. Build output and previous packages stay inside `build/`. Nothing installs into `/Applications`, registers login items, grants permissions, or changes developer settings during the build.

`Scripts/build.sh` signs the package with the keychain's **Developer ID Application** identity, hardened runtime and a secure timestamp. If there is none, it falls back to the local `NotAHotDog Signing` identity, then to an ad-hoc signature, and prints a warning: such a build runs only on this Mac. To choose an identity, set `BOARD_CODESIGN_IDENTITY` to its SHA-1 hash or full name.

### Notarize for other Macs

```sh
bash Scripts/build.sh --notarize
```

This requires the Developer ID identity. It uploads a ZIP of `dist/Board.app` to Apple's notary service and waits up to an hour. If Apple rejects it, the script prints Apple's log and stops. If Apple accepts it, the script staples the ticket to `dist/Board.app` and checks the result with `stapler validate` and `spctl -a -vvv -t exec`. Builds without `--notarize` never contact Apple.

One-time setup: store notarytool credentials in the keychain under the profile name `board-notary` (or set `BOARD_NOTARY_PROFILE` to another name):

```sh
xcrun notarytool store-credentials board-notary --apple-id <your Apple ID email> --team-id <TEAM_ID>
```

`<TEAM_ID>` is the ten characters in parentheses after the Developer ID Application name in `security find-identity -v -p codesigning`. notarytool then asks for an app-specific password; Apple explains how to create one in [Sign in to apps with your Apple Account using app-specific passwords](https://support.apple.com/en-us/102654). By default, notarytool checks the credentials with Apple before saving them.

For a stable permission identity, keep the final `.app` at a stable location. Launch it, choose **Request Input Monitoring**, and enable Board in macOS System Settings if you want system-wide sounds. macOS offers the request prompt only once; after that the button opens the Input Monitoring settings instead. After turning Board on, choose **Quit & Reopen** when macOS asks. Local previews work without permission.

Reopening Board always opens Settings, including when both the menu and Dock icons are hidden. The default toggle shortcut is **Control–Option–Command–K**; its key and tap count can be changed in General.

Choose **Sound → Switch → Classic · Typewriter** to use the new sound. The recordings contain complete strokes and play once per press.

## Included

- Native status menu; six Settings sections; onboarding, permission status, mute and independent volumes.
- One listen-only session event tap; transition deduplication, repeat suppression, Secure Input pause, sleep/session reset and permission retry.
- 32 preloaded playback voices, authentic down/up samples, native spatial output, limiter, offline tone preparation, gain/pitch variation and home-row softness.
- Per-key overrides, six favorites, validated native audio imports, device UID preferences, output-kind override, optional motion tracking and an eight-second orbit mode.
- Keyboard, keystroke pills, combo and bezel visualizers; ANSI/ISO/JIS layouts, position/scale/theme/timing controls, six pins and random placement.
- AI mode: a sound cue for your coding agents. While one works, Board types along, with sounds and the visualizer only; Rex tells Board when an agent is working. See [AI mode](#ai-mode).
- Five app icon colors from the Board Keycap brand package: Porcelain (the bundled icon), Sage, Blue, Lilac and Graphite. Settings › General › App icon changes Board's Dock icon while it runs; Finder and Launchpad keep Porcelain. The visualizer's key highlights follow the chosen color: the brand's strong accent in light mode, the pale finish in dark mode. Settings uses the standard macOS sidebar, forms and controls, in your system accent color.
- App icons and menu bar glyph from the Board Keycap brand package, theme previews, source/license manifests and a recording guide.

The default profile is **Durock Alpaca**. Mouse and Enter sounds support None, the selected keyboard profile, or imported recordings.

## AI mode

AI mode is a sound cue for your coding agents. Turn on **Settings › Extras › AI mode**, and while a coding agent works, Board types along, so you can hear when it's busy and when it stops. It only plays key sounds and drives the visualizer. It never posts key events, so nothing is typed into your apps, and `Scripts/build.sh` fails if the app ever links an event-posting API.

- **Rex provides the agent status.** Board learns whether an agent is working from Rex, the terminal your agents run in: it asks Rex which panes have Claude Code, Codex, Antigravity or Grok working, then follows Rex's events. Board asks with `--autostart=false`, so it never starts Rex. Without Rex, or when Board can't reach it, AI mode waits, and its status line says **Needs Rex to see when your agents are working**. If Rex is installed but not running, Board tries again every 30 seconds; if it isn't installed, Board looks again when AI mode is turned back on or Board restarts.
- **What it types:** real source files from a folder you choose, or Board's own sources by default, with the odd typo, in bursts of up to about ten seconds. The typing stops the moment Rex says the agent stopped, mid-burst if need be, with every held key released.
- **Speed:** from Human (about 9 keys a second) to Machine gun (about 36), with bursts inside words and pauses at spaces, punctuation and line ends.
- AI mode pauses whenever Board's sounds do: Board off, muted, Secure Input, or a locked or sleeping session.

What Board plays isn't the code your agent is writing. Board 0.4.1 had Claude Code and Codex hooks that sent Board each edit, but a hook only gets an edit after it's written, so the typing couldn't keep the agent's pace. Board 0.4.2 removed them. If you installed one with 0.4.1, click its **Remove** button in 0.4.1 before you update.

Code text stays on this Mac: Board never logs it or sends it anywhere.

## Verification

```sh
bash Scripts/test.sh
```

Tests cover input transitions and shortcuts, keyboard geometry, sample selection/held-release association, versioned settings, import validation, visualizer timing, offline stereo/limiter output, and AI mode (key mapping, pacing, coding along only while an agent works, no event posting). Results, measured idle CPU, remaining hardware checks, and known limitations are in [Docs/VERIFICATION.md](Docs/VERIFICATION.md).

Settings use `UserDefaults` under `com.tommyent.Board`; imports are copied to `~/Library/Application Support/Board/Imported Audio/`. No key-event history is persisted. No application code creates a network connection. Only `bash Scripts/build.sh --notarize` uploads anything, and only the built app, to Apple's notary service.

## Assets and provenance

- [Asset inventory](Docs/asset-manifest.json): origin, author, revision/date, SHA-256 and processing.
- [Original recording guide](Docs/RECORDING.md): archived planning reference for creating additional packs; these proposed sounds are outside the current catalog.
- [Design/reference notes](Docs/REFERENCES.md).
- `Assets/Source/`: editable artwork sources.
- `Board-Keycap-Brand-Package.zip`: the brand package (icons, logos, guide, fonts). The app uses its Porcelain `.icon`, five Dock ICNS files and menu bar glyph.
- `Docs/References/`: source notices and reference material, separate from shipped resources.

`Scripts/fetch_assets.py` is an optional **network-using development script** pinned to a specific kbsim revision. It is not bundled or run by the app. All required acquired assets are already checked into the project; ordinary builds are offline.
