# How RTL-SDR Mobile was built

This document explains, in technical detail, how this app's WFM stereo/RDS decoding,
automatic frequency scan, audio recording/export, GPL licensing, and the visual
spectrum tuner were designed and implemented — and how each piece was validated
against real hardware (an RTL2838U dongle on a Moto G35 5G, over Wi-Fi ADB).

A Portuguese translation of this document lives at
[`como-foi-construido.md`](como-foi-construido.md).

## 1. Starting point

Before this work, the app already had a working pipeline:

- Kotlin (`UsbBridge.kt`) requests USB permission and hands a raw file descriptor
  to native code via JNI (`nativeOpenWithFd`) — only the Android side can obtain
  a permitted USB file descriptor.
- Native C (`rtlsdr_shim.c`) wraps that fd with `libusb_wrap_sys_device()` and opens
  it with a patched `rtlsdr_open_fd()` (librtlsdr normally only opens devices by
  enumerating `/dev/bus/usb/*`, which requires root on Android).
- A USB reader thread streams raw 8-bit IQ into a lock-free ring buffer.
- A DSP thread decimates that IQ in two stages (channel bandwidth, then audio
  bandwidth), demodulates (WFM/NFM/AM, mono only), and writes 16-bit PCM into a
  second ring buffer consumed by an Oboe audio callback.
- Dart talks to the same native library two ways: JNI (Kotlin) only for the USB fd
  handoff, and direct FFI (`dart:ffi`, no ffigen — hand-written bindings) for
  everything else (tuning, streaming, stats, spectrum). Both loads resolve to the
  same `libnative_rtlsdr.so` instance in the same process, so state is shared.

This session added five things on top of that: a GPL license (required by
bundling GPLv2 `librtlsdr`), audio recording, automatic frequency scan, WFM
stereo decoding, and RDS decoding — plus later a UI pass (removed debug banner,
fixed a real waterfall rendering bug, replaced a first-draft "preset carousel"
with a CubicSDR/gqrx-style draggable spectrum tuner, and added a settings screen).

## 2. Licensing

The app vendors `librtlsdr` 2.1.0, licensed "GPLv2, or (at your option) any later
version" (confirmed directly from the header of `librtlsdr.c`). Linking GPL code
into a binary creates a combined work that must be distributed under the GPL —
this was already flagged as an open TODO in `docs/native_build.md` before this
session ("uso pessoal, sem distribuição — revisitar antes de distribuir de
qualquer forma"). A top-level `LICENSE` file (GPLv2 text, with the "or later"
clause in the app's own copyright notice — the same formula `librtlsdr.c` itself
uses) resolves that: the app is GPLv2-or-later, satisfying both GPLv2 and GPLv3
distribution. `libusb` (LGPL-2.1), KissFFT (BSD-3-Clause), and Oboe (Apache-2.0)
are all compatible without requiring a license change.

## 3. Audio recording / export

**Native side** (`dsp/wav_writer.c/h`): a small incremental WAV writer. It writes
a 44-byte RIFF/WAVE PCM16 header with the two size fields zeroed (the final file
size isn't known until the recording stops), then streams PCM as it arrives, and
on close seeks back to patch the RIFF chunk size and the `data` chunk size.

**Tap point**: rather than a second ring buffer and a dedicated writer thread, the
recorder taps the exact same `pcm_out` buffer the DSP thread already computes
right before `ring_buffer_write()`ing it into the audio ring — zero extra
buffering, and the file always contains exactly what went to the speaker.
`shim_start_recording(path)` opens the writer (reading the *current* channel
count — 1 or 2 — from shared state, so it matches whatever the demodulator is
producing at that moment); `shim_stop_recording()` and an internal
`stop_recording_if_active()` helper (also called from `shim_stop_streaming()`) close
it safely — stopping the stream while recording auto-finalizes the WAV instead of
leaving a zero-size-field file behind.

**Concurrency**: a `pthread_mutex_t record_lock` guards the writer pointer itself
(not just the "are we recording" flag), because `shim_stop_recording()` can run on
the Dart platform thread at the same instant the DSP thread is mid-write — without
the lock there's a use-after-free window between "recording is still flagged
active" and the actual `wav_writer_write()` call.

**Dart side**: `path_provider`'s app-specific external storage directory (no
runtime storage permission needed on modern Android) plus `share_plus` for
export via the Android share sheet — deliberately avoiding `MediaStore`/SAF
complexity for a first version.

