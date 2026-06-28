# HreflexStimArduino

Arduino firmware and companion MATLAB tools for H-reflex stimulation in the
SpinalAdapt study. The Arduino controls a pair of Digitimer DS8R constant-
current stimulators to deliver tibial nerve stimuli at a precise phase of the
gait cycle during split-belt treadmill walking.

---

## Sketch Directory

| Path | Purpose | Status |
|---|---|---|
| `triggerStimWithGaitStateMachine_SpeedIndependent/` | Autonomous gait-event detection with per-stride MATLAB gating | **Current production** |
| `Dual_Stim_Matlab/` | MATLAB sends explicit per-stride trigger commands; no on-board gait detection | Alternative (MATLAB-driven) |
| `deprecated/Working_triggerStimWithGaitStateMachine/` | Earlier state-machine iteration (superseded Dec 2025) | Deprecated |
| `deprecated/Dual_Stims*.ino` | Early bilateral-stimulation sketches | Deprecated |

The current production sketch is
`triggerStimWithGaitStateMachine_SpeedIndependent.ino`. Use `Dual_Stim_Matlab`
when you want MATLAB to control the stimulation timing directly rather than
delegating gait-event detection to the Arduino.

Each sketch has exactly one matching MATLAB controller — using the wrong
pairing means either the Arduino's state machine never starts (no `0`/`3`
handshake) or stims fire at the wrong point in stance (gate timed for the
wrong firmware):

| Sketch | MATLAB controller |
|---|---|
| `triggerStimWithGaitStateMachine_SpeedIndependent` | `controllers/NirsHreflexArduinoOpenLoopWithAudio.m` |
| `Dual_Stim_Matlab` | `controllers/Deprecated/NirsHreflexOpenLoopWithAudio.m` (fallback only) |

---

## How the System Works

### Gait-State-Machine Mode (current production)

1. MATLAB sends command `0` over serial to reset and start the gait-event state
   machine.
2. The Arduino monitors force-plate Z-axis voltage on analog inputs A0 (left)
   and A1 (right). It detects heel strikes and toe-offs by threshold-crossing on
   the filtered force signal.
3. After each toe-off the Arduino updates an exponentially smoothed estimate of
   single-stance duration (α = 0.7) for that leg. It then schedules the stimulus
   at 50% of the estimated single-stance phase.
4. Each stride, MATLAB sends command `1` (stimulate left) or `2` (stimulate
   right) to gate whether stimulation is delivered on that stride. If no command
   is sent, the Arduino does not stimulate even if the timing condition is met.
   **The Arduino owns the precise 50%-single-stance timing**, so MATLAB should
   send this gate byte at *single-stance onset* (early in the stride), not at
   mid-stance: the latch (`shouldStimL/R`) is held until the Arduino reaches
   its 50% trigger and fires. Sending the gate late (e.g., waiting until
   mid-stance in MATLAB) leaves too little margin before the trigger and causes
   missed or mistimed stims under MATLAB control-loop jitter.
5. MATLAB sends command `3` to stop the state machine at trial end.

### MATLAB-Driven Mode (`Dual_Stim_Matlab`)

MATLAB sends `1` (left) or `2` (right) at any time; the Arduino immediately
delivers a 20 ms pulse on the corresponding output pin. There is no gait-event
detection — MATLAB is fully responsible for timing.

### Serial Commands (both sketches)

| Command byte | Effect |
|---|---|
| `0` | Start gait-event state machine and reset counters (SpeedIndependent only) |
| `1` | Flag left leg for stimulation on current stride |
| `2` | Flag right leg for stimulation on current stride |
| `3` | Stop gait-event state machine (SpeedIndependent only) |

Baud rate: **115200**. Both `LogForcesArduinoSerial.m` and the SpinalAdapt
controllers use this rate; no changes are needed on the MATLAB side when
switching between sketches.

### Device Stim Echo (outbound, SpeedIndependent only)

The inbound `0/1/2/3` command set above is **fixed**. Separately, the
SpeedIndependent firmware reports each delivered pulse back to MATLAB on an
**additive outbound channel** as a newline-terminated CSV record:

```
S,<leg>,<step>,<stimMs>,<toRefMs>,<estSS>
```

| Field | Meaning |
|---|---|
| `S` | Fixed tag so MATLAB can distinguish echoes from other serial output |
| `leg` | `L` or `R` — the stimulated leg |
| `step` | Arduino-side ipsilateral step counter at the pulse |
| `stimMs` | `millis()` time the pulse fired |
| `toRefMs` | `millis()` of the contralateral toe-off used as the 50% reference |
| `estSS` | Arduino single-stance estimate at the pulse (ms) |

