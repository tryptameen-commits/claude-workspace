# SeqFX — Project Reference

A sequenced multi-effects audio plugin: 6 effects in series (Filter, Delay, Reverb,
Distortion, Chorus, Sidechain Compressor) with a host-synced step sequencer that can
draw/automate 18 lanes (3 per effect) independently. **C++20, JUCE 8.0.12, CMake ≥
3.22.** Ships VST3 + AU + Standalone. Root: `~/dev/seq-fx`.

## Layout

```
seq-fx/
├── src/                    # ~36 files
│   ├── PluginProcessor.{cpp,h}   # AudioProcessor — the plugin entry point
│   ├── PluginEditor.{cpp,h}      # editor / GUI root
│   ├── dsp/                # FilterEngine (SVF/TPT), DelayEngine, ReverbEngine,
│   │                       #   DistortionEngine (tanh), ChorusEngine,
│   │                       #   SidechainCompressorEngine
│   ├── sequencer/          # ParameterMatrix.h (lane/param definitions),
│   │                       #   SequencerState, SequencerEngine,
│   │                       #   SequencerUndoableActions.h
│   └── ui/                 # ToolbarComponent, SequencerMatrixComponent,
│                           #   EffectSection, LaneComponent, GateLaneComponent,
│                           #   EffectControls
├── tests/main.cpp          # custom assertion harness → target SeqFX_Tests
├── installer/              # windows.iss(.in) — Inno Setup
├── build/                  # SeqFX_artefacts/ output
├── README.md  USER_MANUAL.md
└── EULA.txt  PRIVACY.txt  LICENSE
```

## Build

JUCE is pulled via **FetchContent**, pinned to `GIT_TAG 8.0.12` (shallow). No
submodule needed; first configure downloads JUCE.

```bash
cmake -B build -D CMAKE_BUILD_TYPE=Release
cmake --build build --config Release -j$(nproc)
```

`COPY_PLUGIN_AFTER_BUILD TRUE` auto-installs the built VST3 to the user plugin dir
(`~/.vst3/SeqFX.vst3` on Linux). Artifacts:

- VST3: `build/SeqFX_artefacts/Release/VST3/SeqFX.vst3/`
- AU (macOS): `build/SeqFX_artefacts/Release/AU/SeqFX.component/`
- Standalone: `build/SeqFX_artefacts/Release/Standalone/SeqFX`

**`juce_add_plugin` key args** (don't change these casually — host caches identify the
plugin by code): `PLUGIN_MANUFACTURER_CODE Sefx`, `PLUGIN_CODE Sfx1`,
`FORMATS VST3 AU Standalone`, `IS_SYNTH FALSE`, `NEEDS_MIDI_INPUT/OUTPUT FALSE`,
`IS_MIDI_EFFECT FALSE`. **Modules:** `juce_audio_utils`, `juce_dsp`,
`juce_gui_extra`, plus recommended config/warning flags. **Compile defs:**
`JUCE_WEB_BROWSER=0`, `JUCE_USE_CURL=0`, `JUCE_VST3_CAN_REPLACE_VST2=0`.

## Testing (custom harness)

No external framework — `tests/main.cpp` is an assertion-based harness linked against
`juce_core`, `juce_dsp`, `juce_audio_basics`.

```bash
./build/tests/SeqFX_Tests
```

Existing groups: `testParameterMatrix` (normalization, min/max, unit formatting),
`testSequencerState` (grid sizing, step/gate values, effect order, bypass/solo,
serialization round-trip), `testSequencerEngine` (host sync, MIDI sync, swing, Hold vs
Glide interpolation), `testDSPSafety` (each engine processes buffers without crashes
and yields finite values). When you add an effect or change sequencer/state logic, add
a matching check function and call it from `main`.

## Architecture

### Parameters — APVTS + ParameterMatrix
`ParameterMatrix.h` defines the 18 sequencable lanes (3 per effect) with min/max and
`isLogarithmic` flags, e.g. Filter Cutoff 20 Hz–20 kHz (log), Resonance 0.001–10, Mix
0–1; Delay Time 1–3000 ms; etc. Plus globals: Bars, StepsPerBar, Interpolation, Swing,
InputGain, OutputGain, DryWet, SyncMode. All live in `juce::AudioProcessorValueTreeState`.

### State save/load
`getStateInformation` / `setStateInformation` serialize APVTS **and** the sequencer:
```cpp
auto tree = apvts.copyState();
juce::MemoryBlock seq; sequencerState.writeToMemoryBlock (seq);
tree.setProperty ("sequencer_data", juce::Base64::toBase64 (seq.getData(), seq.getSize()), nullptr);
copyXmlToBinary (*tree.createXml(), destData);
```
`setStateInformation` reverses this **with defensive checks** — reject sizes ≤ 0 or
> 10 MB, validate the XML, guard the sequencer blob (< 5 MB) before reading. Preserve
these guards; a malformed host state must never crash or allocate unboundedly.
Patterns also export to portable `.seqfx` files via `MemoryBlock`.

### processBlock (the effect chain)
`PluginProcessor::processBlock` (RT-safe — see `rt-safety.md`):
1. `juce::ScopedNoDenormals`.
2. Apply input gain from `apvts.getRawParameterValue("inputGain")->load()`.
3. Make a dry copy (pre-allocated) for dry/wet and sidechain.
4. If grid params changed, `sequencerState.setGrid(bars, spb)`.
5. Sync: MIDI mode advances a step counter on note-ons; host mode feeds
   `setPlayheadPPQ(pos->getPpqPosition())` from `getPlayHead()`.
6. `sequencerEngine.processBlock(numSamples)` produces **smoothed** target values per
   lane.
7. Push smoothed values into each engine via lock-free setters
   (`filterEngine.setCutoff(sequencerEngine.getSmoothedValue(ParameterMatrix::FilterCutoff))`, …).
8. Run effects in `sequencerState.getEffectOrder()`, skipping bypassed and respecting
   solo.
9. Output gain + sample-level dry/wet blend.
Tail time is derived from reverb/delay mix+feedback, capped at 10 s.

### SequencerEngine smoothing
Holds `targetValues[]` (what the current step says) and `smoothedValues[]` (ramping
toward target). **Hold** = instant jump, **Glide** = ~100 ms exponential ramp. Updated
per block from plain float arrays — no allocation.

### Adding an effect engine
Mirror an existing `dsp/*Engine`: a class with `prepare(spec)`, cheap lock-free
`set*` setters, and `process(buffer)` that respects its Mix (parallel dry/wet blend,
short-circuit at mix ≤ 0 / ≥ 1 like `FilterEngine`). Then add its 3 lanes to
`ParameterMatrix`, wire it into the chain and ordering in `PluginProcessor`, and add a
`testDSPSafety` check.

## Packaging / distribution

- **Linux:** CPack DEB + TGZ. `.deb` installs system-wide; `.tar.gz` users extract to
  `~/.vst3/`.
- **Windows:** `installer/windows.iss(.in)` Inno Setup template (CMake `@ONLY`
  substitution fills version/paths) → VST3 to `C:\Program Files\Common
  Files\VST3\`, Standalone to `Program Files\SeqFX\`.
- **macOS:** `.dmg` with VST3 + `.component` (AU) + Standalone. **Not notarized** —
  users right-click → Open. Manual copy to `/Library/Audio/Plug-Ins/{VST3,Components}`.
- Ships ~50 factory presets; legal: `EULA.txt` (no redistribution / reverse
  engineering), `PRIVACY.txt` (no data collection, presets local only).
