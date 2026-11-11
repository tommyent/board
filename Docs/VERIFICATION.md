# Verification and acceptance ledger

Date: **2026-09-10**. Host: Apple Silicon MacBook Air, Xcode 27.0 (27A5252f), Swift 6.4; project language mode Swift 5, deployment target macOS 15. Tests ran on the current host, not a macOS 15 installation.

**Current scope: 11 bundled sound profiles.** The user removed unavailable sounds and recording dependencies from the requested app. Hardware, permission, and performance verification remains limited as detailed below; earlier catalog counts describe historical builds.

## Board 0.4.10 (build 14) — the same app without build paths, 2026-11-11

No Swift file changed. The Release build was not stripped, so the 0.4.8 and 0.4.9 binaries carried the build folder's absolute path, home folder included, 43 times in their debug symbols. `Scripts/build.sh` now runs `strip -S` on the packaged binary before signing and stops if `/Users/` is still in it. `LICENSE` (MIT) is new.

- `bash Scripts/test.sh` at aab43b5 (the tree merged as 3851f49): **68 tests, 1 skipped, 0 failures**.
- `bash Scripts/build.sh --notarize` at 3851f49: notarization accepted (submission `ca608dbc-af45-464f-8469-47da9b5547e3`), stapled, `spctl`: accepted, Notarized Developer ID. 0.4.10 (14), CDHash `977af5ff58ab793b1bf6ec7cdd5fadd269ea0e95`. `Board-0.4.10.zip` SHA-256 `a7452ce061a46c2917d0de0529d9d8a06905e245a00d7bcb2bc55da5d241eeda`.
- `/usr/bin/grep -a -c '/Users/'` on the binary: **0** (0.4.9: 43).
- **Same program as 0.4.9, observed by comparison:** the `__TEXT,__text` and `__TEXT,__cstring` sections of the two binaries are byte-identical, `nm -u` lists the same 1,311 imported symbols, and the bundles hold the same files.
- **The release's own zip on the test Mac** (M1 MacBook Air, macOS 26.5.1): downloaded back with `gh release download`, checksum equal, quarantined by hand as a Safari download, `/Users/` count 0, Gatekeeper accepted it, the first-open dialog was answered with Open, and Board opened Settings with the Input Monitoring onboarding. Log: `Launch version=0.4.10 settingsOpened=true onboardingIncomplete=true inputPermissionMissing=true`. No Motion request, no crash report.
- **Not observed for 0.4.10:** a launch with Input Monitoring granted, a key press, sound. It is not installed on the Macs that run Board daily; they stay on 0.4.9. That those work is inferred from the identical code sections.
- Cost of stripping: crash reports show fewer local names, and no dSYM is kept.

## Board 0.4.9 (build 13) — Mac menus, quieter first run, safer settings, 2026-11-10

Two branches written after 0.4.8 (`fix/menus`, `fix/first-run`), reviewed by a second model and merged on `release/0.4.9`. What changed:

- **Menus.** The hand-built AppKit main menu gains About Board (the existing Settings section), Services, Hide Board, Hide Others and Show All; Undo and Redo before the editing commands; and a Window menu with Minimize, Zoom and Bring All to Front. Practice… and Settings… stay in the app menu. There is no Help menu, because Board has no help to open. The status menu, launch and reopen are unchanged.
- **Motion & Fitness** is no longer asked for at launch. The headphone-motion manager is created only when head tracking is on, and macOS is asked when the user switches head tracking on. If head tracking is saved as on but macOS was never asked, the Sound section says so.
- **Input Monitoring guidance** in Settings now covers the case where macOS shows no prompt and Board is missing from the list.
- **Settings** missing a field take that field's default and keep everything else, at all three levels (app, sound, visualizer) and inside favorites. Settings that cannot be read at all are copied to `appSettings.v1.unreadable` before defaults are used, and Board says so.
- **Log lines** under subsystem `com.tommyent.Board`: the launch (version, whether Settings opened and why), Input Monitoring permission changes, and the input tap being installed or refused. No key events, key codes, typed text or file paths.
- `Scripts/check-launch.swift`, an optional probe for a clean test Mac, and `Scripts/generate-settings-fixtures.py` with its two fixtures.

Changed in review, before the merge:

