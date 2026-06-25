# controllers/

Active real-time speed controllers called by `AdaptationGUI` and the utility
functions they depend on. See [EXPERIMENT_SETUP.md](../EXPERIMENT_SETUP.md)
for full descriptions, study-usage details, and protocol-creation guidance.

## Key Controllers for New Development

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
| `NirsHreflexArduinoOpenLoopWithAudio` | 14 | fNIRS event markers + H-reflex stimulation |
| `NirsAutomaticityAssessment` | 10 | Overground fNIRS dual-task assessment |
| `OGNBackTask` | 13 | Overground N-back cognitive dual-task |

All other controllers in the [Active Controllers](#active-controllers)
table below are study-specific or legacy variants and are not
recommended as starting points for new protocols.

## Active Controllers

| GUI Slot(s) | File | Summary |
|---|---|---|
| 1 | `controlSpeedWithSteps_edit1.m` | Basic split-belt; fixed profile, no self-selected calibration |
| 2–4 | `controlSpeedWithSteps_selfSelect.m` | Primary split-belt controller; stride-synchronized updates |
| 5 | `SelfSelectedSpeed.m` | Overground self-selected speed calibration |
| 6 | `SelfSelectedSpeed_NumPad.m` | NumPad-input variant of self-selected speed calibration |
| 7 | `controlSpeedWithSteps_selfSelect_OneClick.m` | Stride-based perceptual trial; ends on single click |
| 8, 16 | `HreflexOGWithAudio.m` | Overground with H-reflex triggers and audio speed feedback |
| 9 | `controlSpeedWithSteps_PercAdap.m` | Perceptual adaptation; time-based trial end |
| 10 | `NirsAutomaticityAssessment.m` | Overground alphabet dual-task with fNIRS event logging |
| 11 | `controlSpeedWithSteps_edit1_AudioCountDown.m` | Split-belt with audio countdown cue at trial start |
| 12 | `Dulce_grad_betarev2.m` | H-reflex gradient computation (grad project) |
| 13 | `OGNBackTask.m` | Overground N-back cognitive dual-task (Wii remote input) |
| 14 | `NirsHreflexArduinoOpenLoopWithAudio.m` | Split-belt with fNIRS events, Arduino-timed H-reflex, and audio feedback |
| 15 | `controlSpeedWithSteps_WeberPerceptionFaster.m` | Weber perception; fast inter-stride updates |

## Utility Helpers

| File | Called By |
|---|---|
| `generateNbackRestEventString.m` | `OGNBackTask` |
| `generateNirsRestEventString.m` | `NirsAutomaticityAssessment` |
| `nirsEvent.m` | `OGNBackTask`, `NirsAutomaticityAssessment`, `NirsHreflexArduinoOpenLoopWithAudio` |

## Deprecated/

Inactive backup variants and experimental branches. Files are preserved here
for reference and git history but are not part of the active controller set.

- `NirsHreflexOpenLoopWithAudio.m` — MATLAB-timed H-reflex variant; pairs
  with `HreflexStimArduino/Dual_Stim_Matlab.ino` (immediate-fire, no
  on-board gait detection), not the current production firmware. Kept as
  the fallback if the lab ever reverts to that firmware.
