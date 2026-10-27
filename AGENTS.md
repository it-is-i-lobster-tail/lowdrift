# Working on Lowdrift

Lowdrift is a free-forever, private, offline iPhone fan/AC noise generator for
sleep and focus. The experience is: open, select a sound, Play, lock the phone.
It is not a DAW. Read the README for the layout and how to test.

## Non-negotiables

- No ads, subscriptions, purchases, accounts, tracking, analytics, servers,
  networking, microphone or permission prompts. Settings stay on the device
  (UserDefaults). `scripts/privacy-audit.sh` must keep passing.
- Swift and SwiftUI with Apple frameworks only; no third-party packages in the
  app.
- One main screen and one native Customize sheet:
  - The lowercase “lowdrift” wordmark sits at the upper left, with no gear,
    tabs, onboarding, settings or sleep timer.
  - The Customize sound row has no chevron.
  - Loudness comes from the hardware volume buttons; there is no in-app volume
    slider.
- Launch selects the last-used sound (Basement AC on first launch) and stays
  paused. Never start audio the user didn't ask for.
- The six sounds keep their names, subtitles and order: Soft Fan, Box Fan,
  Basement AC, Air Vent, Tower Fan, Deep Drift.

## Sound

- Everything is generated live from the PRNG. Never add recordings, pre-rendered
  buffers or loops.
- Depth = spectral warmth/body, Airflow = rush/turbulence texture, Hum = quiet
  motor harmonics.
  - None of the three is a volume control, and they stay independent.
  - Extreme settings stay pleasant: no hiss, whine, pumping or sudden shifts.
- Basement AC is the signature sound: a soft, deep “whoooosh” with a little
  distant mechanical hum.
- Any tuning change must keep the LowdriftKit tests green. Listen with
  `lowdrift-render` before and after.

## Real-time audio rules

`NoiseRenderer.render` and the `AVAudioSourceNode` block must never allocate,
lock, log, do I/O, `await`, touch the main actor or UI, or block. That includes:

- no arrays,
- no stored global or static `let`s read on the audio thread (use computed
  constants),
- no `print`.

Hand values to the audio thread only through the atomic control words, and
interpolate every change.

## Power

- When paused, the engine is stopped: no timers, no polling, no work.
- The decorative waves animate only while the app is in the foreground, sound
  is playing and Reduce Motion is off. They are never an FFT/visualizer.

## UI

- Calm, airy, premium: SF Pro, SF Symbols, generous spacing, 16–20 pt corners,
  subtle shadows, restrained motion.
- Light mode first; dark mode is midnight blue. Use the `Palette` tokens (their
  contrast is unit-tested). Don't hard-code colors.
- Native controls and sheets; Liquid Glass only where the system provides it.
  Legibility comes first.
- Every control needs a VoiceOver label/value, works at the largest Dynamic Type
  sizes, has a large tap target and respects Reduce Motion.

## Honesty

Report what was compiled and tested, and on what. Physical-device checks (the
eight-hour locked session, energy profiling, interruptions, routes, remote
controls) count only when they were actually performed on an iPhone.