- **The Dock-promotion workaround was removed.** `fix/menus` deactivated and reactivated Board when the Dock icon was switched on, as a cure for "menus don't open right after switching the Dock icon on". The review found a way to reproduce that bug every time (see the known issue below), showed that released 0.4.8 has it too, and showed that the workaround does not cure it: with the workaround built in, the same steps still left the menus dead, 2 tries out of 2. So the policy change is the single `setActivationPolicy` call it was in 0.4.8.
- A test that fails when a stored settings property is left out of the hand-written coding keys (`testEveryStoredSettingsPropertyIsSaved`); the existing tests could not notice that.
- `Scripts/check-launch.swift` now refuses to run on a Mac that has any saved Board settings, since it overwrites them while it runs.
- The Sound section's message for head tracking that is on but was never permitted.
- A scratch probe (not in the repository) decoded the settings exported from the two Macs that run Board daily with the new decoders: both decode and re-encode to the same JSON, a round trip of settings with every property away from its default is lossless, and every stored property of the three types is encoded.

**Known issue, in 0.4.8 and 0.4.9: menus dead after the Dock icon is switched on.** Steps that reproduce it every time on macOS 26.5.1 (7 of 7 across the released 0.4.8, 0.4.9 and the workaround build): start Board with the Dock icon off, minimize the Settings window, open Board again so Settings comes back, switch **Show in Dock and Command–Tab** on. Board is the front app and has its Dock icon, but the menu bar keeps the previous app's menus and Board's do not open, 5 seconds later and 30 seconds later. Switching to another app and back brings them to life. Without the minimize step the menus worked in every try (cold launch then switch; another app then reopen then switch; close then reopen then switch). The cause is not known. Keyboard shortcuts still work in that state.

What was run:

- `bash Scripts/test.sh` at 5613bf2 on a MacBook Air (macOS 27.3, Xcode 27.2 27B52), app-hosted: **68 tests, 67 passed, 1 skipped, 0 failures** (24 app, 20 engine, 10 Gaming, 9 Practice, 5 settings). The skipped one is still `testNativeAccessibilityStartAndPauseActions`. The menu test checks the menu's structure, actions and key equivalents, not key presses; the settings tests check decoding and the backup of unreadable data.
- `bash Scripts/build.sh` at 5613bf2: succeeded. `dist/Board.app` is 0.4.9 (13), CDHash `beab4697b458fedeff5084f0665a6183ed260079`, Developer ID-signed with hardened runtime and a timestamp, `codesign --verify --deep --strict` valid, no posting APIs. Not notarized, not released, not installed.
- **Observed on the test Mac (M1 MacBook Air, macOS 26.5.1) with that package**, no Input Monitoring grant, no saved settings at the start. Evidence: Board's window list from CGWindowList, the front app from `lsappinfo`, screenshots, the accessibility tree for texts, and real pointer clicks and front-app key presses through cua-driver 0.44.0.
  - First launch: Settings opened with **Request Input Monitoring**, the new guidance text and **Got it — continue**. No Motion request: the system's permission log shows one Motion request for Board in the session, at the launch of the released 0.4.8 used for comparison, and none at any of the 0.4.9 launches.
  - Onboarding finished, quit, cold `open -g` with the permission missing: Settings opened and Board came to the front.
  - Launch log lines, read with `/usr/bin/log show`: `Input Monitoring permission allowed=false`, `Input tap refused: Input Monitoring permission missing`, `Launch version=0.4.9 settingsOpened=true onboardingIncomplete=true inputPermissionMissing=true` on the first run, and `onboardingIncomplete=false` afterwards. Nothing else was logged, and nothing private.
  - Dock icon on: the menu bar shows Board, File, Edit, Window. Board has About Board, Practice…, Settings…, Services, Hide Board, Hide Others, Show All, Quit Board. Window has Minimize, Zoom, the system's window-tiling items, Bring All to Front and the open windows. Command-W closed Settings; Command-comma opened the real Settings with no Board window open and again from Practice; Command-Shift-P opened Practice; Command-M minimized and reopening Board restored; Command-H hid Board and reopening showed it; Command-Q quit.
  - Dock icon off: Command-W, Command-M and Command-Q worked the same; reopening Board opened Settings after a close and after a minimize; Command-Shift-P opened Practice; the status menu opened. **Command-H does nothing with the Dock icon off**: macOS does not hide an app that has no Dock icon.
  - `Scripts/check-launch.swift` reported `settingsOpened=true boardTookFront=true` for the first run and for finished onboarding with the permission missing, in about three seconds, and left no settings behind.
  - No crash report.