**Validated on hardware**: recorded 10s of NFM audio → 647KB file, matching the
expected `32000 Hz × 2 bytes × 10s ≈ 625KB` plus header almost exactly. Recorded
again in WFM stereo (double the byte rate) — stopped and restarted cleanly, correct
file each time, zero ring-buffer overflow while writing to disk mid-stream.

## 4. Automatic frequency scan

Implemented entirely in Dart (`lib/radio/scan_controller.dart`) — no new native
code, because the shim already exposed everything needed: `shim_set_frequency_hz`
and `shim_get_stats().rf_level_dbfs`.

The loop is a `Future`-based async walk (not `Timer.periodic`, since each step
needs a variable settle delay), not hardcoded to the commercial FM band — start,
end, step, and threshold are all caller-supplied, so the same controller can sweep
a narrowband PMR/ham range in NFM just as well as FM broadcast in WFM. Per step:
tune, wait ~50ms for the tuner PLL/AGC to settle, sample RF level twice 20ms apart
(take the max, cheap noise reduction), compare against the threshold. A dedicated
`RadioController.sampleRfLevelDbfsNow()` method was added because the existing
stats poll only refreshes every 500ms — far too slow for a ~70ms/step scan; it
reads fresh stats immediately without disturbing the `bytesPerSecond` rate
calculation the periodic poller depends on.

Cancelling mid-scan restores the original frequency; letting it run to completion
leaves the radio tuned to the last frequency swept (both are deliberate — a
completed scan's "last position" is a reasonable place to land, a cancelled one
should not strand you somewhere arbitrary). Found stations can be tuned to with a
tap or saved as a preset, reusing the existing `PresetsController` — no new
storage.

**Validated on hardware**: swept 87.5–108.0 MHz, found 35 real stations, watched
progress update live; cancelling mid-sweep correctly restored the pre-scan
frequency.

## 5. WFM stereo decoding

This is where it gets interesting. Broadcast FM stereo multiplexes L+R (0–15kHz),
a 19kHz pilot tone, and L−R as a double-sideband suppressed-carrier signal
centered on 38kHz (23–53kHz) — plus, optionally, RDS at 57kHz (covered in §6).

### 5.1 Pipeline restructuring

The existing `fm_demod_process()` already had de-emphasis baked in. That's wrong
for stereo: de-emphasis is a lowpass shelf that would attack the 19kHz pilot and
38kHz sidebands before they can be demultiplexed. Fix: for WFM, `fm_demod_init()`
is now called with `deemphasis_tau_us=0` (disabled) — same as NFM already did —
so the discriminator hands back the raw MPX signal untouched. De-emphasis moves
to a new standalone module (`dsp/deemphasis.c/h`, the exact math that used to live
inside `demod_fm.c`) applied *after* the stereo split and *after* decimation, once
per channel, at 32kHz instead of once at 256kHz (cheaper, and mathematically
equivalent since it's an LTI filter far below the decimation cutoff).

### 5.2 Pilot PLL (`dsp/fm_stereo_pilot.c/h`)

A second-order PI-controlled PLL locks onto the 19kHz pilot, running directly on
the raw MPX with no dedicated bandpass filter — the loop's own narrow bandwidth
*is* the tracking filter, which is what established open-source FM stereo
decoders (e.g. SoftFM) do; a separate BPF would only add group-delay bookkeeping
for no real benefit. Per sample:

```
error  = mpx[n] * sin(theta)
freq  += beta  * error
theta += freq + alpha * error
```

`alpha`/`beta` come from the standard discrete-PLL loop-bandwidth/damping
formulas (`loop_bw ≈ 8Hz`, `zeta ≈ 0.707` — starting estimates, not validated
against real transmitter frequency offsets).

The 2nd and 3rd harmonics needed for the stereo demux (38kHz) and RDS
downconversion (57kHz) come "for free" from the NCO's own phase via angle-sum
identities — no second or third oscillator:

```
sin(2θ) = 2 sinθ cosθ              cos(2θ) = cos²θ − sin²θ
sin(3θ) = sin(2θ)cosθ + cos(2θ)sinθ   cos(3θ) = cos(2θ)cosθ − sin(2θ)sinθ
```

Lock detection tracks the pilot's amplitude via a low-passed I/Q correlation
against the PLL's own NCO, with hysteresis and a debounce counter (same pattern
already used for squelch) to avoid flapping right at the threshold.

