---
name: juce-audio-dev
description: |-
  The user's only C++/JUCE audio codebases are DAO DAW (standalone DAW,
  ~/dev/dao-daw) and SeqFX (VST3/AU/Standalone effects plugin, ~/dev/seq-fx) — so
  "the DAW", "my plugin", "the plugin", or these names always mean these repos. Use
  this skill, which holds their build/test commands, layout, parameter map, and
  conventions, whenever the user:
  - works on JUCE/audio code — processBlock, DSP, AudioProcessor, APVTS, ValueTree,
    AudioBuffer, effects, step sequencer, transport, swing, tempo;
  - builds, runs, or adds tests for their plugin or DAW (CMake, Catch2, ctest, auval);
  - debugs audio crackle, dropouts, glitches, crashes, or real-time/audio-thread safety;
  - makes plugin/parameter state save and reload, or fixes VST3/AU packaging or validation.
  Always load it before editing, building, testing, or debugging either project. Skip
  it only for generic music/audio generation, mastering, BPM detection, choosing a DAW
  product, or unrelated C++ work.
---

# JUCE Audio Development — DAO DAW & SeqFX

Two related JUCE projects, one house style. This skill captures their shared
conventions, the exact build/test commands, and the real-time discipline that
makes or breaks audio software, so you can pick up work immediately without
re-deriving any of it.

## Orient first

Both repos are large and audio-thread bugs are subtle, so spend the first moment
locating before editing:

1. **Confirm which project** the task touches and read its reference file:
   - DAO DAW → `references/dao-daw.md` (standalone DAW app)
   - SeqFX → `references/seqfx.md` (effects plugin)
2. **Find the code** with `ctx_search`/Grep before reading whole files — these are
   80+ file codebases.
3. **Before any edit that runs on the audio thread**, read `references/rt-safety.md`.
   This is the single highest-value habit: a heap allocation, lock, or syscall in
   `processBlock`/`getNextAudioBlock` causes audible dropouts that won't show up in
   a quick test, only in a real session under load.

## Shared house style (both projects)

These hold across DAO DAW and SeqFX — match them so new code is indistinguishable
from existing code:

- **C++20, JUCE 8.0.12, CMake ≥ 3.22.** Don't introduce a newer standard or a
  different JUCE version.
- **`#pragma once`** in every header. No include guards.
- **Naming:** `PascalCase` classes/enums, `camelCase` members and functions, **no
  `m_` prefix** on members, `kConstantName` or `UPPER_CASE` for constants.
- **Minimal namespaces** — mostly global scope; a few small ones (`dao`,
  `DaoIcons`). Don't wrap everything in a namespace unless the surrounding file does.
- **Smart pointers:** `std::unique_ptr` with `std::make_unique`; raw pointers only
  for non-owning references. `JUCE_DECLARE_NON_COPYABLE_WITH_LEAK_DETECTOR` on
  classes that shouldn't copy.
- **Parameters:** `juce::AudioProcessorValueTreeState` (APVTS) is the source of
  truth. Read values on the audio thread via
  `apvts.getRawParameterValue("id")->load()`, never by walking the tree.
- **DSP:** prefer `juce::dsp` building blocks — `ProcessSpec`, `AudioBlock`,
  `ProcessContextReplacing`. Sample loops use raw pointer iteration over
  `buffer.getWritePointer(ch)`; SIMD is not used.
- **Doc comments:** every class gets a `/** ... */` block stating its
  responsibility and, for anything touched by the audio thread, its thread-safety
  contract. Keep this convention — it's how the codebase documents RT constraints.

## Real-time safety (the rule that matters most)

The audio callback runs on a high-priority thread that must never block. Both
codebases enforce this and so must you. The short version:

- **No allocation** in `processBlock`/`getNextAudioBlock` — no `new`, `malloc`,
  `std::vector` growth, `juce::String` building, or `setSize` that reallocates.
  Pre-allocate every buffer in `prepareToPlay`.
- **No locks that can block** — no `std::mutex`, no file/network I/O, no logging.
  Cross-thread state moves via `std::atomic`, lock-free FIFOs, or a
  `juce::SpinLock` used only for short non-blocking reads (the pattern in
  `TempoMap`/`AutomationCurve`).
- **`juce::ScopedNoDenormals`** at the top of `processBlock` (SeqFX does this).
- **Smooth parameter changes** — ramp toward targets (`SmoothedValue` or the
  sequencer's smoothing) instead of jumping, to avoid zipper noise.

Full checklist, idioms, and the project's own examples are in
`references/rt-safety.md`. Read it before writing audio-thread code, and sanity-check
diffs against it.

## Build & test quick reference

Full detail (modules, targets, artifact locations) is in each project's reference
file. The essentials:

### DAO DAW (`~/dev/dao-daw`)
```bash
# Debug build
cmake -B build -D CMAKE_BUILD_TYPE=Debug
cmake --build build --target DAO-DAW -j$(nproc)

# Release build
cmake -B build-release -D CMAKE_BUILD_TYPE=Release
cmake --build build-release --target DAO-DAW -j$(nproc)

# Tests (Catch2 v3 + ctest)
cmake --build build --target DAO-DAW-Tests -j$(nproc)
cd build && ctest --output-on-failure
./tests/DAO-DAW-Tests "[unit]"        # filter by tag
# Sanitizers (tests, ASan+UBSan — not TSan): -D DAO_DAW_ENABLE_SANITIZERS=ON
```
JUCE is a **git submodule** (`add_subdirectory(JUCE)`). External deps: Rubber Band,
CURL/ALSA on Linux.

### SeqFX (`~/dev/seq-fx`)
```bash
# Build (Release) — COPY_PLUGIN_AFTER_BUILD installs to ~/.vst3 automatically
cmake -B build -D CMAKE_BUILD_TYPE=Release
cmake --build build --config Release -j$(nproc)

# Tests (custom assertion harness)
./build/tests/SeqFX_Tests
```
JUCE is pulled via **FetchContent** (`GIT_TAG 8.0.12`). Builds VST3 + AU +
Standalone; artifacts land in `build/SeqFX_artefacts/Release/`.

## Working rhythm

1. **Locate** the relevant code (search, don't bulk-read).
2. **Read** the project reference file + `rt-safety.md` if touching audio.
3. **Edit** matching the house style above.
4. **Build** the right target; fix warnings (both use JUCE recommended warning flags).
5. **Test** — run the project's suite, and add a case when you change DSP or state
   logic. DAO DAW uses Catch2 (`TEST_CASE`/tagged); SeqFX adds a check inside its
   `tests/main.cpp` harness.
6. **Verify** audio-thread diffs against the RT-safety checklist before declaring done.

## Reference files

- `references/dao-daw.md` — DAO DAW layout, modules, build/test, plugin & engine
  architecture, persistence (.daodaw).
- `references/seqfx.md` — SeqFX layout, the effect chain & sequencer, APVTS
  parameter matrix, state save/load, packaging/installers.
- `references/rt-safety.md` — real-time audio safety checklist and JUCE idioms,
  with examples drawn from both codebases.