- Observed earlier by the branches' authors on their own builds, not repeated on the combined package: the Motion prompt appearing when head tracking is switched on, and the recovery alert for unreadable settings (both in a macOS 27.0.1 VM); Undo and Redo in Practice's own-text editor; Hide Others and Show All; Zoom.
- **Not observed on that package** (`beab4697…`, built in the release worktree before the merge): a launch with Input Monitoring granted, the `Listen-only input tap installed` log line, sound, a login-item launch, the Motion prompt on switching head tracking on, real head tracking with supported headphones, the **+** route for adding Board to Input Monitoring by hand, running a Services item, and Board › Settings… chosen with the pointer (the synthetic click did not register on the menu item; Command-comma, which calls the same action, did).
- **Released** (2026-11-10): merged to `main` as a9c260f (68 tests, 1 skipped, 0 failures there), built with `bash Scripts/build.sh --notarize`, notarization accepted (submission `b54fb27a-1a42-43a9-afb4-584a77594c28`) and stapled; `spctl -a -vvv -t exec` says "Notarized Developer ID". CDHash `123dc496eeeb6c32115f600f2d07ee02ab802b65`. It differs from the package checked above although the code is the same, because that one was built in another folder; the checks below are on the released one. Tagged `v0.4.9`; the release holds `Board-0.4.9.zip`, SHA-256 `849cef4ce1e165ed8c0658dee5cbdef0f55ae7b9885066301c4779c8b44f850e`.
- **The release's own zip on the test Mac** (macOS 26.5.1): downloaded back with `gh release download`, checksum equal, quarantined by hand as a Safari download and unpacked with `ditto -x -k`. `spctl` accepted it as Notarized Developer ID and `stapler validate` worked. `open` showed Gatekeeper's first-open dialog; **Open** started Board from an App Translocation path with the Settings window showing "Input Monitoring required", **Request Input Monitoring** and **Got it — continue**. The log said `Launch version=0.4.9 settingsOpened=true onboardingIncomplete=true inputPermissionMissing=true`. No Motion request, no crash report.
- **Installed from that zip on two Macs, both macOS 27.3**, replacing 0.4.8 on each; the old apps went to the Trash. Board was not running on either beforehand, and Input Monitoring was already granted on both. One `open -g -a /Applications/Board.app` each, checked with read-only commands only. This is the launch that could not be observed before, and on both Macs:
  - the process ran from `/Applications/Board.app/Contents/MacOS/Board`; Board's only window was its 0×0 off-screen overlay panel, so no Settings; the front app was the same before and after;
  - `CGGetEventTapList` showed an enabled, listen-only session tap owned by Board;
  - the log had `Input Monitoring permission allowed=true`, `Listen-only input tap installed; enabled=true` and `Launch version=0.4.9 settingsOpened=false onboardingIncomplete=false inputPermissionMissing=false`, and nothing about unreadable settings;
  - no Motion request, no crash report;
  - the exported settings were identical before and after the launch (21 settings fields on one Mac, 19 on the other, which still carried settings last written by 0.4.1).
  - Not observed on either: a key press or sound (no keys were pressed on those Macs), the menus and icons on screen, and a login-item launch. Board was quit again afterwards, as it had not been running.

## Board 0.4.8 (build 12) — no Settings window at launch, 2026-11-10

Until 0.4.7, `applicationDidFinishLaunching` ended with an unconditional `showSettings()`, so every launch, including a login item and `open -g`, put the Settings window in front of the user's work. Now a launch opens Settings only while onboarding is unfinished (**Got it — continue** not yet chosen) or Input Monitoring is not allowed (`CGPreflightListenEventAccess()` is false). The gaming overlay and the visualizers are separate and can still show after a launch. 0.4.7 (build 11, 9dd875c) remembered the gaming overlay setting and has no entry of its own.