### 5.3 L/R demultiplex

Per sample, once `cos(2θ)` is available:

```
lr_sum  = mpx[n]                      // L+R
lr_diff = 2 · mpx[n] · cos(2θ)[n]     // coherent DSB-SC demod of L−R
L = lr_sum·(1 − 0.5·blend) + 0.5·blend·lr_diff
R = lr_sum·(1 − 0.5·blend) − 0.5·blend·lr_diff
```

`blend` is a one-pole smoother (same shape as the de-emphasis filter, ~150ms time
constant) ramping toward 1.0 when the pilot is locked *and* the user hasn't
forced mono, or toward 0.0 otherwise. At `blend = 0`, `L = R = lr_sum` — bit-for-bit
the old mono behavior, no 6dB loss — so losing lock never causes a level drop,
just a smooth fade to mono instead of a hard cut.

L and R are decimated together using the *existing* `fir_decimator` in
`complex_mode=1` — a deliberate reuse: that mode was written to filter I and Q as
two independent, synchronized real convolutions, which is exactly the right shape
for "two real channels sharing one decimation clock," even though there's no
actual complex rotation involved. No new decimator code was needed.

### 5.4 Stereo audio path

Oboe now opens in stereo (2 channels) whenever the mode is WFM — even if the
pilot isn't locked or the user has forced mono, so `blend=0` just means both
channels carry identical audio, rather than tearing down and reopening the Oboe
stream on every lock/unlock transition. `audio_sink_oboe.cpp`'s underrun zero-fill
had to change from `bytes = frames * sizeof(int16_t)` to
`bytes = frames * channel_count * sizeof(int16_t)` — an easy one-line bug to
introduce when generalizing a mono-only audio sink to stereo, called out
explicitly during implementation because it silently corrupts only half the
underrun-fill buffer if missed. `PCM_RING_CAPACITY` was doubled (128KiB → 256KiB)
to keep the same ~2s margin for the worst case (stereo).

### 5.5 Validated on hardware

The pilot PLL locked repeatedly on real broadcast signals (confirmed via the
"Estéreo (piloto travado)" indicator flipping green live), across multiple
frequencies, immediately after tuning. This is the single highest-risk untested
piece of the whole session, and it worked correctly on the first real-hardware
attempt.

## 6. RDS decoding

RDS (IEC 62106 / RBDS) rides a 57kHz subcarrier — the pilot's 3rd harmonic — at
1187.5 bits/s, biphase (Manchester-style) coded, further differentially encoded.
This is the highest-risk, most intricate piece of the session, and it's built
from scratch rather than ported from an existing decoder — with one important
exception: the **CRC/offset-word constants are transcribed and verified, byte for
byte, against [redsea](https://github.com/windytan/redsea)** (an actively
maintained, real-world open-source RDS decoder, MIT-licensed), rather than
trusted from memory. Getting those constants wrong doesn't crash anything — it
fails silently, producing a decoder that plausibly looks correct but never
actually decodes real data, which is exactly the kind of bug that's expensive to
catch without a way to independently verify the numbers.

### 6.1 Front end

`audio_pre` (the raw MPX, same buffer the stereo pilot reads) is mixed down by
`cos(3θ)`/`sin(3θ)` (the pilot PLL's 3rd harmonic, so RDS is phase-coherent with
the same reference stereo uses) and decimated by a dedicated complex
`fir_decimator` instance — 256kHz → 16kHz, decimation factor 16, 129 taps (more
than the 63 used elsewhere, because the ~2.4kHz occupied bandwidth needs a much
narrower *relative* cutoff, which needs more taps for equivalent stopband
rejection) and a tighter cutoff (~3.2kHz vs. the generic `0.9/decim` formula used
elsewhere) to reject stereo/pilot leakage.

