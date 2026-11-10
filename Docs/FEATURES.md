# Board in detail

The [README](../README.md) describes each feature in a few lines. This page keeps the exact rules: what counts, what is saved, and when things pause.

## Sound

- 32 playback voices are loaded in advance. Mechanical profiles play separate press and release samples; Typewriter plays one complete stroke per press.
- Native spatial output, a limiter, offline tone preparation, gain and pitch variation, and softer home-row keys.
- Per-key overrides, six favorites, imports of your own recordings (validated before use), a preferred output device, an output-kind override, optional head tracking with supported headphones, and an eight-second orbit mode.
- Mouse and Enter sounds can be None, the selected keyboard profile, or an imported recording.
- Typing, mouse and Enter each have their own volume, and a key with its own sound has its own volume too. Mute silences everything.
- The default profile is Durock Alpaca.

## Input

- One listen-only event tap for the session. Board never posts events.
- It removes duplicate transitions and ignores key repeat, pauses during Secure Input, resets after sleep or a session switch, and retries when the permission changes.

## Visualizers

Four styles: Keyboard, Keystrokes, Combo and Bezel. ANSI, ISO and JIS layouts; position, scale, theme and timing controls; six pins and random placement.

- **Keystrokes** is a ribbon of your last 15 keys, in a row or a column. Each key fades, shrinks and blurs over 1.9 seconds, so the oldest trail off. Taps of the same key less than 0.3 seconds apart merge into one cap with a count, such as `⌫ ×3`. A held key doesn't count up, because Board ignores key repeat.
- **Movement:** Pop, Slide, Bounce and Pulse work in every placement. Keystrokes also offers Float, which lifts each key along its keyboard column.
- **Keyboard:** released keys glow for 1.4 seconds.
- **Colors:** keyboard highlights and keystroke caps take the color of each key's switch, including per-key overrides. Bezel takes the selected switch's color. Combo keeps its own theme.
- With macOS Reduce Motion on, keys only fade, and Float becomes a still row.

## App icon colors

Five colors from the Board Keycap brand package: Porcelain (the bundled icon), Sage, Blue, Lilac and Graphite. **Settings › General › App icon** changes Board's Dock icon while it runs; Finder and Launchpad keep Porcelain. The keyboard in **Settings › Your Keyboard** and Practice's key trail use the chosen color; the visualizer uses switch colors. Settings uses the standard macOS sidebar, forms and controls, in your system accent color.

## Mac menus

With **Show in Dock and Command–Tab** on, Board uses AppKit menus: **Board** (About, Practice, Settings, Services, Hide, Hide Others, Show All and Quit), **File** (Close Window), **Edit** (Undo, Redo, Cut, Copy, Paste and Select All) and **Window** (Minimize, Zoom, Bring All to Front and the open windows). About selects Settings' existing About section. There is no Help menu because Board has no bundled help or public help address yet.

Standard shortcuts use the responder chain: Command-H hides Board, Option-Command-H hides other apps, Command-M minimizes the front window, and Command-Z / Shift-Command-Z undo and redo in editable text fields. Practice's scored input keeps its own editing rules. Command-comma opens the real Settings window, including with the Dock icon off; Command-Shift-P opens Practice. The status menu is unchanged.

## AI mode

AI mode is a sound cue for your coding agents. Turn on **Settings › Extras › AI mode**, and while a coding agent works, Board types along, so you can hear when it's busy and when it stops. It only plays key sounds and drives the visualizer. It never posts key events, so nothing is typed into your apps.

- **Rex provides the agent status.** Board learns whether an agent is working from Rex, the terminal your agents run in. It asks Rex which panes have Claude Code, Codex, Antigravity or Grok working, then follows Rex's events. Board asks with `--autostart=false`, so it never starts Rex. Without Rex, or when Board can't reach it, AI mode waits, and its status line says **Needs Rex to see when your agents are working**. If Rex is installed but not running, Board tries again every 30 seconds. If it isn't installed, Board looks again when AI mode is turned back on or Board restarts.
- **What it types:** real source files from a folder you choose, or Board's own sources by default, with the odd typo, in bursts of up to about ten seconds. The typing stops the moment Rex says the agent stopped, mid-burst if need be, with every held key released.
- **Speed:** from Human (about 9 keys a second) to Machine gun (about 36), with bursts inside words and pauses at spaces, punctuation and line ends.
- AI mode pauses whenever Board's sounds do: Board off, muted, Secure Input, or a locked or sleeping session.

What Board plays isn't the code your agent is writing. Board 0.4.1 had Claude Code and Codex hooks that sent Board each edit, but a hook only gets an edit after it's written, so the typing couldn't keep the agent's pace. Board 0.4.2 removed them. If you installed one with 0.4.1, click its **Remove** button in 0.4.1 before you update.

Code text stays on your Mac: Board never logs it or sends it anywhere.

## Practice

Open **Practice…** from Board's menu, or press **Command–Shift–P** while Board is active. Passages are English, code (Swift, JavaScript or Python) or your own text; attempts last 30 seconds, 1 minute or 2 minutes.

The first committed character starts the clock. WPM is correct characters currently entered divided by five, per minute of active typing time. Accuracy is correct insertion attempts divided by all insertion attempts; correcting a mistake does not erase it from accuracy. Editing earlier text does not recount its unchanged suffix. Return inserts a new line; in code passages Tab inserts four spaces and Control–Tab leaves the typing field. Paste and drop are disabled in a scored attempt; paste your passage in **Your text → Edit text…** instead.

Practice pauses when its window loses focus, the session sleeps or locks, or Secure Input is enabled, and you resume it yourself. Its key trail shows only keys received by its own typing field. Sound still comes from Board's system-wide input monitor, so typing sounds need Input Monitoring; Practice adds no second sound path. The footer shows when Board is off, muted, or lacks the permission.

History keeps the latest 200 completed result summaries in `UserDefaults` under `practice.history.v1`. It never saves passage text, typed text, or individual keys. Personal bests are separate for each mode, duration and code language; custom passages have no shared best. Custom text is limited to 10,000 characters, stays in memory, and is cleared when Practice closes. **History → Clear History…** removes saved results and bests. English and code passages repeat for the timed attempt; reaching the end of a custom passage finishes early. Unfinished attempts are not saved. Typing drills are not included.

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
