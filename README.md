<p align="center">
  <a href="https://github.com/dangercharlie/DubScribe/releases"><img src="https://img.shields.io/github/v/release/dangercharlie/DubScribe?label=release&style=flat" alt="Latest release" /></a>
  <a href="https://github.com/dangercharlie/DubScribe"><img src="https://img.shields.io/badge/macOS-13%2B-000000?style=flat&logo=apple&logoColor=white" alt="macOS 13 or later" /></a>
  <a href="https://github.com/dangercharlie/homebrew-tap"><img src="https://img.shields.io/badge/Homebrew-cask-FBB040?style=flat&logo=homebrew&logoColor=black" alt="Homebrew cask" /></a>
  <a href="https://github.com/dangercharlie/DubScribe"><img src="https://img.shields.io/badge/Local_only-no_cloud-238636?style=flat" alt="Local-only, no cloud" /></a>
  <a href="LICENSE"><img src="https://img.shields.io/github/license/dangercharlie/DubScribe?style=flat" alt="License" /></a>
</p>

**DubScribe** is a small macOS utility for low-friction audio capture.

> Shortcut → record → paste

Hold a key, say the thing, release. The clip lands on your clipboard as a WAV,
ready to paste — no editor, no library, no save dialog, no file hunting.

<p align="center">
  <img src="screenshots/menu_bar.png" width="260" alt="The DubScribe menu: recording status, Start Recording, and quick access to the last clip, Settings and the clips folder." />
  &nbsp;&nbsp;&nbsp;
  <img src="screenshots/settings_window.png" width="350" alt="DubScribe settings, on the Recording tab: shortcuts, microphone and sounds, with an Advanced section holding media handling and the level indicator." />
</p>

---

## Install

Download the latest `.dmg` from [Releases](https://github.com/dangercharlie/DubScribe/releases)
and drag **DubScribe** to your Applications folder. Or:

```bash
brew install --cask dangercharlie/tap/dubscribe
```

DubScribe is unsigned, so macOS may need a nudge the first time — right-click the
app and choose **Open**, or clear the quarantine flag:

```bash
xattr -dr com.apple.quarantine /Applications/DubScribe.app
```

## Use

1. Launch DubScribe and grant microphone access.
2. Set your shortcuts in Settings. The defaults are `⌃⌥Space` to hold and `⌃⌥R` to toggle.
3. Record — press once, or hold and release.
4. `⌘V` wherever the clip belongs.

DubScribe lives entirely in the menu bar: there is no main window and no Dock icon.
The menu holds everything — start and stop, the last clip, playback, Settings, and the
clips folder.

## Features

- **Two ways to record.** Hold a key, or press once to start and again to stop.
- **Straight to the clipboard.** Finished clips are copied automatically as WAV.
- **A level indicator while recording** — the app the clip will paste into, a live
  waveform, and elapsed time. It never takes focus, appears over full-screen apps,
  and can be switched off.
- **Copy Again.** Re-copy the last clip without recording it a second time.
- **Input selection and a microphone test**, with a live level guide.
- **Optional media handling.** Pause Spotify, Music or browser audio and mute
  system output for the length of a recording, then put it all back.
- **Clips clean up after themselves** — see below.

Shortcuts use Carbon (`RegisterEventHotKey`), so **no Accessibility permission is
required**.

## Clips clean up after themselves

DubScribe is for getting audio onto your clipboard, not for building a library, so
clips are temporary by default. **A finished clip is never deleted while it is on the
clipboard** — however long it stays there. The folder is kept within a size budget
(250 MB by default), oldest clips first, and anything removed goes to the Trash where
*Put Back* still works. There is no timer: a clip is only ever removed when the folder
needs the room. The budget is configurable, and the whole behaviour can be turned off.

## Privacy

- **Offline.** No network calls of any kind.
- **The microphone is not held open.** It is live only while you are recording or
  while the mic test panel is open — no background listening, no standing indicator.
- **No telemetry, no crash reporting, no keylogging.**
- Clips live in `~/Library/Application Support/DubScribe/Clips/` and are deleted
  through the standard Trash API, so nothing disappears silently.

## Accessibility

Native SwiftUI controls, labelled icon buttons, human-readable slider values, and
decorative elements hidden from VoiceOver — including the recording indicator,
which is skipped entirely. Feedback from VoiceOver, keyboard-only and
neurodivergent users is very welcome.

## Requirements

macOS 13 or later, Apple Silicon, microphone access.

## About

DubScribe is a vibe-coded experiment that turned into a tool I use every day. It
began from one line:

> Make a simple macOS app where a hotkey records a short WAV clip and
> automatically copies it to the clipboard.

The first release was written with ChatGPT for the product brief and Claude for
the implementation. **0.7.0 was built in conjunction with DeepSeek 4.1 Flash** —
including self-deleting clips, the recording indicator and its dot-matrix
waveform, and a VoiceOver audit of the whole interface. Everything is reviewed
and tested by hand against real use.

It is an early release. The audio and hotkey paths are stable; expect rough edges
around unusual hardware and future macOS updates. Release notes live in
[CHANGELOG.md](CHANGELOG.md).

## License

MIT.

## Support

☕️ [Buy Me a Coffee](https://ko-fi.com/dangercharlie)
