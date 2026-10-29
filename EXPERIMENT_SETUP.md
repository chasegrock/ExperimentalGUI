# Experiment Setup Guide

This document is a reference for lab members running or creating experiments
with ExperimentalGUI. It covers the active study protocols, the controller
library, step-by-step instructions for building a new protocol, and expected
hardware and software configuration.

For coding conventions and contribution guidelines, see
[CONTRIBUTING.md](CONTRIBUTING.md). For a project overview and software
requirements, see [README.md](README.md).

---

## Table of Contents

1. [Active Experimental Studies](#active-experimental-studies)
2. [Controller Reference](#controller-reference)
3. [Creating a New Experimental Protocol](#creating-a-new-experimental-protocol)
4. [External Dependencies and Editable Boundary](#external-dependencies-and-editable-boundary)
5. [Hardware Setup: Bertec Treadmill](#hardware-setup-bertec-treadmill)
6. [Hardware Setup: Vicon Nexus 2.12](#hardware-setup-vicon-nexus-212)
7. [Other Instrumentation](#other-instrumentation)

---

## Active Experimental Studies

| Study Folder | Status | Lead Experimenter(s) | Study Type | Primary Protocol Script |
|---|---|---|---|---|
| [`BrainWalk/`](studies/BrainWalk/README.md) | **Active — longitudinal** | Shuqi Liu, Jiwon Choi | Cognitive dual-task walking (N-back) | `BrainWalkProtocol.m` |
| [`C3/`](studies/C3/README.md) | **Active** (~3 remaining; est. July 2026) | Nate Brantly | Stroke rehabilitation split-belt | `RunProtocol_C3.m`, `RunProtocol_C3_Session2Bouts.m` |
| [`NirsAutomaticityProtocol/`](studies/NirsAutomaticityProtocol/README.md) | **Completed** | Shuqi Liu | fNIRS + H-reflex + split-belt treadmill | `NirsAutomaticityStudyTMProtocol.m` |
| [`Perceptual Adaptation/`](<studies/Perceptual Adaptation/README.md>) | **Completed** | Marcela Gonzalez-Rubio | Two-alternative forced choice perceptual adaptation | `GeneratePartialProfile.m` |
| [`SpinalAdapt/`](studies/SpinalAdapt/README.md) | **Rebooting** (collection begins 2026-09-29) | Chase Rock | H-reflex spinal adaptation to split-belt (+ fNIRS) | `RunProtocol_SpinalAdaptBouts.m` (template; Pilot Study 2 original in `History-PilotStudy2/`) |
| [`Weber Perception/`](<studies/Weber Perception/README.md>) | **Completed** | Marcela Gonzalez-Rubio | Perceptual discrimination thresholds | `GeneratePartialProfile.m` |

### BrainWalk — Stability Notice

**Lead experimenters:** Shuqi Liu, Jiwon Choi.

BrainWalk is a multi-year longitudinal study. Participants return for
visits one year apart, and all procedures must be identical across
visits and across all participants. **Do not make functional changes**
to `BrainWalkProtocol.m` or to the controllers it invokes
(`OGNBackTask`, `NirsAutomaticityAssessment`). Formatting changes are
acceptable; logic changes are not.

### SpinalAdapt — Protocol Notes

**Lead experimenter:** Chase Rock (post-doctoral fellow).
**Key experimenters:** Shuqi Liu, Nate Brantly. Data collection
begins 2026-09-29 with an outside pilot participant with stroke. The
study lead prefers "visit" rather than "session" for this study. See
[studies/SpinalAdapt/README.md](studies/SpinalAdapt/README.md).

Participant ID formats: `SAYA##` (neurologically intact young adults),
`SAST##` (stroke), `SAMC##` (matched controls); `SABH##` identifies
Pilot Study 2 and earlier data. Revised 2026-09-18: every belt speed in
the visit is derived from the overground 6-minute walk test (6MWT)
speed — slow = 0.5×, fast = 1.0×, fastest = 1.5× (`speedProportion` /
`speedProportionFastest` in `RunProtocol_SpinalAdaptBouts.m`), computed
via `utils.extractSpeedsNMWT`, whose walkway-distance default is 10 m
(the current lab walkway). Historical walkway distances used before
this default was introduced, kept here for reference: 12.2 m (Schenley
Place gym) and 11.5824 m (an earlier, longer lab walkway). Pilot Study
2 used a 0.7 slow:fast ratio (changed from 0.5 after participant
SABH16, July 2024) with an abrupt tied-to-split transition (no ramp).
The current design's "abrupt split" refers to the same thing — no
separate ramp-to-split phase — and is distinct from the per-bout
3-stride ramp from rest to target speed at the start of every bout
(tied or split); see `studies/SpinalAdapt/README.md`'s Protocol Notes.

Every participant completes two visits, with the leg on the fast belt
flipped between them: Visit 1 = dominant (young adult), non-paretic
(stroke), or matched (matched control) leg; Visit 2 = the other leg.
At the start of each visit, `RunProtocol_SpinalAdaptBouts.m` asks by
dialog for the visit participant ID — the participant ID plus `_V01`
or `_V02`, e.g. `SAST01_V01` — and the fast leg, then confirms the leg
for that participant type and visit. Name each visit's Vicon Nexus and
Oxysoft folder `Visit01`/`Visit02` inside the participant-ID folder
(e.g., `...\SpinalAdaptStudy\SAST01\Visit01`). Visit 1 completes the
6MWT and generates every profile, for both possible fast-leg
assignments, into a profile folder both visits share; Visit 2 skips
the 6MWT and profile generation and loads those profiles. At the end
of each visit, `transferData_SpinalAdaptBouts` copies the data to
`W:\Chase\SpinalAdapt\` (`Data\<ID>\SpeedProfiles` shared by both
visits, then `Data\<ID>\Visit0N\` and `RawBackupData\<ID>\Visit0N\`).
A fixed ~2.5 min break follows every bout-based condition except the
last, and each bout's spoken "stop" plays on its last step, about half
a stride before the belts stop. There is no fNIRS or H-reflex during
the tied fastest-speed trial (150% of 6MWT, no ramp, no stim), so it runs
on the plain open-loop audio-countdown controller
(`controlSpeedWithSteps_edit1_AudioCountDown`, shared with C3/
BrainWalk) instead of the NIRS/H-reflex controller used by every other
condition, and gets that controller's own spoken "treadmill will
start/stop in 3-2-1" countdown instead of the usual cues.

H-reflex stimulation requires an Arduino Uno running the firmware in
`HreflexStimArduino/`. See `HreflexStimArduino/README.md` for the
complete upload procedure, hardware wiring, and pre-experiment
checklist.

H-reflex timing is split between MATLAB and the Arduino: the Arduino
owns the precise 50%-single-stance pulse timing, and
`NirsHreflexArduinoOpenLoopWithAudio` sends a per-stride gate byte
during the double support phase immediately preceding single-stance
onset (a mid-stance send caused missed/mistimed stims and was fixed to
send at onset; the send was then moved one phase earlier still, to the
preceding double support, to further widen the margin — both fixes
MATLAB-only, no firmware change). It also sends the start (`0`)/stop
(`3`) handshake that runs the Arduino's state machine. See
[studies/SpinalAdapt/README.md](studies/SpinalAdapt/README.md) for the
timing contract and the validation checklist to run before collection.

The overground 6-minute walk test (6MWT) — the first trial of Visit 1,
whose speed sets every other trial's belt speed in both visits — uses
`HreflexOGWithAudio` (menu slot 8) self-paced (`hreflex_present =
false`, no stim, audio feedback answered "No"). H-reflex walking
calibration and all bout-based conditions use
`NirsHreflexArduinoOpenLoopWithAudio` (menu slot 14). There is no
separate OG baseline trial in the current protocol design.

**H-reflex calibration processing:** After each walking dynamic
calibration trial, a Vicon Nexus 2.12 processing pipeline runs
`GenerateHreflexRecruitmentCurves.m` (`labTools/fun/misc/`) to
produce recruitment curves in near real time. The script reads the
open trial via `ViconNexus()` (Nexus MATLAB SDK), loads EMG and
force-plate data via BTK, and calls helper functions in the
`+Hreflex` namespace (labTools) to extract M- and H-wave
amplitudes, fit curves, and save figures to `HreflexCalFigs/`.
This script is triggered by Nexus — not by ExperimentalGUI. The
pipeline's Run MatLab Operation step is currently broken, so run the
script manually after each calibration C3D is saved; enter every EMG
sensor's muscle (`NA` only for unused sensors). See
[studies/SpinalAdapt/README.md](studies/SpinalAdapt/README.md).

**H-reflex M-wave monitor:** a separate, near-real-time tool helps the
experimenter hold each leg's M-wave within ~±10% of its calibration
baseline during a session, running in its own MATLAB instance so it
cannot perturb the control loop above. Built for SpinalAdapt but kept
study-agnostic (outside `studies/SpinalAdapt/`) since other studies
may adopt H-reflex measurement later. See
[HreflexMwaveMonitor/README.md](HreflexMwaveMonitor/README.md) for
phase status, file list, and validation results.

**H-reflex electrode placement:** before the walking calibrations,
the bar electrode's site over the tibial nerve is found once per leg
with `HreflexMappingTool` (repo root, `HreflexMappingTool/`). It runs
in a MATLAB instance of its own and fires single DS8R pulses through
the Digitimer COM API (not the Arduino). It plots TA and Soleus EMG
for a Center site and for sites moved left, up, right, and down, with
automatic M-wave/H-reflex peaks and latencies, and logs every trial to
`<Leg>NerveLocalization/`. See
[HreflexMappingTool/README.md](HreflexMappingTool/README.md) for the
procedure, outputs, and open lab checks.

---

## Controller Reference

The `controllers/` folder contains the active controllers listed below
plus three supporting utility functions (`generateNbackRestEventString`,
`generateNirsRestEventString`, `nirsEvent`). Inactive backup variants
have been moved to `controllers/Deprecated/` and are preserved there
for reference.

### Key Controllers for New Development

**Primary starting points** for new experimental protocols:

- `controlSpeedWithSteps_edit1_AudioCountDown` (slot 11) — split-belt
  treadmill with audio countdown; recommended base for new treadmill
  protocols
- `HreflexOGWithAudio` (slots 8/16) — overground walking with H-reflex
  triggers and audio speed feedback; recommended base for new overground
  protocols

**Use-case-specific** key controllers:

| Controller | Slot | Use when the protocol needs |
|---|---|---|
| `NirsHreflexArduinoOpenLoopWithAudio` | 14 | fNIRS event markers + H-reflex |
| `NirsAutomaticityAssessment` | 10 | Overground fNIRS dual-task |
| `OGNBackTask` | 13 | Overground N-back cognitive dual-task |

All other controllers in the table below are study-specific or legacy
variants and are not recommended as starting points for new protocols.

GUI menu slot numbers correspond to `case` labels in
`Execute_button_Callback` (AdaptationGUI.m lines 374–544).

| Menu Slot | Controller | Description | Used By |
|---|---|---|---|
| 1 | `controlSpeedWithSteps_edit1` | Basic split-belt controller; fixed speed profile without self-selected speed calibration phase. | General / standalone use |
| 2–4 | `controlSpeedWithSteps_selfSelect` | Primary split-belt treadmill controller. Stride-synchronized belt updates; establishes self-selected speed baseline. Slot 2 = signed, 3 = unsigned, 4 = closed-loop. | General treadmill adaptation protocols |
| 7 | `controlSpeedWithSteps_selfSelect_OneClick` | One-click-start variant; trial ends on single response. Used for stride-length based perceptual trials. | Perceptual Adaptation (stride-based) |
| 9 | `controlSpeedWithSteps_PercAdap` | Perceptual adaptation variant; trial ends on click response, task length is time-based. | Perceptual Adaptation |
| 11 | `controlSpeedWithSteps_edit1_AudioCountDown` | Split-belt controller with audio countdown cue at trial start. | BrainWalk (TM trials), C3 (TM trials) |
| 15 | `controlSpeedWithSteps_WeberPerceptionFaster` | Weber perception variant; faster inter-stride update for threshold estimation. | Weber Perception |
| 8 | `HreflexOGWithAudio` | Overground (no belt control) with H-reflex triggers and audio speed feedback. | BrainWalk (OG baseline), C3 (OG baseline), SpinalAdapt (6-min walk test) |
| 16 | `HreflexOGWithAudio` | Same controller, second menu entry. Not currently used by an active study — SpinalAdapt's OG baseline trials were removed from the protocol design. | (unused) |
| 14 | `NirsHreflexArduinoOpenLoopWithAudio` | Split-belt controller with fNIRS event markers, H-reflex stimulation, and audio feedback. | NirsAutomaticityProtocol, SpinalAdapt (calibration + all bout-based conditions) |
| 10 | `NirsAutomaticityAssessment` | Overground alphabet dual-task assessment. Records responses and logs events. | BrainWalk, NirsAutomaticityProtocol |
| 12 | `Dulce_grad_betarev2` | H-reflex gradient computation tool (grad project). | Standalone H-reflex analysis |
| 13 | `OGNBackTask` | Overground N-back cognitive dual-task; plays audio stimuli and records Wii-remote responses. | BrainWalk |
| 5 | `SelfSelectedSpeed` | Overground controller for self-selected walking speed calibration. | General calibration |
| 6 | `SelfSelectedSpeed_NumPad` | NumPad-input variant of self-selected speed calibration. | General calibration |

---

## Creating a New Experimental Protocol

### Overview

A new protocol requires three components:

1. A `generateProfiles_<StudyName>.m` script to generate speed profiles
2. A `RunProtocol_<StudyName>.m` script to sequence trials and call the GUI
3. Optionally, a new controller in `controllers/` if none of the existing
   ones fit the experimental design

### Step-by-Step

**Step 1 — Create a study folder**

```
studies/<StudyName>/
    generateProfiles_<StudyName>.m
    RunProtocol_<StudyName>.m
```

**Step 2 — Write the profile generator**

`generateProfiles_<StudyName>.m` must produce two Nx1 vectors:
- `velL` — left belt speeds in mm/s for each stride
- `velR` — right belt speeds in mm/s for each stride

A `NaN` at position k signals a self-paced stride: the controller holds
or queries the current treadmill speed instead of commanding a preset
value. Profiles are passed directly to the controller as arguments —
there is no file-based loading at runtime.

```matlab
% Example: 50-stride baseline at 800 mm/s, then 100-stride adaptation
% with 2:1 speed ratio, then 50-stride post-adaptation
velL = [repmat(800, 50, 1);  repmat(800, 100, 1);  repmat(800, 50, 1)];
velR = [repmat(800, 50, 1);  repmat(1600, 100, 1); repmat(800, 50, 1)];
```

**Step 3 — Choose a controller**

Consult the [Controller Reference](#controller-reference) table. For a
standard split-belt adaptation paradigm, start with
`controlSpeedWithSteps_edit1_AudioCountDown`. If you need features not
present in any existing controller (e.g., a new peripheral, a novel
feedback signal), copy the closest existing controller, rename it
following camelCase convention, and modify it.

**Step 4 — Add a new controller to the GUI (if needed)**

If you created a new controller, register it in `AdaptationGUI`:

1. Open `AdaptationGUI.fig` in GUIDE and add the controller name to the
   `popupmenu2` string list.
2. In `AdaptationGUI.m`, locate `Execute_button_Callback` and add a
   `case` for the new controller name that calls it with the appropriate
   arguments (follow the pattern of existing cases).

**Step 5 — Write the protocol script**

`RunProtocol_<StudyName>.m` should:
1. Open `AdaptationGUI` and obtain its `handles` struct
2. For each trial block, set `handles.popupmenu1` (profile) and
   `handles.popupmenu2` (controller) to the desired values, then call
   `Execute_button_Callback` (or prompt the experimenter to click Execute)
3. Use `questdlg` calls to pace the experimenter through the session and
   confirm readiness before each trial

See `studies/SpinalAdapt/RunProtocol_SpinalAdaptBouts.m` or
`studies/C3/RunProtocol_C3.m` as reference implementations.

**Step 6 — Test before participant data collection**

Run the protocol with a short dummy profile (e.g., 5 strides) in the
lab with the treadmill at low speed to verify that belt commands,
data logging, and data transfer all work as expected before involving
participants.

---

## External Dependencies and Editable Boundary

ExperimentalGUI calls a fair amount of code it does not own. This
section states what lives in this repo (and may be edited here) versus
what is a fixed external interface that must be changed upstream. The
three MATLAB path roots are listed in
[README.md](README.md#matlab-path-dependencies).

### What this repo owns (editable here)

`AdaptationGUI.m`/`.fig`, everything under `controllers/`, `studies/`,
and `+utils/`, the top-level helpers (`FindKinHS`, `FindKinTO`,
`smoothStop`, `parseEventsFromSpeeds`, `manualLoadProfile`, `nirsEvent`,
the `generate*EventString` helpers, `NBackHelper`, `ISIRandMethod`), the
standalone H-reflex tools in `HreflexMwaveMonitor/` and
`HreflexMappingTool/`, and the `HreflexStimArduino/` firmware. Edits
here are subject to the per-study stability rules above (BrainWalk
logic frozen; C3 and SpinalAdapt require coordination with the lead
experimenter).

### Fixed external interfaces (do not edit here; change upstream)

| Interface | Path root / location | Representative symbols |
|---|---|---|
| Vicon DataStream SDK v1.11.0 (`.NET`; `ViconDataStreamSDK_DotNET.dll`) | `C:\Program Files\Vicon\DataStream SDK\Win64\dotNET\` | `ViconDataStreamSDK.DotNET.Client`, `MyClient.GetFrame`, `MyClient.GetMarkerGlobalTranslation`, `MyClient.GetDeviceOutputValue` |
| Vicon Nexus MATLAB SDK | `W:\Nathan\ViconNexusSDK\MATLAB\` (server drive; distinct from DataStream SDK) | `ViconNexus` class — used by Nexus pipeline scripts (e.g. `GenerateHreflexRecruitmentCurves.m`); not called directly by ExperimentalGUI |
| Bertec treadmill comm layer | `C:\Users\Public\Documents\MATLAB\HMRLhardware\TreadmillInterface\` (lab PC) | `getPayload`, `sendTreadmillPacket`, `readTreadmillPacket`, `openTreadmillComm`, `getCurrentData` |
| labTools post-processing | `C:\Users\cntctsml\Documents\GitHub\labTools\` | `dataMotion.processAndFillMarkerGapsSession`, `dataMotion.exportSessionToC3D` |
| Artinis Oxysoft (fNIRS) COM API | installed application | `actxserver('OxySoft.OxyApplication')` |
| Digitimer DS8R COM API | installed DS8R control software | `actxserver('DigitimerDS8R.DS8RController')`, `GetState`, `SetState`, `Trigger` — used only by `HreflexMappingTool` |
| Arduino H-reflex firmware | running device (source in `HreflexStimArduino/`) | serial `0`/`1`/`2`/`3` handshake |

Changing the treadmill packet contract, the DataStream marker/device
names, or the `dataMotion.*` signatures requires edits in the lab-PC
MATLAB tree or the labTools repo — not here. The Arduino serial
handshake is co-owned with the firmware (see the H-reflex timing
contract in [README.md](README.md) and `CLAUDE.md`).

### Toolbox requirements

Most controllers and protocols rely only on core MATLAB (audio via
`audioplayer`/`audioread`, serial via `serialport`, COM/.NET interop via
`actxserver`/`NET.addAssembly` — none of which require an add-on
toolbox). The exceptions:

- **Statistics and Machine Learning Toolbox** — required by the N-back
  ISI generators (`GenerateNBackSequence`, `GenerateNBackSequence_3back`,
  `NBackHelper`), which use `histfit` and `normrnd`.
- **Instrument Control Toolbox** — only the legacy `serial()` COM paths
  in `AdaptationGUI` use it; the active `serialport` API does not.
- **Signal Processing Toolbox** — optional for `HreflexMappingTool`'s
  10–500 Hz display band-pass (`butter`/`filtfilt`); without it the
  tool falls back to DC removal and warns.

### Unverified / risk

- `NexusGetFrame` and `openNexusIface` are not found in this repo, in
  labTools, in the DataStream SDK, or in the Nexus MATLAB SDK naming.
  They appear only in legacy code paths in `Dulce_grad_betarev2.m` and
  `SelfSelectedSpeed.m` and are presumed dead or lab-PC-only custom
  wrappers.

---

## Hardware Setup: Bertec Treadmill

### What the Code Provides

- **Communication:** UDP connection initialized once per trial in
  `sendTreadmillPacket` (external treadmill comm layer).
- **Packet format:** 64 bytes — 1 format byte, 9 int16 values
  (speedR, speedL, speedRR, speedLL, accR, accL, accRR, accLL,
  incline), 1 checksum byte (255 − sum of data bytes), 27 padding bytes.
- **Hard limits enforced by `getPayload`:** speed ±6500 mm/s,
  acceleration ≤ 3000 mm/s². Commands outside these ranges are clipped.
- **Belt speed logging:** the Bertec's own reported belt speed/incline
  (not just what was commanded) is already read every ~100 ms via
  `readTreadmillPacket` and logged per frame to
  `datlog.TreadmillCommands.read`; commanded values are logged
  separately to `.sent`. `utils.buildDatlogFrameTable(datlog)` joins
  these with forces, gait events, and H-reflex stim gate sends onto one
  per-frame timetable, computed on demand from the saved datlog (not a
  stored field, so it adds nothing to the `.mat` file or to labTools'
  in-memory footprint when loading many trials).

### Bertec Sync Software Settings

> [TODO: Document the expected Bertec Sync software settings here,
> including UDP port configuration, force-plate zeroing procedure,
> and any required startup steps before running an experiment.]

---

## Hardware Setup: Vicon Nexus 2.12

### Marker Set and Capture Settings

> [TODO: Document the marker set used (e.g., Plug-in Gait or custom),
> the expected capture frame rate (e.g., 100 Hz), and the labeling
> template name loaded in Nexus before each session.]

### EMG: Delsys Trigno Wireless System

Surface EMG is recorded using a Delsys Trigno wireless system. Data
are acquired in Nexus 2.12 across two separate, synchronized PCs
(one per leg). Both PCs must be connected to the same Nexus system
before capture begins.

> [TODO: Document the Delsys Trigno channel configuration (sensor
> mapping, muscle assignment) and the dual-PC synchronization
> procedure in Nexus.]

### C3D Output

> [TODO: Document the expected C3D output path convention and any
> naming requirements for compatibility with downstream analysis
> pipelines (e.g., labTools processing scripts).]

---

## Other Instrumentation

### Artenis fNIRS Headband

Used in the BrainWalk study to record prefrontal cortex oxygenation
during cognitive dual-task walking. The headband is synchronized with
the treadmill trial via event markers inserted by
`NirsAutomaticityAssessment` and `OGNBackTask` controllers.

> A.	Take head measurements using a tape measure in the third drawer under the computer desk.
B.	Set up the Oxysoft software.
  1.	Retrieve the big yellow briefcase next to the breakroom and plug in the red flash drive (usually already plugged in).
  2.	Open the Oxysoft application.
  3.	Go to File > New Project > Save Project. Navigate to Documents > Oxysoft Data > BrainWalk, create a new subject folder (e.g., BW0#), create a new visit folder (e.g., V0#), and save the file as BW0#V0#Oxyproj (e.g., BW002V04Oxyproj).
  4.	Select File > Create a new measurement.
  5.	Go to Measurement > Create New Measurement > Browse.
  6.	Select the current subject’s folder and save the measurement file as BW0#V0#M0# (e.g., BW002V01M01).
  7.	Copy the measurement file name (BW0#V0#M0#), paste it into the Data Name field, and click Next.
  8.	Add device 16704, select the Opt-temp setting 2x4, and continue clicking Next until prompted to Start Measurement — do not start yet.
C.	Fit the fNIRS band on the participant.
  1.	Ensure the band is loose before placing it.
  2.	Hold the front portion in one hand and the back in the other. Bring the back to the front and place the front section on the participant's forehead.
  3.	Align the two center sensors with the center of the eyebrows.
  4.	Tighten the side bands and confirm the front center is properly aligned.
  5.	Use the comb to take out any hair between the band and the forehead.
  6.	Measure the distance from the eyebrows to the bottom edge of the band.
D.	Start the measurement once the band is securely in place.
E.	Place the battery in the backpack and put the backpack on the participant.
F.	Verify signal quality.
  1.	In the Data Acquisition panel at the bottom, confirm that numbers appear in all 16 channels (channels 1–8 = right; channels 9–16 = left).
G.	Recording procedure.
  	NOTE: Oxysoft recording must be started and stopped manually for every trial.
  1.	To start recording, press the green button in the top panel.
  2.	Enter the correct recording number for the trial (e.g., BW002V01M01 for Trial 1, BW002V01M02 for Trial 2, and so on).
  	The Oxysoft trial number is independent from Vicon trial number and both of them should be tracked in the datasheet.
  3.	Select Connect Device. If Oxysoft does not recognize the device, ensure the participant is close enough to the computer – Bluetooth connection can be lost if too far.
  4.	Press Next until the recording begins (red and blue lines will fluctuate regularly).
    a.	Red = Oxygenated, Blue = Deoxygenated
  5.	Wait at least 20 seconds before starting the trial in Vicon or MATLAB.
  6.	To stop recording, press the red button.
  7.	Confirm that green lines are visible throughout the recording — these indicate event time points.


### Wii Remote

Used in perceptual studies (Perceptual Adaptation, Weber Perception)
for two-alternative forced choice responses. Participants press left or
right button to indicate perceived faster belt.

> [TODO: Document Bluetooth pairing procedure and which MATLAB
> toolbox or driver is required.]

### Arduino H-Reflex Stimulator

Used in SpinalAdapt and NirsAutomaticityProtocol. The Arduino
interface is in `HreflexStimArduino/`. Stimulation timing is triggered
by the `NirsHreflexArduinoOpenLoopWithAudio` and `HreflexOGWithAudio`
controllers.

**Hardware:** Arduino Uno + two Digitimer DS8R constant-current
stimulators. The Arduino reads force-plate Fz voltage on analog pins
A0 (left) and A1 (right) to detect heel strikes and toe-offs, and
delivers 20 ms trigger pulses on digital pins 8 (right stim) and 9
(left stim). Vicon sync outputs are on pins 11 (right) and 12 (left).

**Firmware:** Upload
`triggerStimWithGaitStateMachine_SpeedIndependent.ino` from the
`HreflexStimArduino/` folder. See `HreflexStimArduino/README.md` for
the complete step-by-step upload procedure (board: Arduino Uno;
baud rate: 115200).

**Stimulus intensity calibration:** Performed at the start of each
session using the calibration trials in `RunProtocol_SpinalAdaptBouts.m`
(`runWalkingCalibrations.m`). The experimenter adjusts DS8R output
current until H-reflex responses of approximately 10–20% of maximum
M-wave are observed in the EMG signal.

> [TODO: Document the detailed DS8R current ramp procedure and the
> Delsys EMG channels used for H-reflex response monitoring.]
