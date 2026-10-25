# Design and API references

Reviewed 2026-09-10. Public references remain separate from shipped original artwork.

- [Pinned kbsim source](https://github.com/tplai/kbsim/tree/ba103f3b0afa9dab80447aa2e7e2ed80b6bd80e4/src/assets/audio), [MIT notice](https://github.com/tplai/kbsim/blob/ba103f3b0afa9dab80447aa2e7e2ed80b6bd80e4/LICENSE.md).
- [Apple guidance on listen-only taps and Input Monitoring](https://developer.apple.com/forums/thread/811443). The installed SDK documents the root restriction for HID-level taps; this app uses a passive **session** tap instead.
- [Native spatial audio](https://developer.apple.com/documentation/avfaudio/avaudioenvironmentnode), [headphone motion](https://developer.apple.com/documentation/coremotion/cmheadphonemotionmanager), [login service](https://developer.apple.com/documentation/servicemanagement/smappservice).

- [Typewriter keystrokes by Cassie-OrbitGames](https://opengameart.org/content/typewriter-sounds), CC0 1.0. Four recordings, published September 6, 2025; preserved originals in `Docs/References/typewriter/`, preparation in `Scripts/prepare_typewriter.py`, and provenance/hashes in `Docs/typewriter-assets.json`.

## Visual direction and recreation

The app uses native AppKit menus and SwiftUI controls, a compact gray/material foundation, rounded keycaps, and accents from the brand palette that follow the chosen icon color. The app icons (Porcelain, Sage, Blue, Lilac, Graphite) and the menu bar glyph come from the Board Keycap brand package (`Board-Keycap-Brand-Package.zip`). Keyboard layouts and theme previews come from the same runtime geometry.

The Settings sidebar and cards are an interpretation of the documented sections. Full pixel-level parity with undocumented screens, original switch illustrations, and every physics/animation detail has not been established. No website wallpaper, stock photography, web fonts, airplane, or globe assets ship in the app.