`NirsHreflexArduinoOpenLoopWithAudio.m` drains these **non-blocking** off its
control loop (reads only bytes already buffered; a serial hiccup is caught and
ignored — a dropped echo is a non-event) and appends one row per pulse to
`datlog.stim.deviceEcho.data`. From `stimMs − toRefMs` (elapsed time into single
stance) over the MATLAB-measured single-stance duration, it computes the actual
**%-single-stance** per stim and prints it live, flagging anything outside
50 ± 5%. This echo requires a **matched firmware re-upload**: old firmware
simply sends nothing and the MATLAB side is a clean no-op.

> **Caveat:** the live %SS mixes an Arduino-detected toe-off (numerator) with a
> MATLAB-detected single-stance duration (denominator), so it carries a small
> cross-detector error and is a **gross-error online check**, not the
> acceptance number. The Vicon analog sync pulse is the gold standard — see
> "Validating stim timing" below.

---

## Validating Stim Timing (Acceptance Test)

Run this once back in the lab after any firmware re-upload, before participants.
The **Vicon analog sync pulses** (pins 11/12 → Vicon) mark the exact stim
instant on the *same clock* as the force-plate gait events, so they are the
ground truth for the ±5% acceptance criterion.

1. **Re-upload firmware** (the echo is a firmware change): follow "Arduino
   Upload Workflow" above for
   `triggerStimWithGaitStateMachine_SpeedIndependent`.
2. **Bench-check the echo** without walking: open the Arduino IDE Serial Monitor
   at 115200, send `0`, then `2` (or `1`), and confirm a `S,R,...`/`S,L,...`
   line appears per gated stride while you hand-press the force plates. Close
   the Serial Monitor before running MATLAB (only one process can hold the
   port).
3. **MATLAB dry run (no participant):** run a short dummy profile with
   `hreflex_present = true` and the Arduino reading bench force input. Confirm
   the console prints `Stim L/R step N: ...% SS` lines, that
   `datlog.stim.deviceEcho.data` is populated, and that
   `datlog.diagnostics.loopSegMs` per-iteration timing is unchanged versus a run
   with the echo firmware absent (the drain must add no measurable hot-path
   latency).
4. **Representative trial:** collect ≥1 trial with a participant (or a walking
   stand-in). Offline, for each stim compute
   `100 × (stimVsync − RTO) / (RHS − RTO)` for left (and the LHS/LTO analog for
   right) using **Vicon** force-plate events and the analog sync-pulse channel,
   all on the Vicon clock.
5. **Acceptance:** the Vicon-derived %-single-stance should cluster at
   **50% ± 5%**. The MATLAB-echoed `pctSS` column should track it within the
   cross-detector error; large divergence between the two points to a gait-event
   detection mismatch (threshold/debounce), not a stimulator fault.

---

## Hardware Pin Map

| Arduino Pin | Signal | Direction |
|---|---|---|
| A0 | Left force-plate Fz (analog voltage from force plate DAQ) | Input |
| A1 | Right force-plate Fz | Input |
| 9 | Left Digitimer DS8R trigger | Output |
| 12 | Left Vicon sync marker | Output |
| 8 | Right Digitimer DS8R trigger | Output |
| 11 | Right Vicon sync marker | Output |

> **TODO:** Document the physical wiring between the force-plate DAQ analog
> outputs and the Arduino analog inputs (cable type, connector, voltage range,
> any required voltage divider), and the wiring from Arduino digital outputs to
> Digitimer DS8R trigger inputs.

---

## Arduino Upload Workflow

The repository stores the Arduino sketches for version control, but the
Arduino IDE requires the project to live locally on the experimental PC.
Follow these steps each time the firmware needs to be updated.

**Prerequisites:** Arduino IDE installed on the experimental PC.

**Step 1 — Locate the sketch folder in the repository.**

```
HreflexStimArduino\triggerStimWithGaitStateMachine_SpeedIndependent\
```

**Step 2 — Copy the entire folder to the Arduino sketchbook.**

The Arduino IDE requires the folder name to match the `.ino` filename exactly.
This is already the case for all sketches in this repository. Copy the folder
to:

```
C:\Users\<username>\Documents\Arduino\
```

After copying, the path should be:

```
C:\Users\<username>\Documents\Arduino\triggerStimWithGaitStateMachine_SpeedIndependent\
    triggerStimWithGaitStateMachine_SpeedIndependent.ino
```

