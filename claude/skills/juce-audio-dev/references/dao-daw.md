# DAO DAW — Project Reference

A standalone digital audio workstation. **C++20, JUCE 8.0.12, CMake ≥ 3.22.**
Root: `~/dev/dao-daw`.

## Layout

```
dao-daw/
├── src/                # ~86 files, ~20k LOC
│   ├── ui/             # MainComponent, TransportControls, TimelineView, PianoRoll,
│   │                   #   SessionMatrix, MixerView, WaveformDisplay, BrowserPanel,
│   │                   #   DeviceLane, TrackInfoPanel, Icons, Theme
│   ├── audio/          # AudioEngine, AudioTrack, MixerChannel, AudioRecorder,
│   │                   #   TempoMap, AutomationCurve, PluginProcessor,
│   │                   #   TimeStretchProcessor, LFOModulator
│   ├── plugins/        # NativePluginFactory + native effects/instruments (see below)
│   ├── midi/           # MidiEngine, MidiTrack, MidiLearnManager
│   └── engine/         # Project, StateManager (singleton, undo/redo), VideoSync
├── JUCE/               # JUCE 8.0.12 as a git submodule (add_subdirectory)
├── cmake/              # helper cmake modules
├── tests/              # Catch2 v3 — unit/ integration/ stress/ fixtures/
├── docs/               # currently sparse; in-code doc comments are primary
├── build/  build-release/
└── TESTING.md          # main external doc: test org, fixtures, known limitations
```

## Build

JUCE is a **git submodule** — ensure it's checked out (`git submodule update --init
--recursive`) before configuring.

```bash
# Debug
cmake -B build -D CMAKE_BUILD_TYPE=Debug
cmake --build build --target DAO-DAW -j$(nproc)

# Release
cmake -B build-release -D CMAKE_BUILD_TYPE=Release
cmake --build build-release --target DAO-DAW -j$(nproc)

# Sanitizers — tests-scoped option enabling ASan + UBSan (NOT TSan); for memory/UB bugs.
# (For data races, add a separate -fsanitize=thread build; ASan and TSan can't combine.)
cmake -B build -D DAO_DAW_ENABLE_SANITIZERS=ON
```

**Target names:** app = `DAO-DAW` (PRODUCT_NAME "DAO DAW", COMPANY "DAO"). Tests =
`DAO-DAW-Tests`.

**JUCE modules linked:** `juce_audio_utils`, `juce_dsp`, `juce_gui_extra`,
`juce_opengl`, plus `juce_recommended_config_flags` and `juce_recommended_lto_flags`.

**External deps:** Rubber Band (via `pkg_check_modules`, for time-stretch/pitch),
CURL on Linux. `DAW_USE_ALSA=1` on Linux.

**Compile definitions:** `JUCE_WEB_BROWSER=0`, `JUCE_DISPLAY_SPLASH_SCREEN=0`,
`JUCE_REPORT_APP_USAGE=0`, `DAW_VERSION="${PROJECT_VERSION}"`.

## Testing (Catch2 v3)

87 tests across unit/integration/stress. Fixtures are generated WAVs (see
`tests/fixtures/generate_fixtures.py` — sine_440hz, stereo_pan, dual_tone, etc.).

```bash
cmake --build build --target DAO-DAW-Tests -j$(nproc)
cd build && ctest --output-on-failure
# Filter by Catch2 tag:
./tests/DAO-DAW-Tests "[unit]"
./tests/DAO-DAW-Tests "[audio_engine]"
```

Existing tagged suites: `TempoMap`, `AutomationCurve`, `MixerChannel`, `Project`,
`StateManager`, `AudioTrack`, `AudioEngine`, `DaoSynth`, plus integration (engine
renders fixtures) and stress (save/load cycles, memory stability). When you change
DSP or state logic, add a `TEST_CASE` with the matching tag.

## Architecture notes

- **AudioEngine** is the core: it subclasses `juce::AudioProcessorPlayer` and a
  private `juce::AudioProcessor`. Responsibilities: device management, the real-time
  callback, track mixing, sample-accurate playback timing (target latency < 5 ms).
  Playhead/transport/sample-rate are `std::atomic`; `processBlock` is allocation- and
  lock-free and explicitly commented "CRITICAL: runs on the audio thread."
- **TempoMap / AutomationCurve** are read on both UI and audio threads, guarded by
  `juce::SpinLock` so the audio thread never blocks. This is the reference pattern for
  shared read-mostly data here.
- **MixerChannel** holds atomic volume/pan/mute/solo and atomic meter levels.
- **Native plugins** (`src/plugins/`, built by `NativePluginFactory`): instruments
  and effects — `DaoSynth` (2 morphable wavetable oscillators + sub + noise, SVF
  filter, DAHDSR env, mod matrix, FX rack; oscillators are FFT band-limited per octave
  for alias-free output), `DaoSampler`, `DaoEQ`, `DaoCompressor`, `DaoReverb`,
  `DaoDelay`, `DaoLimiter`. Each is a `juce::AudioProcessor` with APVTS state. To add a
  new native effect, follow an existing one (e.g. `DaoDelay`) and register it in
  `NativePluginFactory`.
- **State / persistence:** `engine/Project` + `StateManager` (singleton) with
  `juce::UndoManager` for undo/redo and auto-save. Project files use the `.daodaw`
  format (JSON-based, e.g. `~/Documents/*.daodaw`). Synth presets live under
  `~/.config/DAO-DAW/DaoSynthPresets`.

## Conventions specific to DAO DAW

- Class doc comments spell out the thread-safety contract — preserve this when adding
  classes touched by the audio thread.
- Members are plain `camelCase` (e.g. `trackName`, `volume`), no prefix.
- Prefer reusing pre-allocated `readBuffer`/`mixBuffer` style scratch buffers in the
  engine rather than introducing per-block allocation.
