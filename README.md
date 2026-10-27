# Lowdrift

A free, private, offline fan and air-conditioning sound generator for iPhone.
Open it, pick a sound, tap Play, lock the phone.

- Six procedurally generated sounds: Soft Fan, Box Fan, Basement AC, Air Vent,
  Tower Fan and Deep Drift. Nothing is a recording or a loop. Every sample is
  generated live from a long-period random number generator and shaped with
  lightweight filters.
- Three plain-language controls per sound (Depth, Airflow, Hum). They are saved
  on the device, and each sound can be reset on its own.
- Background playback, Lock Screen and Control Center controls, headphone
  buttons, and Shortcuts/Siri (Play, Pause, Play a sound).
- No ads, accounts, purchases, analytics, network access, microphone or
  permissions of any kind. See [PRIVACY.md](PRIVACY.md).

## Build and run

Requirements: Xcode 16 or later (built against the current iOS SDK). The app
runs on iOS 17 and later, on iPhone.

1. Open `Lowdrift.xcodeproj`.
2. Choose the **Lowdrift** scheme and an iPhone simulator, then press Run.
3. To run it on your iPhone: select the Lowdrift target, open **Signing &
   Capabilities**, and pick your team. If the default bundle identifier
   `app.lowdrift.Lowdrift` is taken, change it to your own. No other setup,
   accounts, keys or packages are needed. The Background Modes → Audio
   capability is already declared in `Config/Info.plist`.

## Tests

| What | How | Covers |
|---|---|---|
| Sound engine and app logic | `cd LowdriftKit && swift test` (macOS or Linux), or ⌘U in Xcode | Output bounds and non-silence, no clipping/DC/NaN, slider ranges, loudness matching, independence of the three controls, fades, crossfades, glides, restarts, sustained generation (2 min in Debug, 10 min in Release), no repetition, render cost, persistence, reset, corrupt settings, playback state machine, interruptions, route loss, retry, palette contrast |
| AVAudioEngine integration | `swift test` on macOS, or ⌘U in Xcode | The real `AVAudioSourceNode` render block inside a real `AVAudioEngine` (offline manual rendering) |
| App UI | ⌘U in Xcode (LowdriftUITests) | Fresh install opens on Basement AC, paused; six cards; selecting while paused stays paused; exactly three sliders; edits survive relaunch; Reset affects only that sound |
| Eight-hour render | `cd LowdriftKit && LOWDRIFT_OVERNIGHT_TEST=1 swift test -c release --filter testOvernightRenderStaysClean` | Eight simulated hours rendered offline: no NaN, peak below the limiter ceiling, minute-to-minute level steady |
| Privacy | `./scripts/privacy-audit.sh` | No network, tracking, recording, purchase or logging APIs in shipped code, no permission keys, empty privacy manifest |

CI (`.github/workflows/ci.yml`) runs the package tests on Linux and macOS,
builds the app for the iOS Simulator with the newest installed Xcode, checks the
built app's Info.plist and linked frameworks, and runs the UI and engine tests
in the simulator (`scripts/ci-ios.sh`).

### Listening without the app

`lowdrift-render` writes WAV previews of the real engine:

```sh
cd LowdriftKit
swift run -c release lowdrift-render                      # all six, 30 s each, into ./previews
swift run -c release lowdrift-render basementAC --seconds 120 --depth 90
swift run -c release lowdrift-render all --speaker        # as heard through the phone's speaker
```

## Needs validation on a physical iPhone

These cannot be proven by automated tests or the simulator. They are pending
acceptance checks until someone actually runs them on a device:

1. **Eight-hour locked-screen session.** Start Basement AC, lock the phone, leave
   it overnight on power and once on battery. Listen for dropouts, seams,
   swells or clicks. Afterwards confirm the app still shows Pause and Now Playing
   is still correct.
2. **Energy.** In Xcode, use Debug Navigator → Energy Impact with the screen
   locked, then Instruments' *Power Profiler* / *Energy Log* over at least an
   hour. Compare against playing a similar-level audio file in another player.
   No battery percentage is claimed until this has been measured.
