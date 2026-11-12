# Install and first run

Board is built for Apple silicon Macs. [Download the current release](https://github.com/tommyent/board/releases/latest), or [build Board from source](BUILDING.md).

1. Download [`Board-0.4.10.zip`](https://github.com/tommyent/board/releases/download/v0.4.10/Board-0.4.10.zip) and open it.
2. Move `Board.app` to your Applications folder.
3. Open Board. The first time, macOS asks whether you want to open an app downloaded from the internet; choose **Open**. The release is signed with Developer ID and notarized by Apple.

Board opens its Settings window. To hear sounds in other apps, Board needs the **Input Monitoring** permission:

1. Choose **Request Input Monitoring**.
2. If macOS shows a prompt, choose **Open System Settings**. If no prompt appears, choose **Open Input Monitoring Settings** in Board.
3. If Board is missing from the list, use **+** below it to add Board from Applications. macOS may ask for your password before you can add an app.
4. In **Privacy & Security › Input Monitoring**, switch Board on. macOS asks for your password.
5. Quit Board and open it again. If macOS offers **Quit & Reopen**, choose it.
6. Check that Settings says **Listening to physical input**, then choose **Got it — continue** to finish the first run.

Without the permission Board still opens, and the sound previews in Settings work, but it can't hear your keys in other apps.

On the macOS 26.5.1 test system, a fresh request still showed no prompt and left the list empty after resetting Board's permission. **+** opened the account-password sheet; adding the app and granting access could not be completed without that password. Use the manual-add route above when Board is absent.

Keep `Board.app` in one place. macOS ties the permission to the app's identifier and signing identity, so an update signed with the same identity keeps it. The two updates tested so far did.

## Everyday controls

- **It stays out of the way.** Board does not open Settings when it starts, so starting it at login doesn't interrupt you. It opens Settings by itself only on the first run, until you choose **Got it — continue**, and whenever Input Monitoring is off.
- **Opening Board again opens Settings.** If Board is already running, opening it from Finder, Spotlight or the Dock shows Settings. This also works when you have hidden both of Board's icons.
- **The menu bar icon** has the everyday controls: turn Board on or off, mute, volume, the switch, mouse and Enter sounds, favorites, the visualizer, Practice and Settings.
- **A global shortcut turns Board on and off:** Control–Option–Command–K. You can change the key and how many taps it takes in **Settings › General**.
- **Icons:** Board can show a menu bar icon, a Dock icon, both or neither (**Settings › General**). The app icon comes in five colors: Porcelain, Sage, Blue, Lilac and Graphite.
- **Mac menus:** with the Dock icon on, Board has About, Services, Hide, the standard editing commands (including Undo and Redo), and a Window menu for Minimize, Zoom and Bring All to Front. About opens the About section in Settings. With the Dock icon off, Command-comma still opens Settings while a Board window is in front.

Board runs from the menu bar. [All features](FEATURES.md) describes its sounds, visualizers, and practice modes.