Do not copy just the `.ino` file — copy the entire folder.

**Step 3 — Open the sketch in the Arduino IDE.**

File → Open → navigate to the copied folder and select the `.ino` file.

**Step 4 — Select the correct board.**

Tools → Board → Arduino AVR Boards → **Arduino Uno**

**Step 5 — Select the correct COM port.**

Tools → Port → select the COM port assigned to the Arduino. If you are unsure
which port it is, open Windows Device Manager (right-click Start → Device
Manager → Ports (COM & LPT)) and look for "Arduino Uno (COMx)".

**Step 6 — Upload.**

Click the Upload button (right-pointing arrow in the toolbar). Wait for the
status bar to show "Done uploading." before closing the IDE.

**Step 7 — Keep the USB cable connected.**

The same USB cable used for uploading is also the serial communication link
between MATLAB and the Arduino during an experiment. Leave it connected to the
experimental PC after uploading.

---

## Pre-Experiment Checklist

- [ ] Arduino firmware uploaded (verify with step-by-step above)
- [ ] USB cable connected; COM port confirmed in Device Manager
- [ ] Force-plate analog outputs connected to Arduino A0 (left) and A1 (right)
- [ ] Digitimer DS8R trigger cables connected to Arduino pins 8 (right) and 9 (left)
- [ ] Vicon sync cables connected to Arduino pins 11 (right) and 12 (left)
- [ ] Run `LogForcesArduinoSerial.m` to verify force signal quality and gait
      event detection before running a participant (see Troubleshooting below)
- [ ] Confirm MATLAB serial port setting matches the Arduino COM port

---

## Troubleshooting with `LogForcesArduinoSerial.m`

Run this companion MATLAB script before an experiment to verify that the Arduino
is correctly reading the force-plate signals.

1. Set the `comPort` variable at the top of the script to match the Arduino COM
   port (e.g., `'COM4'`).
2. Run the script. A live two-panel plot shows left and right Fz traces in a
   rolling 2-second window.
3. Walk on the treadmill (or apply hand pressure to the force plates) and confirm
   that the traces respond appropriately.
4. The script saves a timestamped CSV and plot to the current working directory
   on completion. Review these offline to assess signal noise, threshold
   crossings, and detected event timing.

If force traces look flat or noisy:
- Check that the force-plate analog output cables are securely seated in the
  Arduino analog input headers.
- Confirm that the Bertec Sync software is running and the force plates are
  zeroed.
- If the signal range is very small, the voltage may need to be amplified before
  reaching the Arduino (10-bit ADC; stances should reach ~30 bits above
  baseline).

---

## Future Improvements

The following enhancements are recommended for future development. None are
implemented yet; this section is for planning purposes.

1. **Configurable thresholds via serial** — Force thresholds (`threshFzUp`,
   `threshFzDown`) and the exponential smoothing factor (α) are currently
   hard-coded constants. Exposing them as serial-configurable parameters would
   allow MATLAB to tune them per participant without re-uploading firmware.

2. **~~Two-way serial protocol with event echo~~ (implemented)** — On each
   delivered pulse the SpeedIndependent firmware now echoes a tagged record
   back to MATLAB (`S,<leg>,<step>,<stimMs>,<toRefMs>,<estSS>`); see "Device
   stim echo" below. MATLAB drains it non-blocking and logs the actual
   %-single-stance to `datlog.stim.deviceEcho`. Remaining future work: also use
   the echoed step/timestamp to align H-reflex events during post-processing.

3. **Mid-experiment gating update** — Currently, MATLAB must send per-stride
   `1`/`2` commands proactively. A mechanism for MATLAB to send a burst of
   future-stride flags in advance (e.g., for the next 10 strides) would reduce
   the risk of missed commands due to MATLAB loop jitter.

4. **Startup handshake** — Add a request/acknowledge exchange at connection time
   so MATLAB can confirm Arduino firmware version and readiness before starting
   the trial, reducing silent miscommunication from stale serial buffers.

5. **LogForcesArduinoSerial.m improvements** — Add a subject ID prompt for
   better file naming; add auto-detection of active Arduino COM port (by
   scanning available ports for the baud-rate handshake); add overlay of
   detected gait-event markers on the force trace plot.

6. **Inline documentation in the sketch** — The timing algorithm (how single-
   stance duration is estimated via exponential smoothing and how 50% is used
   as the delay target) is not explained in comments. Adding block comments at
   the key calculation steps would make the sketch auditable without needing to
   refer back to design discussions.
