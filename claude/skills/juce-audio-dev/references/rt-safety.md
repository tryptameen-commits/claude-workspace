# Real-Time Audio Safety (JUCE)

The audio callback (`AudioProcessor::processBlock`, `AudioAppComponent` /
`AudioSource::getNextAudioBlock`, `AudioProcessorPlayer`'s callback) runs on a
high-priority OS audio thread with a hard deadline: it must fill the buffer before
the soundcard needs it. Miss that deadline and the user hears a click, pop, or
dropout. Because the failure is timing-dependent, it often **passes a quick test and
only breaks in a loaded session** — which is exactly why discipline here matters
more than almost anywhere else in the codebase.

Both DAO DAW and SeqFX already follow these rules. Match them.

## The non-negotiables (audio thread)

**No heap allocation.** No `new`, `delete`, `malloc`, `free`. No `std::vector`
push_back/resize, no `juce::Array` growth, no `juce::String` construction or
concatenation, no `AudioBuffer::setSize` that reallocates. Allocate every buffer and
container once in `prepareToPlay(sampleRate, samplesPerBlock)` and reuse it.

**No blocking.** No `std::mutex`/`CriticalSection` you might contend on, no file or
network I/O, no `Logger`/`DBG`/`std::cout`, no `sleep`, no waiting on another thread.

**No unbounded or surprising work.** Keep per-block cost roughly constant; don't loop
over data structures whose size the UI can change underneath you without
coordination.

**Denormals off.** Put `juce::ScopedNoDenormals noDenormals;` at the top of
`processBlock`. Reverb/filter feedback paths decay into denormal floats that silently
cost huge CPU without it. (SeqFX's `PluginProcessor::processBlock` does this.)

## How state crosses the thread boundary

The UI/message thread changes parameters; the audio thread reads them. Move data
across without locking the audio thread:

- **`std::atomic<T>`** for scalar controls. This is the dominant pattern here —
  e.g. DAO DAW's `MixerChannel`:
  ```cpp
  std::atomic<float> volume { 1.0f };
  std::atomic<float> pan    { 0.0f };
  std::atomic<bool>  muted  { false };
  // audio thread: float v = volume.load();
  ```
- **APVTS raw parameter pointers** — cache `std::atomic<float>* p =
  apvts.getRawParameterValue("cutoff");` and `p->load()` on the audio thread. Never
  search the ValueTree by string on the audio thread.
- **`juce::SpinLock`** only for *short, non-blocking* reads where atomics aren't
  enough (a small shared structure). DAO DAW's `TempoMap` and `AutomationCurve` use
  `juce::SpinLock::ScopedLockType` guarding quick lookups so the audio thread never
  waits on a long critical section. Use a real lock-free FIFO
  (`juce::AbstractFifo`) for streaming larger data.
- **Smoothing** — never snap a parameter to a new value mid-buffer; ramp it.
  `juce::SmoothedValue<float>` or the SeqFX sequencer's `smoothedValues[]` ramp
  (~100 ms glide) prevent zipper noise. Hold = instant, Glide = exponential ramp is
  the SeqFX convention.

## prepareToPlay vs processBlock

`prepareToPlay(double sampleRate, int samplesPerBlock)` is your one chance to do
expensive work: size buffers, allocate delay lines, configure `juce::dsp` objects
via `ProcessSpec`, reset filter state. Treat it as "the audio thread is about to
start; get everything ready." Everything `processBlock` needs must already exist when
it's called. `releaseResources()` is where you can free.

```cpp
void prepareToPlay (double sr, int blockSize) override
{
    juce::dsp::ProcessSpec spec { sr, (juce::uint32) blockSize,
                                  (juce::uint32) getTotalNumOutputChannels() };
    filter.prepare (spec);
    delayBuffer.setSize (numChannels, maxDelaySamples); // allocate ONCE here
    smoothedGain.reset (sr, 0.05);                       // 50 ms ramp
}
```

## processBlock skeleton (the house pattern)

```cpp
void processBlock (juce::AudioBuffer<float>& buffer, juce::MidiBuffer& midi) override
{
    juce::ScopedNoDenormals noDenormals;

    // 1. Read parameters atomically (no tree walking, no allocation).
    const float gain = gainParam->load();

    // 2. Pull host transport if you need tempo/PPQ (RT-safe getter).
    if (auto* ph = getPlayHead())
        if (auto pos = ph->getPosition())
            if (auto ppq = pos->getPpqPosition())
                sequencer.setPlayheadPPQ (*ppq);

    // 3. Process into pre-allocated buffers; raw-pointer sample loops.
    for (int ch = 0; ch < buffer.getNumChannels(); ++ch)
    {
        auto* x = buffer.getWritePointer (ch);
        for (int n = 0; n < buffer.getNumSamples(); ++n)
            x[n] = process (x[n]);          // no allocation, no locks
    }
}
```

## Setters called from the audio thread must be lock-free

In SeqFX the audio thread calls `filterEngine.setCutoff(...)` every block from
smoothed values. Such setters must just copy a few floats into the engine's local
state — no reallocation, no locks. Keep engine `set*` methods trivial and cheap.

## Review checklist (run against any audio-thread diff)

- [ ] `ScopedNoDenormals` present in `processBlock`.
- [ ] No `new`/`malloc`/`std::vector` growth/`String` building/`setSize`-realloc in
      the callback or anything it calls.
- [ ] No `std::mutex`/`CriticalSection`, file/network I/O, logging, or sleeps on the
      audio path.
- [ ] Cross-thread reads use `std::atomic`, APVTS raw pointers, a bounded SpinLock
      read, or a lock-free FIFO — nothing that can block.
- [ ] Parameters that can jump are smoothed/ramped.
- [ ] Buffers and DSP objects are sized/allocated in `prepareToPlay`, not in the
      callback.
- [ ] Plugin reports a correct tail time so reverb/delay tails aren't cut off.

## Catching violations

- Build the tests with sanitizers (DAO DAW: configure with
  `-D DAO_DAW_ENABLE_SANITIZERS=ON`, which is a **tests-scoped** option that turns on
  **AddressSanitizer + UndefinedBehaviorSanitizer** — `-fsanitize=address,undefined`).
  ASan catches use-after-free/overflow; UBSan catches UB. Note this flag does **not**
  enable ThreadSanitizer — to chase data races between the UI and audio threads you'd
  add a separate TSan build (`-fsanitize=thread`), since ASan and TSan can't be
  combined.
- When chasing dropouts, suspect the audio thread first: search the callback's call
  graph for allocation, locking, or logging that crept in.
