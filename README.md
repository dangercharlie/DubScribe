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

It lives in your menu bar. There is no window and no Dock icon, so there is
nothing to switch to: the app is wherever you already are.

<p align="center">
  <img src="screenshots/hud.png" width="420" alt="The level indicator: a frosted panel showing the app the clip will paste into, a dot-matrix waveform of the live input, and the elapsed time." />
</p>

<p align="center">
  <img src="screenshots/menu_bar.png" width="230" alt="The DubScribe menu: recording status, Start Recording, the situational settings nested with checkmarks, and quick access to the clips folder and Settings." />
  &nbsp;&nbsp;&nbsp;
  <img src="screenshots/settings_window.png" width="300" alt="DubScribe settings, on the Recording tab: shortcuts, microphone and sounds, with an Advanced section holding media handling and the level indicator." />
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

1. Launch it. A short welcome explains where the app lives and what to press.
2. Record — hold `⌃⌥Space`, or press `⌃⌥R` to start and stop. Both are rebindable.
   macOS asks for microphone access the first time, not at launch.
3. `⌘V` wherever the clip belongs.

The menu holds everything: the last clip and its playback, **Copy Last Clip
Again**, the clips folder, and Settings. The settings you change mid-task —
microphone, level indicator, pause media, mute system audio, delete clips
automatically — are nested right in the menu, so a quick change never means
opening a window.

## Features

- **Two ways to record.** Hold a key, or press once to start and again to stop.
- **Straight to the clipboard.** Finished clips are copied automatically as WAV.
- **A level indicator while recording** — the app your clip will paste into, a live
  dot-matrix waveform, and elapsed time. It never takes focus, appears over
  full-screen apps, and can be switched off.
- **Copy Again.** Re-copy the last clip without recording it a second time.
- **Input selection and a microphone test**, with a live level guide.
- **Optional media handling.** Pause Spotify, Music or browser audio and mute
  system output for the length of a recording, then put it all back.
- **Clips clean up after themselves** — see below.

Shortcuts use Carbon (`RegisterEventHotKey`), and pausing media uses MediaRemote,
the same channel the keyboard's media keys use — so **DubScribe never asks for
Accessibility permission**.

## Clips clean up after themselves

DubScribe is for getting audio onto your clipboard, not for building a library, so
clips are temporary by default. **A finished clip is never deleted while it is on the
clipboard** — however long it stays there. The folder is kept within a size budget
(250 MB by default), oldest clips first, and anything removed goes to the Trash where
*Put Back* still works. There is no timer: a clip is only ever removed when the folder
needs the room. The budget is configurable, and the whole behaviour can be turned off.

## Privacy

- **Offline.** The app makes no network calls of any kind.
- **The microphone is not held open.** It is live only while you are recording or
  while the mic test panel is open — no background listening, no standing indicator.
- **No telemetry, no crash reporting, no account.**
- Clips live in `~/Library/Application Support/DubScribe/Clips/` and are deleted
  through the standard Trash API, so nothing disappears silently.

## Accessibility

Native SwiftUI controls, labelled icon buttons, human-readable slider values, and
decorative elements hidden from VoiceOver — including the recording indicator,
which is skipped entirely because the menu-bar item already carries the state.
Feedback from VoiceOver, keyboard-only and neurodivergent users is very welcome.

## What's new in 0.7.0

This release was mostly a rebuild of how the app looks and feels.

- **Menu-bar only.** The main window is gone, along with the Dock icon. The
  settings you change while working moved into the menu, where they are checkmarks
  on the same state Settings edits.
- **A redesigned Settings window** — three tabs (General, Recording, Storage),
  native controls, and copy that explains itself rather than needing to be decoded.
- **A level indicator**, the most visible addition. Frosted, monochrome, drawn as a
  dot matrix, and adjustable from fully opaque to barely there.
- **Self-deleting clips.** A size budget, no timer, and a clip on the clipboard is
  never deleted.
- **Voice activation is gone.** It was unreliable and held Bluetooth headsets in
  low-quality call mode. Holding or pressing a shortcut now opens the microphone
  only on demand.
- **A fixed start cue**, Bluetooth headset handling, key-cap display, and a
  settings-decoding bug that could silently reset preferences.

Full detail in [CHANGELOG.md](CHANGELOG.md).

## Requirements

macOS 13 or later, Apple Silicon, microphone access.

## About

DubScribe is a vibe-coded experiment that turned into a tool I use every day. It
began from one line:

> Make a simple macOS app where a hotkey records a short WAV clip and
> automatically copies it to the clipboard.

The first release was written with ChatGPT for the product brief and Claude for
the implementation. **0.7.0 was built in conjunction with DeepSeek 4.1 Flash** —
including the menu-bar-only rebuild, the dot-matrix indicator, the redesigned
Settings, and a VoiceOver audit of the whole interface. Everything is reviewed
and tested by hand against real use.

It is an early release. The audio and hotkey paths are stable; expect rough edges
around unusual hardware and future macOS updates.

## License

MIT.

## Support

☕️ [Buy Me a Coffee](https://ko-fi.com/dangercharlie)
