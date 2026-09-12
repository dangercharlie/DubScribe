# Changelog

## v0.7.2

### Fixed

- **"Pause media playback" could hang forever and stay broken for the rest of the
  session.** When Chrome was running, DubScribe drove JavaScript into every open
  tab to look for browser media. A tab that accepts the request but never answers
  left that Apple Events call waiting with no timeout, which stalled the media
  controller and stopped everything queued behind it. QuickTime never paused at
  all, because it has no dedicated code path and relies on the fallback that ran
  after the Chrome sweep; resume stopped working for *every* player, including
  the ones that had paused correctly, because the same stalled controller was
  still holding the next call. Closing and reopening the app was the only way
  back. Reproduced with one unresponsive Chrome tab out of seven.

  Three changes, each verified against a Chrome window engineered to hang:
  Apple Events calls now time out after 3 seconds and are abandoned rather than
  waited on; the reliable system-level fallback runs *before* the tab sweep
  instead of after it; and the sweep is skipped entirely unless Chrome is
  actually producing audio, so a silent Chrome window costs nothing. With the
  sweep deliberately forced to hit the hanging tab, pause and resume both still
  complete normally.

## v0.7.1

### Fixed

- **"Pause media playback" no longer launches Apple Music.** With the setting on
  and nothing playing, finishing a recording opened Music. The MediaRemote fallback
  had no way to tell "I paused something" from "I sent a command into the void", so
  it recorded a pause that never happened; the later play was read as *start
  playback* and Music launched. Reproduced 6 times out of 6. The fallback is now
  gated on another process actually producing audio output, so a play is only ever
  sent if a pause was really sent. Nothing else about recording changes. This also
  affected 0.6.4, whose guard shelled out to `nowplaying-cli` and failed open when
  it was absent.
- On macOS 13 the per-process audio check is unavailable, so the catch-all
  fallback is skipped rather than risk launching Music. Spotify, Music, VLC and
  Chrome still pause and resume normally, because those paths are only reached
  when the app is already running.

### Changed

- The release workflow now builds a **draft** and pins the tag explicitly. The
  draft-tag behaviour had been associating releases with a placeholder name, which
  would have left the Homebrew cask download URL pointing at a tag that does not
  exist.

## v0.7.0

### Added