### 6.2 Symbol timing recovery — Gardner, at chip rate

A first design pass assumed a single Gardner loop running at the 1187.5 bit rate.
That's wrong: biphase-coded data is DC-null over one symbol period *by
construction* — the information is entirely in which half of the symbol is
positive vs. negative, not in a net amplitude — so a symbol-rate timing loop
would see essentially nothing to lock onto. Real decoders (including redsea)
recover timing at **2375Hz, twice the bit rate** — one Gardner-recovered "chip"
per half-symbol — then combine chip pairs into bits afterward. This project's
Gardner implementation uses linear interpolation between the two nearest 16kHz
baseband samples (~6.7 samples/chip) for the "on-time" sample, and approximates
the "mid" sample Gardner's error term needs as the midpoint between the current
and previous decided chip (a simplification relative to an independent
interpolation at exactly −sps/2 — reasonable near lock, a wider error term when
not).

### 6.3 Costas loop, biphase combine, differential decode

A per-chip BPSK Costas loop (`error = sign(I) · Q`) corrects residual phase
rotation between the stereo-pilot path and the RDS path's own decimation chain
(different filters, different group delay). Consecutive chip pairs combine into
one raw bit via a soft comparison (`first_chip_I − second_chip_I > 0`), then
`data_bit = raw_bit XOR previous_raw_bit` recovers the actual transmitted bit —
which, as a side effect, also absorbs the Costas loop's inherent ±180° phase
ambiguity for free (inverting every raw bit doesn't change a XOR of consecutive
values). A `biphase_slot` parity toggle, triggered if block sync doesn't lock
within ~44 seconds, hedges against getting the "which chip of the pair is first"
alignment backwards.

### 6.4 Block synchronization

RDS blocks are 26 bits (16 data + 10 check bits, generator polynomial
`x^10+x^8+x^7+x^5+x^4+x^3+1`), where the check bits are the data's CRC XORed with
one of five 10-bit offset words identifying the block's position (A, B, C, C′, D).
The syndrome-calculation function and its 26-row parity-check matrix, plus the
five syndrome→offset lookup values, were fetched from redsea's `block_sync.cc`/
`block_sync.hh` and hand-verified bit-for-bit (each of the 26 matrix rows and 5
syndrome constants converted from binary to hex and checked against the source)
before being ported — see the comments in `dsp/rds_decoder.c` for the exact
provenance.

Acquisition anchors on offset A specifically: scan every bit position for a
syndrome match against A, then require B to appear exactly 26 bits later before
declaring lock (a simpler, slightly slower-to-acquire alternative to searching all
five offsets in parallel). Once locked, block N's slot only needs to be checked
against *its* expected offset (C or C′ are both accepted for slot 2, since which
one is used encodes the group's A/B version — redundantly with a bit in block B
itself); losing sync 3–6 blocks in a row drops back to acquisition.

### 6.5 Group parsing

Block A is the PI code directly. Block B carries group type (bits 15–12), version
A/B (bit 11), TP (bit 10), PTY (bits 9–5), and group-specific bits. Group 0
(A/B) carries PS (the 8-character station name, 2 characters per group, address
in bits 1–0 of block B) and TA (bit 4). Group 2A carries RadioText 4 characters
at a time (2 from block C, 2 from block D); Group 2B carries 2 at a time from
block D only. The exact bit offsets were cross-checked against Wikipedia's RDS
technical summary and redsea's `station.cc` rather than recalled from memory,
per the same "verify, don't trust memory" principle applied to the CRC constants.

### 6.6 Exposure to Dart