3. **Interruptions.** A phone call, FaceTime, Siri, an alarm, and another app
   starting audio. Lowdrift should stop, then resume only when iOS says it may
   and only if it was playing.
4. **Routes.** Unplug wired headphones and disconnect AirPods mid-playback (it
   should pause, not move to the speaker). Also try a Bluetooth speaker and
   AirPlay, and switch while playing (sample-rate changes rebuild the engine).
5. **Controls outside the app.** Lock Screen, Control Center, headphone
   play/pause, and Shortcuts (“Play Lowdrift”, “Pause Lowdrift”, “Play Deep
   Drift in Lowdrift”) with the app closed.
6. **Silent switch and Airplane Mode.** Sound continues in Silent Mode. With
   Airplane Mode on, everything works and no permission prompt ever appears.
7. **Listening.** Tune by ear on the phone speaker and on good headphones: the
   presets should be clearly different at matched loudness, with no hiss, whine
   or pumping at any slider setting.
8. **Accessibility.** VoiceOver on every control, the largest Dynamic Type sizes,
   Increase Contrast, Reduce Motion (the waves stay still), and Dark Mode.

## How it is built

```
Lowdrift/                 SwiftUI app: one screen, the Customize sheet, App Intents
  App/                    App entry and the shared environment
  Views/                  Main screen, cards, sheet, waves, theme
  Intents/                Play, Pause, Play a sound; Siri phrases
  Resources/              Asset catalog (icon, colors, artwork), privacy manifest
Config/Info.plist         Background audio, launch screen
LowdriftKit/              Swift package with everything else
  LowdriftDSP             The procedural sound engine (real-time safe)
  LowdriftCore            Presets, on-device settings, playback state, palette
  LowdriftAudio           AVAudioEngine output, audio session events, Now Playing
  LowdriftAnalysis        FFT and loudness measurement (tests and tools only)
  LowdriftRender          lowdrift-render command-line tool
scripts/                  CI, privacy audit, icon generator
```

### The sound engine

Each sound is a voice with four layers, all driven by one xoshiro128+ generator
(period 2¹²⁸ − 1):

- **Airflow:** pink-tilted noise through state-variable band-pass and low-pass
  filters, which make the broad rush and its “whoosh” band.
- **Rumble:** separately filtered low noise for the distant HVAC body. It is
  high-passed so there is no uncontrolled sub-bass.
- **Motor:** up to eight quiet harmonics of a low motor tone, plus a narrow
  band of tonal noise. They are sized by their tone-to-noise ratio so that
  “More” never becomes a whine.
- **Microvariation:** very slow, smooth random drift (no LFOs) in brightness,
  level and motor speed.

The controls map to timbre, not volume:

- **Depth** moves the spectrum toward warm and bass-rich.
- **Airflow** changes the turbulence, the density of the rush band and the
  blade texture.
- **Hum** sets how present the motor is.

An analytic loudness model, fitted to ISO 532-1 loudness, sets the output gain
so the presets and slider positions stay at matched perceived loudness. A
headroom cap and a soft limiter keep the output clean. On the phone's built-in
speaker, deep bass the speaker cannot reproduce is removed rather than
overdriving it. At the most extreme Depth settings the headroom cap can leave
Deep Drift and Basement AC up to ~3 phon quieter than the others (~5 phon on
the phone speaker). That is a deliberate choice of clean sound over matched
loudness.

**Real-time rules.** The render callback never allocates, locks, logs, does
I/O or calls into the main thread. Controls cross threads as 32-bit atomic
words. The audio thread picks them up once per callback and interpolates every
change per sample. Starts fade in (1.1 s), pauses fade out (0.6 s), and preset
changes use an equal-power crossfade (1.4 s). After a pause fade the engine is
stopped completely, so a paused Lowdrift uses no CPU.

## Icon

`scripts/make_icons.py` draws the light, dark and tinted app icons and the Now
Playing artwork (requires Pillow and NumPy).

## License

MIT. See [LICENSE](LICENSE).
