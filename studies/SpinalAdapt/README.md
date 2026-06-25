# SpinalAdapt

Measures spinal-level H-reflex adaptation to split-belt treadmill
walking alongside prefrontal cortex oxygenation (fNIRS). H-reflex
responses are elicited by Arduino-triggered Digitimer DS8R
stimulators at a fixed phase of the gait cycle.

## Status

**Rebooting.** Data collection is planned to resume approximately
July 2026. Protocol software updates may be required to ensure
precise H-reflex stimulation timing before collection resumes.

## Experimenters

| Role | Name |
|---|---|
| Lead | Chase Rock (post-doctoral fellow) |
| Key | Shuqi Liu |
| Key | Nate Brantly |

## Subject IDs

| Format | Population |
|---|---|
| `SABH##` | Healthy controls |
| `SAS##V##` | Participants with stroke (two visits) |

## Protocol Notes

- Speed ratio: slow = 0.7 × fast belt speed (abrupt split, no ramp).
  This ratio was changed from 0.5 after participant SABH16 (July 2024).
- Overground baseline trials: `HreflexOGWithAudio` (GUI menu slot 16).
  The speed feedback range must be adjusted manually between
  participants based on comfortable overground walking speed.
- Calibration trials: `NirsHreflexArduinoOpenLoopWithAudio` (slot 14).
- H-reflex stimulation timing: the Arduino owns the precise
  50%-single-stance pulse timing; `NirsHreflexArduinoOpenLoopWithAudio`
  sends command `0` once before the main loop to start the Arduino's
  state machine, a per-stride gate byte (`1`/`2`) at single-stance onset,
  and command `3` in the closing routine to stop the state machine.
  Earlier code waited until mid-stance to send the gate, which left too
  little margin before the Arduino's 50% trigger and caused missed or
  mistimed stims under control-loop jitter — now fixed (MATLAB-only).
  Display work was also moved off the control loop's hot path (`drawnow
  limitrate`, reusable `animatedline` markers, throttled textbox
  updates). The deprecated `NirsHreflexOpenLoopWithAudio` (now in
  `controllers/Deprecated/`) pairs with the alternative
  `Dual_Stim_Matlab.ino` firmware (fully MATLAB-timed, no on-board gait
  detection) and is kept only as a fallback for that mode.

## Validation Before Resuming Collection

The controller logs per-iteration loop timing and gate lead time to the
additive `datlog.diagnostics` field. Before participant collection,
confirm:

- **0 missed stims** — intended stims (count of `1`s in the `stimL` /
  `stimR` profile columns) equal delivered pulses (Vicon-recorded
  Arduino trigger count).
- **Tight stim timing** — stimulus fires near 50% of single stance;
  check the distribution from labTools `computeHreflexParameters`
  (`stimTimeFromSingleStanceSlow/Fast`).
- **Loop timing** — review `datlog.diagnostics.loopSegMs` (median, p95,
  max) and `gateLeadMs*` (small, stable lead from single-stance onset).
- **Bench check** — run `HreflexStimArduino/LogForcesArduinoSerial.m`
  with a short dummy profile at low treadmill speed and confirm every
  intended stride fires once near mid-single-stance.

## Key Scripts

| Script | Purpose |
|---|---|
| `RunProtocol_SpinalAdaptBouts.m` | Main protocol runner |
| `generateProfiles_SpinalAdaptBouts.m` | Speed profile generator |
| `runWalkingCalibrations.m` | Pre-experiment stimulus calibration |
| `transferData_SpinalAdaptBouts.m` | Data transfer and archival |

## Hardware

H-reflex stimulation requires an Arduino Uno running the firmware in
`HreflexStimArduino/`. See
[HreflexStimArduino/README.md](../../HreflexStimArduino/README.md)
for the upload procedure, wiring diagram, and pre-experiment
checklist.

## See Also

[EXPERIMENT_SETUP.md](../../EXPERIMENT_SETUP.md).
