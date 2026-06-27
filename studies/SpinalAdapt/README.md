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

## Study History

| Archive folder | Description |
|---|---|
| `History-PilotStudy1/` | Original pilot — simpler tied/split structure; no fNIRS bout design. Scripts: `SpinalAdaptProtocol.m`, `GenerateProfileSpinalStudy.m`. |
| `History-PilotStudy2/` | Bout-based protocol — participants SABH01 through at least SABH16+ (July 2023–2025). Speed ratio changed from 0.5 to 0.7 after SABH16 (July 2024); ramp-to-split option added then later removed. Scripts reformatted to CLAUDE.md style (June 2026). |

The active files in this folder are templates for the next protocol version.
New protocol conditions and ramp logic have not yet been designed.

## Key Scripts

| Script | Status | Purpose |
|---|---|---|
| `RunProtocol_SpinalAdaptBouts.m` | Template | Main protocol runner |
| `generateProfiles_SpinalAdaptBouts.m` | Template | Speed and stim profile generator |
| `runWalkingCalibrations.m` | Active | H-reflex walking calibration helper |
| `transferData_SpinalAdaptBouts.m` | Active | Data transfer and archival |

## H-Reflex Calibration Processing

After each walking dynamic H-reflex calibration trial, a Vicon Nexus
2.12 processing pipeline automatically runs
`labTools/fun/misc/generateHreflexRecruitmentCurves.m`. This script
is **not** called by ExperimentalGUI — it is triggered by Nexus after
each calibration C3D is saved.

The script accesses the current open trial via `ViconNexus()` (Vicon
Nexus MATLAB SDK), loads analog EMG and force-plate data via BTK
(`btkReadAcquisition`, `btkGetAnalogs`), and calls the `+Hreflex`
namespace in labTools to produce recruitment curves. Output figures
are saved to a `HreflexCalFigs/` subfolder of the trial directory.
The experimenter inspects the curves to select the stimulation
current for the walking adaptation trials (target: ≈ 10–20% of
maximum M-wave).

**`+Hreflex` functions called by this pipeline** (all in
`labTools/fun/+Hreflex/`):

| Function | Role |
|---|---|
| `extractStimArtifactIndsFromTrigger` | Locate pulse times from trigger channel |
| `plotStimArtifactPeaks` | Plot detected peaks for QC |
| `extractSnippets` | Extract per-pulse EMG windows |
| `plotSnippets` | Plot per-pulse snippets for QC |
| `extractBackgroundEMG` | Compute pre-stimulus background level |
| `computeAmplitudes` | Peak-to-peak M- and H-wave amplitudes |
| `fitCal` | Fit recruitment curves to amplitude vs. current |
| `plotNoiseHistogram` | Plot background EMG noise distribution |
| `plotCal` | Plot fitted recruitment curves |

## Hardware

H-reflex stimulation requires an Arduino Uno running the firmware in
`HreflexStimArduino/`. See
[HreflexStimArduino/README.md](../../HreflexStimArduino/README.md)
for the upload procedure, wiring diagram, and pre-experiment
checklist.

## See Also

[EXPERIMENT_SETUP.md](../../EXPERIMENT_SETUP.md).