- **The opacity slider previews the indicator.** Adjusting it brings the real
  indicator up so the setting can be judged against the actual desktop rather than
  from memory. Nothing is recorded. The preview is drawn as a single still frame:
  it does not scroll, so what is being judged is the appearance and nothing else,
  and it costs about half the CPU of the live trace (measured 6.8% against 13.3%
  of one core, on identical builds — while drawing a full waveform to the live
  version's flat line). The opacity is applied on every change rather than only on
  release, so the preview's frost follows the slider as it moves. If a recording is
  already in progress the real indicator is on screen, so no preview appears and the
  live one simply restyles.

- **Self-deleting clips.** A recording now moves itself to the Trash instead of
  accumulating in the clips folder forever. A clip sitting on the clipboard is never
  deleted, however long it stays there. The folder is kept within a size limit
  (default 250 MB), oldest clips first, and the behaviour can be turned off entirely.
  There is deliberately no time-based expiry: an earlier design trashed a displaced
  clip two minutes after it left the clipboard, which broke the one promise a
  clipboard tool must keep.
- **Copy Last Clip Again**, in the dashboard and the menu bar — re-copies the most
  recent clip without recording it again.
- **Clip storage panel** in Settings, showing the clips folder and its size limit,
  with a Show in Finder button.
- Dashboard empty state, app mark, and clip glyph as vector assets, with a defined
  accent colour.
- **A level indicator while recording.** A small floating panel at the top of the
  screen — where macOS puts the volume HUD — showing the destination app, a scrolling
  dot-matrix waveform of the live input, elapsed time, and a brief confirmation when the
  clip lands on the clipboard. It never takes focus, and appears over full-screen apps
  and on every Space. It can be turned off in Settings, and VoiceOver skips it entirely
  because the menu-bar item carries the accessible state.
- **The indicator names where the clip will land.** The app that was frontmost when
  capture began is shown beside its own icon, so the paste destination is visible before
  you paste — the same promise as the clipboard behaviour, made one step earlier. When
  DubScribe itself had focus, the last other app is named instead.
- **Adjustable indicator opacity**, defaulting to the lightest frost the indicator has
  ever had. The scale was rebuilt so its top is the old *minimum*: the previous 15%
  setting is exactly what 100% means now, and everything below it is more transparent
  than the app could previously go. Only the backdrop is affected — the dot matrix and
  text stay fully opaque, so the indicator remains readable however much of the desktop
  shows through.

### Changed

- **DubScribe lives in the menu bar.** The main window is gone — the app now runs
  without a Dock icon or an application menu, and everything it does is reachable
  from its menu-bar icon. The settings you reach for while working (microphone,
  level indicator, pause media, mute system audio, delete clips automatically) are
  nested directly in that menu, so a mid-task change no longer means opening a
  window. Audio playback and Show in Finder moved there too. Settings is
  unchanged as a place to configure things properly.
- **A welcome window on first launch**, explaining that the app lives in the menu
  bar, what to press, and where the clip goes. A menu-bar-only app has a
  discoverability problem — you launch it and, as far as the screen is concerned,
  nothing happens.
- **A "What's New" window** appears once after an update, summarising what changed
  in the version you have just started using. It never appears on a first install,
  where it would tell you nothing you could act on.
- **The indicator is no longer hidden from screen capture.** It previously set
  `sharingType = .none`, which excludes a window from *every* capture client — including
  your own `⌘⇧4` screenshots, so the indicator could never be shown, demoed, or reported
  on. Measured both ways: a `.none` window is absent from full-display capture while a
  default one is present. It now uses the system default, so it appears wherever you
  record your screen — which is how other menu-bar indicators behave.
- **The opacity slider now has real travel in both directions.** A tint can only *add*
  darkness, so the old range ran out of room at the light end and the slider did
  progressively less. The setting now raises the material's own alpha across the lower
  half of its range as well as driving a tint over it, so the panel can genuinely recede:
  full frost at the top, composited down to 60% at the bottom. Measured over black and
  white stripes, contrast behind the panel falls from stdev 111.2 at 0% to 101.3 at
  100% — real, though most of the visible change is in the bottom third.
- **The interface now follows your system appearance.** The window previously used a
  hardcoded dark gradient and ignored light/dark mode; it now uses standard macOS
  semantic colours and materials, and switches with the system.
- **DubScribe no longer writes a log file.** It appended to
  `~/Library/Logs/DubScribe-media.log` on every media event, with no rotation
  and no size cap — a file that grows for the life of the install, in a
  location the app never mentioned. Diagnostics go to the console only now.
- Clips moved from `~/Music/DubScribe/Clips/` to
  `~/Library/Application Support/DubScribe/Clips/`. Existing clips are migrated
  automatically on first launch.
- The About panel now reads the real bundle version, which previously could drift from
  the actual build.
- Settings uses native controls (standard switches, pickers and prominent buttons).
- The recording-duration timer runs only while recording, instead of redrawing the
  whole window ten times a second forever.
- **The start cue is now opt-in, and off by default.** The waveform indicator covers
  "did it start?" without putting a sound into the room, and while the cue is off there
  is no pre-roll delay, so capture begins immediately. It stays available in Settings for
  anyone who cannot see the indicator.

### Fixed

- **"Pause media playback" no longer needs Accessibility, and now actually
  pauses.** The feature previously posted a synthetic media key with `CGEvent`,
  which only works if the user has granted Accessibility — a large ask for
  "pause my music while I record", described in Settings as though it needed
  nothing. It failed silently when the permission was missing, and the only
  hint was a line in a log file. It now uses MediaRemote, the same private
  framework the keyboard's media keys go through, loaded dynamically so a
  change on Apple's side degrades to "did not pause" rather than a crash.
  Verified on macOS 26 with `CGPreflightPostEventAccess() == 0`: six
  record/stop cycles, playback paused and resumed every time. The pause and
  resume commands are distinct (1 and 0, not a toggle), which an earlier
  version of this change got wrong — playback paused and never came back.

- **Dock → Quit now works while Settings is open.** Settings was presented as a sheet,
  and a sheet runs a modal session that makes macOS refuse to quit: the quit Apple Event
  came back as `userCanceledErr (-128)` *before* `applicationShouldTerminate` was ever
  called, so no app delegate could intercept it. Settings is now its own window, which
  is also the standard macOS pattern for preferences.

- **The level indicator no longer scrolls, so it can no longer stutter.** The capture tap
  is stuck at ~10 Hz: `AVAudioEngine` ignores `installTap(bufferSize:)`, measured
  delivering 4800-frame buffers at 10.7 Hz for *every* requested size up to 4096. The
  indicator originally drew a scrolling history of that stream, which meant bars were born
  at one edge and died at the other, and the trace sat still between callbacks. Positioning
  each bar by age made it slide continuously, but an entry and an exit were still inherent
  to the design. It is now drawn as a thirteen-row dot matrix — each column one time bin,
  its amplitude lighting dots outward from the centre row — and the two edges fade, so
  columns dissolve in and out rather than appearing and vanishing at full strength. The
  scroll itself is unchanged and still driven by age, which is what makes it continuous
  rather than stepping at the tap's rate. The waveform's dB floor was also raised from -55
  to -45: at the old floor ordinary speech sat near full height, so the matrix read as a
  solid blob instead of a legible shape.
- **The start cue was being recorded into the clip.** It played *after* the microphone
  had already opened, so every recording began with a cue transient about 140 ms in, at a
  level comparable to speech. The cue now plays before capture starts. The lead-in is a
  fixed 0.2 s rather than `NSSound.duration`, because these system sounds carry long
  silent tails: `Tink` reports 0.564 s but is audible for only ~40 ms, so waiting on the
  reported duration would have added ~0.7 s of lag to every recording.
- **The start/stop cue is no longer jarringly loud.** It played at full system
  output volume, which a user reported as "the beep very loud even when im using the
  integrated mic" — the cue is unrelated to the chosen input, so it now plays at 35%.
- **Shortcut labels no longer show raw key codes.** A shortcut such as `` ⌃` `` was
  displayed as `⌃Key(50)`, because only letters, digits, space, return and the function
  keys had readable names. Punctuation, keypad and navigation keys are now mapped.
- **Bluetooth headsets are no longer held in low-quality call mode.** Voice activation
  kept a microphone stream open at all times, which forced macOS to keep a connected
  Bluetooth headset in narrowband HFP. Recording now opens the microphone only on
  demand, and the device is released as soon as recording or monitoring stops. The
  microphone test panel now names the device it is testing and explains the switch.
- **Global shortcuts can no longer be set without a modifier.** A shortcut recorded
  without ⌃, ⌥ or ⌘ (a bare `R`, for example) was registered system-wide and swallowed
  that key in every app, making it untypable. Such combinations are now rejected with an
  explanatory message, and any already saved in that state are repaired on launch.
- **Removing voice activation no longer resets your settings.** The settings decoder
  treated the voice-activation keys as required; with those keys gone, decoding failed
  and every preference silently reverted to defaults. All fields now fall back
  individually, and unreadable settings are reported rather than disguised as a fresh
  install.
- **A recording that captured nothing is discarded** instead of being copied to the
  clipboard as silence, which previously looked like the app was broken.
- **Microphone test clips are cleaned up.** They were written to the temp folder and
  never deleted, leaking a WAV per test.
- **A failed recording start no longer leaves a partial WAV** in the clips folder.
- **"Play Test Clip" no longer appears for an empty clip.** State was set from the
  presence of a URL rather than the presence of audio.
- **Paste fallback added.** Alongside the file URL, the plain-text path is now placed on
  the clipboard, so pasting into a terminal or text field does something useful instead
  of nothing. The code comment previously described this behaviour; the code did not
  implement it.
- Clips recorded twice within the same second no longer overwrite each other.
- System volume is only restored after a muted recording if you have not changed the
  volume yourself in the meantime.

- **VoiceOver now announces what each setting actually does.** The switches in
  Settings carried no accessible label of their own — their visible titles were
  published as separate text elements — so VoiceOver read them as "switch, on"
  with no indication of what was being switched. All seven are labelled now, the
  opacity slider is labelled like its neighbours already were, and two decorative
  icons that were announcing raw SF Symbol names (literally
  "clock.arrow.circlepath") are hidden from assistive tech.
- **The recording indicator is now genuinely invisible to VoiceOver.** It was
  hidden on its hosting view, which was not enough: the panel still surfaced as
  an `AXSystemDialog` exposing the destination app name and the elapsed timer, so
  VoiceOver could land on a stray dialog mid-recording. The window now overrides
  its own accessibility, and the content is hidden as well. Verified by dumping
  the app's own accessibility tree: the indicator no longer appears in it at all.

### Removed

- **Voice activation.** It could start recording from ambient noise, was the buggiest
  capture path in the app, and made the microphone permanently active. Recording now
  starts only when you ask it to. The microphone test panel remains, with its own
  threshold setting.

### Known limitations

- Pausing browser media other than Chrome relies on media keys and needs Accessibility
  permission; Chrome pausing additionally requires "Allow JavaScript from Apple Events"
  to be enabled in Chrome's Develop menu, and fails silently without it.

## v0.6.4

- Improved the release DMG layout with a standard drag-to-Applications install window.
- Added a Homebrew cask install path.
- Bumped the app version to 0.6.4, build 10.

## v0.6.3

- Added optional media pause/resume while recording.
- Pauses common playback sources including Chrome web media, VLC, Spotify, Music, and system Now Playing fallback where permissions allow.
- Fixed the recording-start stutter by moving media control work off the main UI thread.
- Kept the cleaner recording timer/button animation behavior while preserving the original recorder ring styling.
- Bumped the app version to 0.6.3, build 9.
