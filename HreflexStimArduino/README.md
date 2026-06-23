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

2. **Two-way serial protocol with event echo** — The Arduino currently receives
   commands from MATLAB but does not report actual stimulation timestamps back.
   Adding an echo (stride index + actual stim timestamp on each delivery) would
   let MATLAB verify timing accuracy and align H-reflex events in post-
   processing without relying solely on the Vicon analog sync trace.

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