Reopen is as in 0.4.7: opening Board again while it runs always opens Settings (`applicationShouldHandleReopen`). From 7a2d392 to 90a90cf, 0.4.8 briefly had a narrower rule, Settings only when both **Show menu bar icon** and **Show in Dock and Command–Tab** are off. It was dropped (the owner's decision, 2026-11-10) because the VM run below showed that with the Dock icon on and the menu bar icon off it left no way into Settings. The observations of that rule are kept below as history.

Board now starts with a plain AppKit `main` (72612d0) instead of a SwiftUI `App` whose only scene was `Settings { EmptyView() }`. SwiftUI replaced the main menu `applicationDidFinishLaunching` builds with its own, and that menu's **Settings…** and Command-comma opened the scene's empty window. This is older than 0.4.8. Observed on the final package, below.

- **Final package, observed** on a macOS 27.0.1 VM (2026-11-10): the package built at 72612d0, CDHash `c1a3ae063e7a152059f39f7ccb5cde7ab6c33196` checked in the VM, fresh settings. Evidence is Board's window list from CGWindowList (Settings is the 890×740 window) and the front app from `lsappinfo`, plus screenshots for the menus.
  - First launch (`open -g`): Settings opened and Board came to the front. **Got it — continue** was saved and survived a restart. A cold launch with onboarding finished and the permission still missing opened Settings.
  - Input Monitoring granted by the owner in System Settings. Then a cold `open -g` and a cold plain `open`, each with System Settings in front: Board started, no Settings window, no Board window on screen, and System Settings stayed the front app.
  - Input tap: with System Settings in front, Control–Option–Command–K switched **Enable Board** off and on again in the status menu, and Settings showed "Listening to physical input". Sounds were not listened to; the VM's output was muted for the test so nothing played on the host.
  - Reopen with Settings closed and Finder in front, permission missing: `open -g` and plain `open` each opened Settings and brought Board to the front in all four combinations of menu bar icon and Dock. A Dock click did the same (both icons on, and Dock only). With Settings already visible or minimized, `open -g` brought it back to the front. With the permission granted, `open -g` opened Settings with the Dock off and with it on.
  - Menus with the Dock icon on: the menu bar shows Board, File, Edit. **Board** has Practice… (⇧⌘P), Settings… (⌘,) and Quit Board (⌘Q). **Board › Settings…** opened Settings; Command-comma from the Practice window opened Settings; no empty "Board Settings" window appeared. **File › Close Window** closed Settings, and **Edit** has Cut, Copy, Paste and Select All. Board's menu has no About, Hide, Services or Window menu.
  - With the menu bar icon only, the status menu's **Settings…** opened Settings, and Command-W and Command-Q worked in the Settings window; macOS does not show Board's menu bar in that setup.
  - Right after **Show in Dock and Command–Tab** was switched on, the menu bar showed Board, File, Edit but the menus did not open on a click until another app had been activated and Board activated again. Whether the SwiftUI start did the same was not checked.
  - Not observed: a login-item launch, and sound output.
- **Released** (2026-11-10): merged to `main` as 18e4546 (62 tests, 1 skipped, 0 failures there), built with `bash Scripts/build.sh --notarize`, notarization accepted (submission `9becc601-617f-47fe-8809-b1a0d876b318`) and stapled; `spctl -a -vvv -t exec` says "Notarized Developer ID". The CDHash is still `c1a3ae063e7a152059f39f7ccb5cde7ab6c33196`, the one observed on the VM. Tagged `v0.4.8`; the release holds `Board-0.4.8.zip` (made with `ditto -c -k --keepParent`), SHA-256 `58824cc6e9272fa7352804f6ea1035606848cf0d4f39e048e0bd5d06f15bda0d`.
- **The release's own zip on the test Mac** (M1 MacBook Air, macOS 26.5.1): downloaded back with `gh release download`, checksum equal, given the quarantine attribute of a Safari download by hand (zip and every unpacked file) and unpacked with `ditto -x -k`. `spctl` accepted it as Notarized Developer ID and `stapler validate` worked. `open` showed Gatekeeper's first-open dialog ("Apple checked it for malicious software and none was detected"); Cancel ended the launch; Open started Board from an App Translocation path with its menu bar icon and the Settings window showing "Input Monitoring required", **Request Input Monitoring** and **Got it — continue**. Board did not come to the front there (Safari stayed in front). No crash report. Input Monitoring can't be granted on that Mac, so nothing beyond the first run was tried.
- **Installed from that zip on two Macs, both macOS 27.3**, replacing 0.4.7 (build 11) on a MacBook Air and 0.4.1 (build 5) on a Mac mini; the old apps went to the Trash. Board was not running on either beforehand. One `open -g -a /Applications/Board.app` each, checked with read-only commands only:
  - Both: the process ran from `/Applications/Board.app/Contents/MacOS/Board`; no Settings window (Board's only window was its 0×0 off-screen overlay panel); the front app was the same before and after; `CGGetEventTapList` showed an enabled, listen-only session tap owned by Board's process; no crash report. So the Input Monitoring grants made for 0.4.7 and 0.4.1 carried over (the designated requirement is unchanged).
  - Mac mini: the settings saved by 0.4.1 were read as they were (onboarding finished, both icons on); the exported settings were byte-identical before and after the launch. The current `AppSettings` also decoded that export in a separate probe.
  - Both Macs have the menu bar icon and the Dock icon on.
  - Not observed on either: the menu bar icon and Dock icon on screen, any key press or sound (no keys were pressed on the owner's Macs), and a login-item launch. Board was quit again afterwards on both, as it had not been running.

- New `testLaunchOpensSettingsOnlyForOnboardingOrMissingPermission` (2cb0b59) covers the four combinations of the launch decision; it tests the decision function only, not the launch itself. New `testNothingButBoardBuildsTheMainMenu` (72612d0) checks in the test host, which skips Board's own menu, that the app delegate is `AppDelegate` and nothing else installed a main menu; against the SwiftUI start it failed on both counts. `bash Scripts/test.sh` at 72612d0 on this MacBook Air (macOS 27.3, Xcode 27.2 27B52), app-hosted: **62 tests, 61 passed, 1 skipped, 0 failures** (23 app, 20 engine, 10 Gaming, 9 Practice). The skipped one is still `testNativeAccessibilityStartAndPauseActions`. Earlier counts: 61 with 1 skipped at 5d54ee1, 62 with 1 skipped at 965f758 (which had a test for the dropped reopen rule).
- `bash Scripts/build.sh` at 72612d0: succeeded. `dist/Board.app` is 0.4.8 (12), CDHash `c1a3ae063e7a152059f39f7ccb5cde7ab6c33196`, Developer ID-signed with hardened runtime and a timestamp, `codesign --verify --deep --strict` valid, with no posting APIs. Not notarized and not installed. The items after this one were observed on earlier packages, named in each.
- Observed on the test Mac (M1 MacBook Air, macOS 26.5.1, a clean account with no Board settings and no Input Monitoring grant), with the package built at 5d54ee1, **before the reopen change**, both icon settings at their defaults (menu bar icon on, Dock off), reading windows from CGWindowList and cua-driver 0.44.0:
  - First run, `open -g`: the 890×740 **Board — Settings** window opened and Board came to the front.
  - After **Got it — continue** (saved `onboardingComplete` true), quit and `open -g` again, permission still missing: Settings opened. The same with a plain `open`.
  - With Board running and Settings closed, `open -g` on the app showed Settings again and brought Board to the front. This is the reopen behaviour 0.4.8 ships with again.
  - **Request Input Monitoring** showed no macOS prompt and did not add Board to System Settings › Privacy & Security › Input Monitoring (the list stayed empty; tccd logged "Service kTCCServiceListenEvent does not allow prompting"). The button changed to **Open Input Monitoring Settings**, which opened that pane. Adding Board with **+** asks for the account password.
- Not observed on the test Mac: a launch with onboarding finished and Input Monitoring allowed, which is the case that must not open Settings. Allowing it there needs the account password in System Settings, so that path is covered only by the unit test and by reading the code. Board was not launched on the MacBook Air.
- History, the dropped reopen rule. Observed on a macOS 27.0.1 VM with the package built at 965f758 (CDHash `2ea79c5b…`), which had that rule and the SwiftUI start, onboarding finished, Input Monitoring **not** granted, reading Board's windows from CGWindowList and the front app from `lsappinfo`, with Finder in front before each reopen:

  | Menu bar icon | Dock | `open -g` on the running app | plain `open` |
  |---|---|---|---|
  | on | off | no Settings, Finder stays in front | no Settings, Board becomes the front app with no window |
  | on | on | no Settings, Finder stays in front | no Settings, Board becomes the front app with no window |
  | off | on | no Settings, Finder stays in front | no Settings, Board becomes the front app with no window; a Dock click does the same |
  | off | off | Settings opens and Board comes to the front | not run |

  - First run with `open -g`: Settings opened (behind the front app), and macOS asked "Allow “Board” to access your motion and fitness activity?" (answered Don't Allow).
  - **Request Input Monitoring** showed macOS's Keystroke Receiving prompt on this system, and **Open System Settings** listed Board in Input Monitoring, switched off. Switching it on asks for the account password, which was not entered, so the permission was never granted.
  - A launch with onboarding finished and the permission missing (`open -g`) opened Settings and brought Board to the front, as intended.
  - With the Dock icon on, **Board › Settings…** in the menu bar and Command-comma open an empty window titled "Board Settings", not Board's Settings. The menu bar shows SwiftUI's menus (Board, View, Window, Help), not the ones `applicationDidFinishLaunching` builds; the empty window is the `Settings { EmptyView() }` scene in `BoardApp`. With the Dock icon on and the menu bar icon off there was therefore no way into Settings in the running app. Older than 0.4.8, but until 7a2d392 a Dock click opened the real Settings.
- On these earlier packages the launch with Input Monitoring allowed was never observed; it was on the final package, above.

## Board 0.4.6 (build 10) — Gaming practice, 2026-11-01

Merges `gaming` (8f9de8e, fbd4574), built on 0.4.5. It adds a Gaming tab to the Practice window with four drills (Reaction, Strafe rhythm, Key reversal, Hold + tap), its own history, and an opt-in floating overlay of the gaming keys and mouse buttons. The drill engine lives in `Board/Gaming/` and also builds as a separate Swift package (`Package.swift`). The project generator now includes Swift files in subfolders; regenerating the merged project changed nothing. The branch also removed the unreachable Bezel case in `OverlayContent.content`.

- `bash Scripts/test.sh` on this MacBook Air (macOS 27.2, Xcode 27.2 27B52), app-hosted: **59 tests, 58 passed, 1 skipped, 0 failures**. That is the 30 from 0.4.5, 20 engine tests and 9 Gaming tests. The skipped one, `testNativeAccessibilityStartAndPauseActions`, skips itself because the off-screen SwiftUI window exposes no buttons to accessibility, so Start and Pause through accessibility are unverified.
- `swift test` (the engine package alone): **20 tests, 0 failures**.
- `bash Scripts/build.sh`: succeeded. `dist/Board.app` is 0.4.6 (10), Developer ID-signed with hardened runtime and a timestamp, `codesign --verify --deep --strict` valid, with no posting APIs.
- Installed on this MacBook Air at 20:16. 0.4.5 was backed up first. It wasn't running: it ended at 19:43 through Board's own Quit, so there was nothing to quit through Vitals. The old bundle was trashed, the new one copied with `ditto`, and Board launched with `open -g`. `/Applications/Board.app` is 0.4.6 (10), its binary byte-identical to `dist/`, and it runs as the only Board process. tccd allowed its Input Monitoring preflight and both WindowServer checks (`kTCCServiceListenEvent`, `authValue=2`).
- Not observed yet: any drill or the overlay on screen; the overlay over a full-screen game or in OBS; real focus, sleep, lock and Secure Input changes; VoiceOver; key sounds during a drill (single, not doubled); and latency of the keyboard, app and display path. The Gaming images are off-screen renders of test sessions.

## Board 0.4.5 (build 9) — keystroke trails and Practice, 2026-11-01

Merges two branches built from 0.4.4. `visualizer` (453a860) brings the 15-key fading keystroke ribbon with repeat counts, Float and the other movements in every placement, a 1.4-second afterglow on the keyboard, and switch-colored highlights and caps. `practice` (2d144be) brings the Practice window. The branches didn't conflict. Practice had added its sources to the Xcode project by hand. `Scripts/generate_project.py` now adds every `Tests/*.swift` file, and the project is regenerated from it, so a later regeneration keeps the Practice tests. Practice keeps its own key trail for now.

- `bash Scripts/test.sh` on this MacBook Air (macOS 27.2, Xcode 27.2 27B52), app-hosted: **30 tests, 0 failures**. That is the 17 from 0.4.4, the 4 new visualizer tests (trail capacity and repeat counts, afterglow, movement independent of placement, expiry and Secure Input reset; three existing tests were extended) and Practice's 9.
- `bash Scripts/build.sh`: succeeded. `dist/Board.app` is 0.4.5 (9), Developer ID-signed with hardened runtime and a timestamp, `codesign --verify --deep --strict` valid, with no posting APIs. The package's `Resources/Code` holds the five Practice sources and no Ambient files.
- `/usr/bin/grep -R` for `suffix(6)` and `pills` over the checkout and `dist/`: no match. The README's old "keystroke pills" line is rewritten. Under `build/`, only Xcode's index and the archived packages in `build/PreviousBuilds/` still match.
- Installed on this MacBook Air at 19:37. 0.4.4 was backed up first. It wasn't running: its last run, launched from `/Applications` at 17:43, ended at 18:03 through Board's own Quit, so there was nothing to quit through Vitals. The old bundle was trashed, the new one copied with `ditto`, and Board launched with `open -g`. `/Applications/Board.app` is 0.4.5 (9), its binary byte-identical to `dist/`. It runs as the only Board process. tccd allowed its Input Monitoring preflight and both WindowServer checks (`kTCCServiceListenEvent`, `authValue=2`). No crash report. AI mode is off in the saved settings, so no `rex` stream runs.
- Not observed yet: the ribbon, Float and afterglow on screen while typing; CPU while typing; Practice's window focus, sleep, lock and real Secure Input transitions; the Command–Shift–P shortcut; VoiceOver; and sound while practicing. The builders' images are off-screen renders, and their tests inject focus and Secure Input states.

## Board 0.4.4 (build 8) — the cue stops when the agent stops, 2026-11-01

When Rex reports that the agent stopped, AI mode now drops the rest of the current burst at once. It releases every held key through the same path as physical keys, so nothing stays down in the sound engine or the visualizer. Before, the burst played out for up to about ten more seconds.

- New `testJokeTypingStopsTheMomentTheAgentStops`. It cuts in while a key is down, delivered on the main queue as `AgentWatch` delivers it. It checks four things: a key was down at the cut, every pressed key was released at once, nothing more is typed in the next 0.5 s, and the status returns to waiting. Against 0.4.3's code it failed: 3 → 6 presses, and the status still said "Coding along". With the fix, `bash Scripts/test.sh` passes **17 tests, 0 failures** (macOS 27.2, Xcode 27.2 27B52).
- `bash Scripts/build.sh`: succeeded. `dist/Board.app` is 0.4.4 (8), Developer ID-signed with a timestamp, `codesign --verify --deep --strict` valid, with no posting APIs.
- Installed on this MacBook Air at 17:27. 0.4.3 was backed up, quit through Vitals with the owner's OK, and replaced: old bundle trashed, then copied with `ditto`. `/Applications/Board.app` is 0.4.4 (8), and its binary is byte-identical to `dist/`. It runs as the only Board process, with its `rex --autostart=false events` stream as a child. tccd allowed its Input Monitoring preflight (`authValue=2`). No crash report. How the cut sounds live is for the owner to hear.

## Board 0.4.3 (build 7) — AI mode as a sound cue, 2026-11-01

Settings › Extras › AI mode now explains AI mode as a sound cue for your agents, with Rex as the source of the agent status. The status line says **Needs Rex to see when your agents are working** when Rex isn't installed, doesn't answer, or its event stream has ended. It keeps "Waiting for a coding agent to work in Rex" for when Rex answers and no agent is working. `AgentWatch.snapshot` now returns nil when `rex api call session.list` fails, instead of an empty set. With `--autostart=false` and no server, the real `rex` prints "no Rex server is running at …, and autostart is disabled" and exits 4 (checked against a socket path with no server behind it).

- `bash Scripts/test.sh` on this MacBook Air (macOS 27.2, Xcode 27.2 27B52), app-hosted: **16 tests, 0 failures**. New: `testAIModeSaysWhenItNeedsRex`. A stand-in `rex` that exits 4 gives a nil snapshot, and one that lists no sessions gives an empty one. The status line follows Rex's reachability.
- `bash Scripts/build.sh`: succeeded. `dist/Board.app` is 0.4.3 (7), Developer ID-signed with a timestamp, `codesign --verify --deep --strict` valid, with no posting APIs. The binary contains the full Settings text and both status lines.
- Installed on this MacBook Air at 17:20. 0.4.2 was backed up, quit through Vitals with the owner's OK, and replaced: old bundle trashed, then copied with `ditto`. `/Applications/Board.app` is 0.4.3 (7); its binary is byte-identical to `dist/` and contains the full Settings text and the "Needs Rex" line. It runs from `/Applications/Board.app/Contents/MacOS/Board` as the only Board process, with its `rex --autostart=false events` stream as a child. tccd allowed its Input Monitoring preflight (`authValue=2`). No crash report. The text was read from the binary, not the screen.

## Board 0.4.2 (build 6) — AI mode without agent hooks, 2026-11-01

AI mode now does one thing: while Rex reports a coding agent working, Board codes along from real source files (a chosen folder, or Board's own sources), at the chosen speed and with the odd typo. It isn't the code the agent is writing. The Claude Code and Codex hooks of 0.4.1 are gone: the hook script and its copy in the app, the Install/Remove rows, the folder reader and its `listening` marker, `Scripts/test-ai-hook.sh` and its fixtures, the ⌘S that ended a typed edit, and three tests (queue, queued edit, hook installer). The hooks only got an edit after it was written, so they couldn't follow the agent's pace. When it starts, Board 0.4.2 deletes the folder 0.4.1 used for them, `~/Library/Application Support/Board/AI Queue/`, and nothing else. The no-event-posting guarantee, its test and the `Scripts/build.sh` check are unchanged.

- `bash Scripts/test.sh` on this MacBook Air (macOS 27.2) with Xcode 27.2 (27B52), app-hosted: **15 tests, 0 failures** (`** TEST SUCCEEDED **`). New: `testJokeModeCodesAlongOnlyWhileAnAgentWorks` (nothing is typed until an agent works, joke typing then reaches Board's pipeline, and stops when AI mode is turned off; the test sets the working state itself, without Rex).
- `bash Scripts/build.sh`: Release build succeeded; Xcode removed the stale hook from the previous build's product. `dist/Board.app` is 0.4.2 (6), Developer ID-signed with hardened runtime and a secure timestamp, `codesign --verify --deep --strict` valid. The event-posting check passed (`nm -u` lists none of the posting APIs).
- `/usr/bin/grep -R` for `board-ai-hook`, `AI Queue` and `PostToolUse` over the checkout, `build/` and `dist/`: the source, scripts, README and packaged app have only the cleanup line in `Board/AppState.swift` (and its copy in the app's `Resources/Code/`). `build/` also has the Debug build of that line, Xcode's cached build descriptions of earlier builds, and the old packages in `build/PreviousBuilds/`. The 7 old packages that still held the hook were moved to the Trash afterwards; `build/PreviousBuilds/` now has no match.
- Installed on this MacBook Air at 17:06, after the owner clicked Remove in 0.4.1. Neither `~/.codex/hooks.json` nor `~/.claude/settings.json` had Board's entry. 0.4.1 was backed up, quit through Vitals with the owner's OK, then replaced by `dist/Board.app` (old bundle trashed, then copied with `ditto`, so no stale files). `/Applications/Board.app` is 0.4.2 (6), with `codesign --verify --deep --strict` valid and no hook in `Contents/Resources`. It runs as the only Board process, from `/Applications/Board.app/Contents/MacOS/Board`. On start it deleted `~/Library/Application Support/Board/AI Queue/`; the `Board` folder itself stays. tccd's log shows its Input Monitoring preflight (`kTCCServiceListenEvent`) allowed (`authValue=2`). Whether keys sound is for the owner to confirm.

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

2026-10-25: after the audit fixes the suite has eleven tests, adding a decoded-size bound, import copies (source swapped after copying, failed second copy), clamped saved presets, and keystroke labels cleared on a Space change. All eleven passed on the test Mac (macOS 26.5.1), first as logic tests under Xcode 27's `xctest` (SwiftPM build of the same sources) while it had no Xcode. Later the same day AI mode and its hook installer brought the suite to seventeen tests, and the app-hosted `bash Scripts/test.sh` passed all 17 there with Xcode 27.0 (27A5252f) at commit `42d4efb` (`** TEST SUCCEEDED **`). The Xcode test target compiles (`build-for-testing`). Against the pre-fix code, the new decoded-size, preset and Space tests fail.

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
