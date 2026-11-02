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
- Keyboard, Keystrokes, Combo and Bezel visualizers; ANSI/ISO/JIS layouts, position/scale/theme/timing controls, six pins and random placement.
  - **Keystrokes** is a ribbon of your last 15 keys, in a row or a column. Each key fades, shrinks and blurs over 1.9 seconds, so the oldest trail off. Taps of the same key less than 0.3 seconds apart merge into one cap with a count, such as `⌫ ×3`; a held key doesn't count up, because Board ignores key repeat.
  - **Movement:** Pop, Slide, Bounce and Pulse work in every placement. Keystrokes also offers Float, which lifts each key along its keyboard column.
  - **Keyboard:** released keys glow for 1.4 seconds.
  - **Colors:** keyboard highlights and keystroke caps take the color of each key's switch, including per-key overrides, and Bezel takes the selected switch's color. Combo keeps its own theme.
  - With macOS Reduce Motion on, keys only fade, and Float becomes a still row.
- Practice window: English, Swift/JavaScript/Python code, or your own text; 30-second, 1-minute and 2-minute attempts; WPM, accuracy, marked errors, a key trail, and local result history. Open **Practice…** from Board's menu, or press **Command–Shift–P** while Board is active. See [Practice](#practice).
- Gaming practice: a **Gaming** tab in the Practice window with Reaction, Strafe rhythm, Key reversal and Hold + tap drills, and an optional floating overlay of WASD, Shift, Ctrl, Space and the mouse buttons. See [Gaming practice](#gaming-practice).
- AI mode: a sound cue for your coding agents. While one works, Board types along, with sounds and the visualizer only; Rex tells Board when an agent is working. See [AI mode](#ai-mode).
- Five app icon colors from the Board Keycap brand package: Porcelain (the bundled icon), Sage, Blue, Lilac and Graphite. Settings › General › App icon changes Board's Dock icon while it runs; Finder and Launchpad keep Porcelain. The keyboard in Settings › Your Keyboard and Practice's key trail use the chosen color; the visualizer uses switch colors. Settings uses the standard macOS sidebar, forms and controls, in your system accent color.
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

## Practice

The first committed character starts the clock. WPM is correct characters currently entered divided by five, per minute of active typing time. Accuracy is correct insertion attempts divided by all insertion attempts; correcting a mistake does not erase it from accuracy. Editing earlier text does not recount its unchanged suffix. Return inserts a new line; in code passages Tab inserts four spaces and Control–Tab leaves the typing field. Paste and drop are disabled in a scored attempt; paste your passage in **Your text → Edit text…** instead.

The Practice controller is wired to pause when its window loses focus, the session sleeps or locks, or Secure Input is enabled, with an explicit Resume action. Its key trail consumes only keys received by its own typing field. Sound still comes from the existing physical input monitor, so Input Monitoring permission is required for typing sounds; Practice adds no second sound path. The footer shows when Board is off, muted, or lacks permission.

History keeps the latest 200 completed result summaries in `UserDefaults` under `practice.history.v1`. It never saves passage text, typed text, or individual keys. Personal bests are separate for each mode, duration, and code language; custom passages have no shared best. Custom text is limited to 10,000 characters, stays in memory, and is cleared when Practice closes. **History → Clear History…** removes saved results and bests. English/code passages repeat for the timed attempt; reaching the end of a custom passage finishes early. Unfinished attempts are not saved. Typing drills are not included.

## Gaming practice

The Practice window's **Gaming** tab drills key presses for games. A drill starts with **Start** and a three-second countdown and lasts 30, 60 or 120 seconds. Keys are physical positions, labeled as on a US QWERTY keyboard.

- **Reaction:** a key or button appears after a random wait, and you press it. Key sets: WASD; WASD + abilities (adds Q, E, R, F, Space, left Shift and 1–5); Abilities + mouse (adds the left and right buttons). Results: median reaction time, accuracy, consistency (median absolute deviation, MAD) and APM.
- **Strafe rhythm:** alternate D and A on the beat.
- **Key reversal:** hold the first key, and at GO release it and press the opposite one. It scores the gap between the release and the press.
- **Hold + tap:** hold left Shift while you tap Space on the beat.
- Timed drills run at 60, 80, 100, 120 or 160 BPM with a ±60 or ±120 ms window (≤60 or ≤120 ms for Key reversal), and say whether a press was early, late, missed, the wrong key, out of order, extra or missing its hold. The beat is visual only. With Reduce Motion on, upcoming keys stand still instead of moving along a lane.

Only presses in the Gaming tab's own input area count, so typing in other apps can't score. A drill pauses on Escape, when you leave its input area or switch tabs, when the window or Board loses focus, when the Mac sleeps or locks, and during Secure Input; you resume it yourself. Closing Practice drops an unfinished drill. Key repeat and releases never add to APM, and mouse buttons count only in the mouse key set. The drills play no sounds of their own: key sounds come from Board as usual, and the tab has a **Mute Board** box.

Gaming history keeps the latest 200 completed results in `UserDefaults` under `gaming.history.v1`, separate from typing history: drill settings and totals, never individual presses. A personal best compares only results with the same drill settings and scoring version, at least 90% accuracy and no interruptions. **History → Clear gaming history…** removes them.

**Gaming keys overlay** (a switch in the Gaming tab) shows a small floating window, **Board — Gaming Keys**, at the lower left of the main screen: WASD, left Shift, left Ctrl, Space and the left and right mouse buttons, each showing how long it's held and fading 0.35 seconds after release. Clicks go through it, and it stays above other windows on every Space. It follows Board's system-wide input monitoring, so it needs Input Monitoring, and it hides while Board is off, during Secure Input, and while the Mac sleeps or is locked. It never feeds scores or history, and remembers whether it was on or off across launches (off by default). Whether it shows over full-screen games and in OBS hasn't been tested.

Reaction times include the delays of your keyboard, Mac and display. Compare them on the same setup; they aren't laboratory measurements.

## Verification

```sh
bash Scripts/test.sh
```

Tests cover input transitions and shortcuts, keyboard geometry, sample selection/held-release association, versioned settings, import validation, visualizer timing and the keystroke trail (15-key limit, repeat counts, expiry, afterglow, movement in every placement), offline stereo/limiter output, AI mode (key mapping, pacing, coding along only while an agent works, no event posting), and Practice (scoring, corrections, time limits, pause and resume, Secure Input, Unicode composition through native text input, saved results, off-screen rendering). It also covers Gaming practice: cue timing and scoring for every drill, native key and mouse input, pausing, history and best scores, the overlay's hold times, and off-screen rendering. Practice's and Gaming's rendering tests write their screenshots to `/private/tmp/board-practice-artifacts/` and `/private/tmp/board-gaming-artifacts/`. The gaming engine in `Board/Gaming/` also builds as its own Swift package: `swift test` runs its tests without the app. Window focus changes, the menu shortcut, a real Secure Input change, the overlay over full-screen games and audible playback in Practice still need a check by hand, and the test of Gaming's Start and Pause buttons through accessibility is skipped because an off-screen window exposes no buttons. Results, measured idle CPU, remaining hardware checks, and known limitations are in [Docs/VERIFICATION.md](Docs/VERIFICATION.md).

Settings use `UserDefaults` under `com.tommyent.Board`; imports are copied to `~/Library/Application Support/Board/Imported Audio/`. No key-event history is persisted. No application code creates a network connection. Only `bash Scripts/build.sh --notarize` uploads anything, and only the built app, to Apple's notary service.

## Assets and provenance

- [Asset inventory](Docs/asset-manifest.json): origin, author, revision/date, SHA-256 and processing.
- [Original recording guide](Docs/RECORDING.md): archived planning reference for creating additional packs; these proposed sounds are outside the current catalog.
- [Design/reference notes](Docs/REFERENCES.md).
- `Assets/Source/`: editable artwork sources.
- `Board-Keycap-Brand-Package.zip`: the brand package (icons, logos, guide, fonts). The app uses its Porcelain `.icon`, five Dock ICNS files and menu bar glyph.
- `Docs/References/`: source notices and reference material, separate from shipped resources.

`Scripts/fetch_assets.py` is an optional **network-using development script** pinned to a specific kbsim revision. It is not bundled or run by the app. All required acquired assets are already checked into the project; ordinary builds are offline.