A `shim_rds_info_t` struct (PI, PTY, TP, TA, PS, RadioText, a generation counter
that only increments when the decoded text actually changes, a valid-group
counter, and a sync-locked flag) is protected by its own mutex and copied out on
poll — the same pattern already used for the spectrum snapshot. Dart mirrors it
with a matching `ffi.Struct` (`ShimRdsInfo`) and a dedicated `RdsController`
polling every 500ms, sharing its start/stop lifecycle with the existing
`SpectrumPoller` pattern (a plain field nested in `RadioController`, not a
top-level `Provider`).

### 6.7 Validated on hardware

RDS achieved genuine lock on a real station and decoded **PS "GRFM", PI 65399,
PTY 14, TA active** — correctly. That's the group-parsing bit offsets, the CRC
syndrome table, and the whole Gardner→Costas→biphase→differential chain all
working together correctly against a real over-the-air signal, on the first
attempt. Lock was intermittent (dropped and re-acquired on its own over the next
few minutes) — expected, given the loop gains are unvalidated starting estimates
by design (see §8), and honest confirmation that the *algorithm* is correct even
though the *tuning* isn't finished.

## 7. UI: spectrum tuner, waterfall fix, settings

A first draft added a horizontally-swipeable carousel of saved presets. That
wasn't the right shape — a follow-up request asked for something closer to
CubicSDR/gqrx: a live spectrum display with a fixed tuning cursor at the center
that you drag through, not a list of stations.

**`lib/widgets/spectrum_tuner.dart`**: renders `SpectrumPoller`'s 256 dB-magnitude
bins as a filled line chart spanning `frequencyHz ± sampleRateHz/2` (the bins are
computed from the whole captured band, not a demodulated channel), with a fixed
vertical line at the center. A `GestureDetector` combines `onTapUp` (tune
directly to the tapped point — absolute) with `onHorizontalDragUpdate` (tune by
`-delta.dx/width * spanHz` — relative, like scrolling a list: dragging right
pulls lower frequencies toward the center). `RadioController.sampleRateHz` was
added (read from `shim_get_sample_rate_hz()` once streaming starts) since nothing
previously tracked it on the Dart side.

**Waterfall freeze bug**: `WaterfallPainter.shouldRepaint` compared
`oldDelegate.rows` against `rows` with `identical()` — but `WaterfallView` mutates
its `_rows` list *in place* (`insert`/`removeRange`), never reassigning it, so
that comparison was always `true` for the same underlying object, meaning
`shouldRepaint` always returned `false`. The waterfall was, in effect, frozen
after its first frame. Fixed by always returning `true` — safe because the
painter is only ever reconstructed when `WaterfallView`'s own listener calls
`setState()` in response to a real new frame from the poller, so there's no
redundant-repaint cost to worry about. Confirmed visually on hardware: the
waterfall now clearly scrolls/updates with each retune.

**`lib/screens/settings_screen.dart`**: a recordings manager (list, share, delete
the WAV files the recorder produces) and an About section (app/version, license
summary, third-party component licenses), reachable from a settings icon in the
app bar. `debugShowCheckedModeBanner: false` removes the corner debug ribbon.

## 8. What's still unvalidated

Everything in §5 and §6 works — proven against real hardware, not just compiled —
but several numeric constants are first-pass estimates that weren't, and by the
nature of this development environment (no physical dongle available to the
agent that wrote them) couldn't be, tuned against a real RF environment before
today's one test session:

- Pilot PLL loop bandwidth/damping, and RDS Gardner/Costas loop gains — starting
  values from standard formulas, not swept against real signal.
- No PPM/frequency-offset correction anywhere in the pipeline — cheap RTL-SDR
  crystals can drift by tens to hundreds of Hz, which could exceed the pilot
  PLL's capture range on some individual dongles.
- Stereo lock/unlock amplitude thresholds and debounce timing.
- RDS block-sync debounce counts (2 to acquire, 3–6 to lose lock).
- No RDS burst error correction (an explicit scope cut for the first pass).
- No RDS character-set table — PS/RadioText are stored as raw bytes, correct for
  plain ASCII (the common case), not the RDS-specific extended character table.

None of these are correctness bugs in the sense of "wrong code" — they're
tuning parameters that need a wider sample of real stations/dongles than one
session with one dongle in one location can provide.
