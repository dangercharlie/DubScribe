<p align="center">
  <a href="https://github.com/dangercharlie/DubScribe"><img src="https://img.shields.io/badge/macOS-Apple_Silicon-000000?style=flat&logo=apple&logoColor=white" alt="macOS" /></a>
  <a href="https://github.com/dangercharlie/DubScribe"><img src="https://img.shields.io/badge/Telemetry-None-238636?style=flat" alt="Telemetry" /></a>
  <a href="https://github.com/dangercharlie/DubScribe"><img src="https://img.shields.io/badge/Privacy-Local_Only-238636?style=flat&logo=lock&logoColor=white" alt="Privacy" /></a>
  <br/>
  <a href="https://github.com/dangercharlie/DubScribe"><img src="https://img.shields.io/badge/Build-Transparent-007EC6?style=flat&logo=githubactions&logoColor=white" alt="Build" /></a>
  <a href="https://github.com/dangercharlie/DubScribe"><img src="https://img.shields.io/badge/Accessibility-Active_Testing-007EC6?style=flat&logo=apple&logoColor=white" alt="Accessibility active testing" /></a>
  <a href="https://github.com/dangercharlie/DubScribe"><img src="https://img.shields.io/badge/Vibe_Coded-Human_Reviewed-007EC6?style=flat" alt="Vibe Coded" /></a>
</p>

**DubScribe** is a lightweight macOS utility for low-friction audio capture.

The core workflow is simple:

> Shortcut → record → paste

It is designed for moments when you want to capture a short audio clip without opening a full audio editor, managing a voice memo library, exporting a file manually, or transcribing your voice into text.

DubScribe captures the original audio as a pasteable WAV file.

<p align="center">
  <img src="screenshots/main_window.png" width="350" alt="DubScribe main window showing a green success checkmark, 'Copied to clipboard' message, and playback controls for the last recorded audio clip." />
  &nbsp;&nbsp;&nbsp;
  <img src="screenshots/settings_window.png" width="350" alt="DubScribe settings window displaying options for customizable recording shortcuts, audio input device selection, voice activation toggle, and a live microphone test meter." />
</p>

---

## Why?

macOS has plenty of ways to record audio, but most involve opening another app, saving or exporting a file, finding it, then attaching or dragging it somewhere.

DubScribe solves a narrower problem:

> I want to capture a short audio clip and paste it immediately.

It is designed for low-clutter workflows where reducing small steps matters — especially if file hunting, extra windows, save dialogs, or context switching create friction.

Think of it like a screenshot tool, but for quick WAV audio snippets.

---

## Low-Clutter Workflow

DubScribe is built around reducing small workflow costs.

The intended loop is:

> configure once → use a shortcut → paste the result

This may be useful for people who prefer predictable, low-interruption workflows, including users who experience ADHD-related task switching, cognitive overload, or file-management clutter.

DubScribe is not trying to replace platform accessibility tools. It is a focused utility for quickly creating a pasteable audio file with minimal context switching.

---

## Features

- Native macOS app built with SwiftUI
- Apple Silicon focused
- Records short WAV audio clips
- Automatically copies finished recordings to the clipboard
- Global hotkey recording
- Push-to-record and hold-to-record workflows
- Menu bar utility design
- Last recording preview/playback
- Input source selection
- Voice activation support
- Mic test / input feedback
- Optional media pause/resume while recording
- Launch at login
- Local-only: no cloud, telemetry, AI, or transcription

---

## Installation

1. Download the latest `.dmg` from the [Releases](https://github.com/dangercharlie/DubScribe/releases) page.
2. Open the `.dmg` and drag **DubScribe** to your `Applications` folder.
3. Launch DubScribe. *(Note: Since this is an unsigned indie app, you may need to Right-Click -> Open the first time, or allow it in System Settings -> Privacy & Security).*

---

## What's Changed

See [CHANGELOG.md](CHANGELOG.md) for release notes.

---

## Basic Usage

1. Launch **DubScribe**.
2. Grant microphone permission when prompted.
3. Set your preferred recording hotkeys in Settings.
4. Press your recording hotkey.
5. Speak for a few seconds.
6. Stop or release the hotkey.
7. DubScribe saves the clip as a WAV and copies it to the clipboard.
8. Press `Cmd + V` in a compatible app or folder to paste the WAV file.

---

## Recording Modes

DubScribe supports multiple quick recording styles:

### Hold to Record

Hold the configured shortcut to record.  
Release the shortcut to stop recording and copy the WAV to the clipboard.

### Push to Record

Press the configured shortcut once to start recording.  
Press it again to stop recording and copy the WAV to the clipboard.

### Voice Activation

DubScribe can listen for input above a configurable threshold and automatically record when speech is detected.

The threshold slider helps avoid accidental recordings from background noise.

---

## How It Compares

DubScribe is intentionally small and specific.

- Voice Memos is better for longer personal recordings, but not instant hotkey-to-clipboard capture.
- QuickTime and traditional recorders can capture audio, but usually involve manual saving, exporting, and file hunting.
- Dictation tools turn speech into text. DubScribe keeps the original audio as a pasteable WAV.
- Larger capture tools may handle screenshots, video, and audio. DubScribe only focuses on quick microphone WAV capture.

---

## Requirements

- macOS
- Apple Silicon Mac
- Microphone access

---

## Privacy & Security

DubScribe is a local-only utility designed for maximum transparency.

✅ **100% Offline:** Zero internet connections, no cloud sync, and no APIs.  
✅ **Local Storage:** Files are written straight to your local sandbox (`~/Library/Containers/`).  
✅ **Blind Hotkeys:** Uses Carbon APIs (`RegisterEventHotKey`) so it doesn't need invasive Accessibility permissions to monitor your keyboard.  
❌ **No AI Models:** Zero speech-to-text or semantic processing. "Voice Activation" just mathematically measures microphone volume.  
❌ **No Telemetry:** Zero crash reporters or product analytics.  
❌ **No Keylogging:** It only responds to the exact shortcut you configure.  

---

## Accessibility

DubScribe aims to support simple keyboard and VoiceOver-friendly workflows.

Current accessibility work includes:

- Native SwiftUI controls where possible
- Descriptive labels for icon-only buttons
- Human-readable slider values
- Decorative visual elements hidden from VoiceOver
- A workflow designed to avoid unnecessary windows, save dialogs, and file browsing

Feedback from VoiceOver users, keyboard-only users, and neurodivergent users is very welcome.

---

## Development Notes

DubScribe was created as a small native macOS app experiment using Xcode and AI-assisted development.

Initial product brief and iteration prompts were written with ChatGPT.  
The working app was generated and refined in Antigravity using Claude Sonnet 4.6.

The goal was to see whether a focused native utility could be built quickly from a clear product brief:

> Make a simple macOS app where a hotkey records a short WAV clip and automatically copies it to the clipboard.

---

## Status

Early release.

The core audio and hotkey systems are stable, but expect some rough edges around edge-case hardware or future macOS updates.

---

## License

DubScribe is released under the MIT License.

---

## Support

If you find DubScribe useful, consider buying me a coffee!  
☕️ [Buy Me A Coffee](https://ko-fi.com/dangercharlie)
