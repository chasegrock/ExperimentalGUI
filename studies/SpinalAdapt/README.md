# SpinalAdapt

Measures spinal-level H-reflex adaptation to split-belt treadmill
walking alongside prefrontal cortex oxygenation (fNIRS). H-reflex
responses are elicited by Arduino-triggered Digitimer DS8R
stimulators at a fixed phase of the gait cycle.

## Status

**Rebooting; data collection begins 2026-09-29** with an outside pilot
participant with stroke — the first participant from outside the lab
and the first participant with stroke to run the two-visit protocol
(`SAST##_V01`/`_V02`; see Two-Visit Protocol below). The internal lab
pilots before it (2026-09 `SAYA##` visits) validated the H-reflex
timing path; open items are tracked under Validation Before Collection.

## Experimenters

| Role | Name |
|---|---|
| Lead | Chase Rock (post-doctoral fellow) |
| Key | Shuqi Liu |
| Key | Nate Brantly |

## Participant IDs

| Format | Population |
|---|---|
| `SAYA##` | Neurologically intact young adults |
| `SAST##` | Participants with stroke |
| `SAMC##` | Matched controls |
| `SABH##` | Pilot Study 2 and earlier data (healthy); not used in the rebooted study |

Every participant completes two visits. The **visit participant ID**
adds the visit suffix, `_V01` or `_V02` (e.g., `SAST01_V01`); the Vicon
Nexus and Oxysoft visit folders and the server folders are named
`Visit01`/`Visit02`, inside a folder named with the participant ID
(e.g., `SAST01\Visit01`).

## Protocol Notes

**Speeds** are all derived from the overground N-Minute (6-minute)
Walk Test comfortable walking speed (`speedNMWT`), computed via
`utils.extractSpeedsNMWT()` immediately after the walk test trial (see
below): slow = 0.5×, fast = 1.0×, fastest = 1.5× `speedNMWT`
(`speedProportion` / `speedProportionFastest` in
`RunProtocol_SpinalAdaptBouts.m`). Pilot Study 2 used a 0.7 slow:fast
ratio, changed from 0.5 after participant SABH16 (July 2024) — see
Study History below. The 1.5× "fastest" speed was added 2026-09-18 for
the single tied trial described below. `extractSpeedsNMWT`'s default
walkway distance is 10 m (the SpinalAdapt lab walkway) as of
2026-09-18 — this function is currently called only from this study's
protocol script. Earlier walkway distances (12.2 m, Schenley Place
gym; 11.5824 m, an earlier/longer lab walkway) are no longer offered
as dialog defaults but are recorded in
[EXPERIMENT_SETUP.md](../../EXPERIMENT_SETUP.md)'s SpinalAdapt section
for reference.

**Current protocol design (revised 2026-09-18):**

| Condition | # | Structure |
|---|---|---|
| Tied Fastest (tied, no ramp, 150% of 6MWT) | 1 | 50 SS strides |
| Pre-Adaptation Fast (tied, 100% of 6MWT, 10 bouts × 3 ramp + 10 SS) | 1 | 130 strides |
| Pre-Adaptation Slow (tied, 50% of 6MWT, 10 bouts × 3 ramp + 10 SS) | 1 | 130 strides |
| Adaptation Split (100%/50% split, 10 bouts × 3 ramp + 10 SS per trial) | 5 | 130 strides each |
| Post-Adaptation Slow (tied, 50% of 6MWT, 10 bouts × 3 ramp + 10 SS) | 5 | 130 strides each |

Total: 50 + 130 + 130 + 5×130 + 5×130 = **1,610 strides**. Profile
files: `TiedFastest.mat`, `PreAdaptFast.mat`, `PreAdaptSlow.mat`,
`AdaptSplitFastR.mat`, `AdaptSplitFastL.mat`, `PostAdaptSlow.mat`.
Familiarization trials (`FamBoutsSlow.mat`/`FamBoutsFast.mat`, part of
the 2026-08-13 design) were removed. H-reflex walking calibration
(`CalibrationFast.mat`, `CalibrationSlow.mat`, 400 strides each) runs
separately before and after the main protocol via
`runWalkingCalibrations`, not as a numbered condition — the
start-of-visit loop defaults to slow first, then fast, matching the
protocol's own speed order. There are no TM/OG baseline conditions or
profiles in the current design — the previous protocol version used
the TM baseline step length asymmetry to determine each stroke
participant's fast/slow leg assignment; the current design takes the
fast leg as a direct experimenter entry instead (see Two-Visit Protocol
below).

**Breaks (added 2026-09-18):** a fixed ~2.5 min break
(`pauseBetweenTrials = 115` s, plus the ~35 s Vicon stop/start delay)
follows every bout-based condition (2, 3, and the numbered Adaptation
Split / Post-Adaptation Slow blocks) except the very last condition of
the visit. There is no break between the 6MWT, the start-of-visit
H-reflex calibration trials, or after the Tied Fastest trial (condition
1) — the protocol proceeds straight into condition 2 after it.

**Adaptation split profile, both fast-leg assignments (added
2026-09-18 for the two-visit protocol):** `generateProfiles_
SpinalAdaptBouts` generates BOTH `AdaptSplitFastR.mat` (right belt
fast) and `AdaptSplitFastL.mat` (left belt fast) up front, rather than
taking a `fastLeg` input and generating only one. `RunProtocol_
SpinalAdaptBouts.m` selects the file matching the confirmed fast leg
at run time, so Visit 2 reuses every profile generated in Visit 1 with
the fast/slow leg assignment simply flipped, without regenerating
anything.

**Two-Visit Protocol (all participants; revised 2026-09-25):** every
participant — young adult (`SAYA##`), participant with stroke
(`SAST##`), or matched control (`SAMC##`) — completes two visits with
the leg on the fast belt flipped between them: Visit 1 puts the
dominant (young adult), non-paretic (stroke), or matched (matched
control) leg on the fast belt, and Visit 2 the other leg.

- **Entry.** `RunProtocol_SpinalAdaptBouts.m` opens with a dialog for
  the visit participant ID (e.g., `SAST01_V01`) and the leg on the fast
  belt this visit (R/L); nothing is edited in the script (an edited-in
  ID was forgotten during a 2026-09 pilot, and editing a tracked file
  also blocks `git pull` on the lab PC). A malformed ID or leg stops
  the script with an error. A confirmation dialog then spells out which
  leg belongs on the fast belt for that participant type and visit
  (e.g., "Visit 2 (stroke): the fast belt should carry the paretic
  leg").
- **Visit 1** runs the 6-minute walk test, computes speeds, and
  generates every profile (both split variants above) into the
  participant's profile folder,
  `profiles\SpinalAdaptNirsStudy\<participant ID>`, which both visits
  share.
- **Visit 2** skips the walk test and profile generation, verifies the
  Visit 1 profiles exist in that folder (error otherwise, rather than
  silently running an empty folder), and loads the split file for its
  flipped fast leg.
- **Folders.** Name the Vicon Nexus and Oxysoft visit folders `Visit01`/
  `Visit02` inside the participant folder (e.g.,
  `...\SpinalAdaptStudy\SAST01\Visit01`). At the end of each visit
  `transferData_SpinalAdaptBouts(participantID, visitNum, threshTime)`
  copies files newer than the visit's start to the server,
  `W:\Chase\SpinalAdapt\`, laid out as for `SAYA90`:
  `Data\<ID>\SpeedProfiles\` (shared, transferred once, at Visit 1),
  `Data\<ID>\Visit0N\{Vicon, NIRS, DataLogs, Results}`, and
  `RawBackupData\<ID>\Visit0N\{Vicon, NIRS, DataLogs}`. Post-hoc
  outputs (`DatlogSyncRes`, `TrajectoryFigures`, the `c3d2mat` files,
  renamed `DataLogs\TrialNN.mat`) are not the helper's job.

**Overground 6-minute walk test:** the first trial of Visit 1
(added 2026-09-01; moved to run *before* speed computation 2026-09-18,
since its result now sets every other trial's belt speed — previously
`utils.extractSpeedsNMWT()` was called before this trial had run,
which cannot have been correct). Not one of the 13 numbered conditions
above, and skipped entirely in Visit 2 (see above). Uses
`HreflexOGWithAudio` (slot 8, `hreflex_present = false`,
no stim), profile `SixMinuteWalk.mat` (`velL`/`velR` all-`NaN`, 1,000
strides — self-paced, sized only as a generous safety margin since the
trial length is controlled by the experimenter pressing Stop in the
GUI, not by the profile). Answer **No** to the "Should audio feedback
on speed be provided?" prompt so the participant walks at their own
comfortable pace. Generated by its own `generateProfile_
SixMinuteWalk.m`, called directly and only from `RunProtocol_
SpinalAdaptBouts.m` before speeds are known — `generateProfiles_
SpinalAdaptBouts.m` no longer calls it internally (it would just
rewrite an identical, already-present file, since the protocol script
guarantees `SixMinuteWalk.mat` exists before ever reaching profile
regeneration). The walk-test trial and the profile-regeneration dialog
are both guarded by a resume prompt, so restarting a visit mid-way
does not force a redundant six-minute walk or NMWT re-entry. After the
walk-test dialog, the script prints the walk-test arithmetic (laps ×
walkway ± tape = distance / duration) and every derived belt speed in
m/s and in the integer mm/s actually commanded — the paper datasheet's
lap and tape units need not match the dialog's (10 m laps, tape in
inches), and the echo makes a mismatch visible at entry time.

**Tied Fastest trial: a different controller entirely (revised
2026-09-18):** there is no fNIRS or H-reflex during this trial, so
unlike every other condition in the visit it does not run on
`NirsHreflexArduinoOpenLoopWithAudio` (GUI slot 14) at all — it runs on
the plain `controlSpeedWithSteps_edit1_AudioCountDown` (GUI slot 11),
the same controller C3 and BrainWalk use for their own tied trials.
With the default `numAudioCountDown = -1`, that controller speaks its
own "treadmill will start in 3-2-1" countdown before the belts move and
a stride-synced "treadmill will stop in 3-2-1" countdown before they
stop — there is no "stop"/"silently count forward" rest cue and no
silent-counting wait at all for this trial, since that comparison
condition only applies once fNIRS is recording. The profile
(`TiedFastest.mat`) is 50 steady-state strides with no ramp and no
trailing rest pad: `controlSpeedWithSteps_edit1_AudioCountDown` has no
rest-event handling and terminates cleanly once all 50 strides are
taken, unlike the NIRS/H-reflex controller used by every other
condition, which needs a rest event as its self-termination path. **Belt
acceleration is not the same as other trials**, and was not
deliberately changed: `controlSpeedWithSteps_edit1_AudioCountDown`
hardcodes `acc = 3500` mm/s² (vs. the ~500 mm/s² the NIRS/H-reflex
controller used for this trial in an earlier design), which shortens
the dead-stop ramp to 150% of comfortable speed from roughly 3 s to
well under 1 s. This controller is shared with C3/BrainWalk and not
this study's to edit; flag it to the lead experimenter if a gentler
ramp is wanted for this trial specifically. **Why it matters which
controller runs it:** on 2026-09-18 (participant `SAYA90`) this trial
ran on slot 14 — the switch to slot 11 was committed after the trial
— and the participant felt stimulation: the NIRS/H-reflex controller
treated the profile's explicit all-zero `stimL`/`stimR` as "no schedule
given" and gated every 10th stride (strides 4, 14, 24, 34, 44; five
pulses per leg, confirmed on the Vicon trigger channels). Since
2026-09-22 that controller treats an explicit all-zero schedule as no
stimulation; only a profile with no stim variables at all still gets
its legacy every-10th-stride default.

**fNIRS event naming (added 2026-09-18):** every event
`NirsHreflexArduinoOpenLoopWithAudio` logs to Oxysoft is now prefixed
with its condition — e.g. `PreAdaptSlow_Rest01`,
`AdaptSplitFastR_DccRamp2Split05`, `PostAdaptSlow_TrialEnd` — instead
of the bare, condition-agnostic `Rest1` logged before this change, so a
marker in Oxysoft is directly attributable to a condition and epoch
without cross-referencing the run sheet by wall-clock time. This
controller (and hence this naming scheme) covers the ramp-start
(`AccRamp`/`DccRamp2Split`), steady-state (`Mid`/`Split`), and
rest/"stand and silently count forward" (`Rest`) events for every
bout-based condition; the Tied Fastest trial has no fNIRS events at
all, since it does not use this controller (see above). The condition
label is the loaded profile's basename (e.g. `PreAdaptSlow`, or
`AdaptSplitFastR`/`AdaptSplitFastL` per the per-leg split files
above), and only the event's *display string* is prefixed — never the
audio-cue key or the single-letter Oxysoft code, since `nirsEvent`
looks the audio key up with `isKey` and a prefixed key would silently
fail to match, dropping the cue with no error. Composed names are
underscore-free CamelCase (`TrialEnd`, not `Trial_End`) so the
condition prefix stays the only `_` separator in the string; the
`Rest` event name itself comes from the shared `parseEventsFromSpeeds`
(also used by BrainWalk controllers) and was left as-is. See the local
`nirsEventName` helper in `NirsHreflexArduinoOpenLoopWithAudio.m`. The
2026-09-18 pass also normalized the bout numbering: ramp/steady-state
events previously logged one bout number lower than that same bout's
rest event (e.g. `AccRamp0` next to `Rest1`); both now use the same
1-based bout number.

- Calibration trials: `NirsHreflexArduinoOpenLoopWithAudio` (slot 14).
- Bout timing and cues (`NirsHreflexArduinoOpenLoopWithAudio`, revised
  2026-08-13, cue split 2026-09-02): the inter-bout rest is a fixed
  ~10 s SILENT window (`restSilentSec`, belts stopped, timer padded by
  the `silentlyCountForward` cue's own length so it excludes the cue),
  applied to every bout-based trial. Every bout start (tied ramp =
  `AccRamp`, split ramp = `DccRamp2Split`) announces "Walk" exactly
  once, with no 3-2-1 countdown; bout 1 gets the same "Walk" cue from
  the pre-loop block, and the ramp-event cue is suppressed only for
  that first bout to avoid a duplicate. This entire bullet describes
  `NirsHreflexArduinoOpenLoopWithAudio` only; the Tied Fastest trial
  does not use this controller at all (see Tied Fastest trial above).
  The speed ramp at each bout start is 3 strides (`rampStrides` in
  `generateProfiles_SpinalAdaptBouts.m`, reduced from 10). The "which
  bout to start from" dialog range and default are derived from the
  loaded profile's bout count (10 for every bout-based condition), not
  hard-coded. The break between trials (`pauseBetweenTrials` in
  `RunProtocol_SpinalAdaptBouts.m`) targets ~2.5 min wall clock — see
  Breaks above.
- **Belt-stop cues (revised 2026-09-25):** each inter-bout rest and the
  trial end use two short cues, `stop.mp3` ("Stop", 0.72 s) and
  `silentlyCountForward.mp3` ("Silently count forward from one"; both
  from Narakeet — see
  [CONTRIBUTING.md](../../CONTRIBUTING.md#audio-cue-assets)), which
  replaced the too-wordy `stopAndRest.mp3` in 2026-09.
  - **"Stop" is spoken on the bout's last step**, about half a stride
    before the belts stop abruptly: each step counter advances at its
    own leg's toe-off and the belts stop at the first toe-off that
    reaches the rest stride, so the controller plays `stop`
    (non-blocking) once *both* legs have started the final stride.
    History: until 2026-09-22 it played after a 1.5 s settle pause,
    once the belts had already stopped; the 2026-09-24 pilot's version,
    at the zero-speed command, was still too late to be useful. If a
    missed toe-off keeps one counter behind, the rest handler says it
    at the zero-speed command instead.
  - **The rest itself is timed as before:** the Rest fNIRS marker
    follows the zero-speed command by 1.5 s and `silentlyCountForward`
    by 1.5 s + the `stop` cue's length, and the 10 s silent counting
    window (`restSilentSec`) begins exactly when
    `silentlyCountForward.mp3` finishes — so rest epochs stay
    comparable across visits.
  - **Analysis note — exclude each bout's final, post-stop pulse:** at
    every rest, one leg's last gated pulse (alternating legs; 10 of 200
    per bout trial) fires 100–300 ms *after* the zero-speed command,
    while the belts decelerate, because that leg's final single stance
    begins about when the belts are commanded to stop (2026-09-18
    datlogs). The spoken "stop" now also precedes the bout's last one or
    two pulses. These pulses are handled by exclusion in analysis; the
    profiles and controller are deliberately unchanged.
- H-reflex stimulation timing: `NirsHreflexArduinoOpenLoopWithAudio`
  paired with firmware `triggerStimWithGaitStateMachine_SpeedIndependent`
  is the authoritative, Arduino-timed path. The Arduino owns the
  precise 50%-single-stance pulse timing; `NirsHreflexArduinoOpenLoopWithAudio`
  sends command `0` once before the main loop to start the Arduino's
  state machine, a per-stride gate byte (`1`/`2`) during the double
  support phase immediately preceding single-stance onset, and command
  `3` in the closing routine to stop the state machine. Earlier code
  waited until mid-stance to send the gate, which left too little margin
  before the Arduino's 50% trigger and caused missed or mistimed stims
  under control-loop jitter; later code moved the send to single-stance
  onset, and it was moved earlier still, to the preceding double
  support, to further widen the margin — all MATLAB-only, no firmware
  change. Display work was also moved off the control loop's hot path
  (`drawnow limitrate`, reusable `animatedline` markers, throttled
  textbox updates). Both sides estimate single-stance duration via an
  EWMA (`alpha = 0.70`), with each candidate duration clamped to
  100-1000 ms before the update to reject doubled/missed detections
  and standing rests; MATLAB mirrors the firmware's alpha/clamp in its
  own diagnostics EWMA. The firmware also echoes each delivered
  pulse's actual fire time back over serial (`echoStimRecord`), which
  MATLAB logs to the additive `datlog.stim.deviceEcho` field as a lab
  ground-truth check (informational only — it does not feed the firing
  decision). The deprecated `NirsHreflexOpenLoopWithAudio` (now in
  `controllers/Deprecated/`) pairs with the alternative
  `Dual_Stim_Matlab.ino` firmware (fully MATLAB-timed, no on-board gait
  detection) and is a frozen bench/emergency fallback only — do not
  extend it or treat it as a starting point.
- **Missed / wrong-stride stim bug, root cause and fix (2026-08-06):**
  the 2026-08-05 pilot (`CalibrationSlow`, `CtrlBouts`) delivered some
  gates as missed pulses and some one stride late, both still correctly
  timed to 50% of single stance when they did fire. Root cause:
  `NirsHreflexArduinoOpenLoopWithAudio.m` sent every Arduino command
  with `write(portArduino,X,'int16')` — two bytes, command + a
  trailing `0x00` — but the firmware's `processSerialCommands()` reads
  one byte per `loop()` pass and dispatches `case 0` to
  `resetStateMachine()`. Every gate byte was therefore immediately
  followed by a spurious full state-machine reset a few hundred ms
  before the single stance it was meant to gate, which (via the
  cross-leg debounce in `updateGaitEventStateMachine()`) could erase
  the real contralateral toe-off event and stall `phase`, carrying the
  gate into a later stride. Confirmed from the pilot datlogs: the
  echoed `ardStep` column (`numStepsL/R` on the Arduino) only ever took
  values `{0, 1}` across both trials — the signature of a counter that
  keeps getting zeroed mid-trial. Fix: all four `write(...)` calls now
  use `'uint8'` (one byte, matching what the firmware actually reads),
  with the command bytes as named constants
  (`cmdArduinoStart`/`Stop`/`StimL`/`StimR`). No firmware re-flash is
  required for this half of the fix; the serial protocol values
  (`0`/`1`/`2`/`3`) are unchanged. Paired with it, the firmware gained
  a lateness guard and a gate-expiry guard in `triggerStimulation()`
  (see `HreflexStimArduino/README.md`) so that any gate that is still
  late or unconsumed is dropped — echoed as a `D` record — rather than
  fired off-target or carried forward; this **does** require a
  re-flash. The `ardStep`-decreased regression sentinel added to the
  controller (warns once per leg, logs to `datlog.errormsgs`) is the
  direct guard against this bug class recurring. See the dry-run
  checklist below before the next pilot.
- **Missed and wrong-stride stim bug #2, root cause and fix
  (2026-09-14):** the 2026-09-08 pilot (`CalibrationFast`) lost 50 of
  333 strides (15%) to the Arduino's gait-event state machine falling
  behind — `numStepsL/R` climbing too slowly, not resetting — which
  produced 5 missed pulses and 24 stim-stride-schedule gaps (a pulse
  landing a stride later than intended), despite every delivered pulse
  still being correctly timed to ~50% of the (wrong) stride's single
  stance. Diagnosed against the matching Vicon capture (`Trial08.c3d`)
  and a known-good comparison visit from 2026-09-02 (`Trial03.c3d`,
  same belt speed and loop timing, 0 stride-count deficit). Root
  cause: `updateGaitEventStateMachine()`'s stance debounce required
  BOTH legs' `timeSinceStanceChange` to exceed `timeDebounce` (100 ms)
  before accepting a heel-strike or toe-off, coupling the debounce to
  double-support duration; a constant ~40 ms heel-strike registration
  lag (from `threshFzUp`) shrinks true double support into
  *perceived* double support, and 09-08's perceived double support
  (105 ms) had only ~5 ms of margin left over the debounce versus
  09-02's 41 ms (176 ms true DS vs. 132 ms) — measured margin
  sensitivity: 20 ms of extra lag blanks 7% of toe-offs, 30 ms blanks
  32%, 35 ms blanks 59%. A blanked toe-off was then *lost*
  (`isPrevStanceL/R` advanced unconditionally every loop pass, whether
  or not the debounce accepted the transition), stalling `phase` for a
  full stride; a latched gate then carried forward and fired at 50% of
  the *next* stride, and `durGateMaxAge` (2000 ms, longer than one
  stride) let two consecutive stalls carry a gate two strides before
  the expiry guard dropped it — all 4 drops in the 09-08 pilot were
  this expiry case. Ruled out: loop timing (statistically identical
  between the two visits), the encoding regression above (`ardStep`
  climbed cleanly into the 140s), and analog wiring/gain/zeroing (a
  single ~320 N effective threshold, and a swing-phase baseline
  differing by <2 N, explain both visits equally well — a wiring or
  zeroing change could not fit both). Fix (firmware, needs
  re-upload): the debounce now checks only each leg's own
  `timeSinceStanceChange` (see the `timeDebounce` comment in the
  sketch); `isPrevStanceL/R` now advances only when its own debounce
  accepts the transition, so a blanked event is retried next pass
  instead of discarded; `durGateMaxAge` is now `durGateMaxAgeFactor`
  (1.5) times the live `estSS` rather than a fixed 2000 ms, so it
  still tracks genuinely slower clinical strides without needing
  re-tuning; a gate still pending at STOP now echoes a `D` record
  instead of vanishing silently, so the accounting identity (check 2
  below) holds for every trial. Fix (MATLAB, no re-flash): the
  calibration audio cue now plays after the Arduino write, not
  before, so `audioplayer` start latency cannot eat into the gate
  lead; the live `%SS` console readout now divides by `estSSms`
  (same-stride, Arduino clock) instead of `durSSms` (one stride
  stale), which had been inflating the apparent within-stance spread
  the experimenters noticed (true placement sd was 2.4–2.8% in both
  visits; the stale-denominator readout ran 3.9–5.2%); a new
  stride-count-deficit watchdog (distinct from the existing `ardStep`
  regression sentinel, which only catches the counter *decreasing*)
  warns into `datlog.errormsgs` the first time a leg's Arduino step
  count falls behind MATLAB's own, which would have flagged 09-08
  within its first 20 strides. See
  [`diagnostics/auditHreflexStimTiming.m`](../../diagnostics/auditHreflexStimTiming.m)
  (repo root) for a reusable tool that runs this incident's full
  diagnosis — accounting, drop classification, the on-target metric,
  loop timing, and (given the matching C3D) the Arduino stride-count
  deficit, true double support, and toe-off reference error — against
  any saved datlog; it reproduces 0/360 for the 09-02 visit and
  50/333 for 09-08. (The firmware was re-flashed on 2026-09-17; the
  bench bits-to-newtons calibration for `threshFzUp` and a formal run
  of the dry-run checklist remain open — see Validation Before
  Collection.)
- **Near-total stim loss, 2026-09-16 pilot (09-14 fix confirmed never
  flashed):** a participant reported no felt stimulation during
  `CalibrationFast`. `NirsHreflexArduinoOpenLoopWithAudio.m` sent all 132
  gates normally (66/leg, matching the 09-02 good-visit count), but the
  Arduino delivered only 1 and dropped 131, every drop classified as
  expiry, never lateness — `ardStep` reached only 1 (left) / 0 (right)
  across the full 227 s trial, categorically worse than 09-08's partial
  loss. Root cause: the physical Arduino was still running the
  **pre-09-14 firmware** — the per-leg debounce fix above was committed
  but never re-uploaded. This is confirmed directly, not inferred, from
  the gate-to-drop-echo latency: both legs' drops cluster tightly at
  ~2000 ms (the old fixed `durGateMaxAge`), none near the current
  firmware's ~595 ms (`1.5 * estSSLInit`) band. This participant (52.0 kg)
  also loaded the plates markedly more lightly than prior visits (Vicon
  `forces.data` |Fz| p99 ~560 N vs. ~940 N on 09-08 and ~1340 N on 09-02)
  — still above the ~280-320 N effective `threshFzUp` inferred by the
  09-14 fix's own reasoning, so the threshold was not simply unreachable;
  rather, a lower peak force lengthens the heel-strike registration lag,
  shortening *perceived* double support further on top of this
  participant's already-short true double support at fast speed. The
  already-committed per-leg debounce fix directly addresses this
  mechanism; it was simply never deployed. This is not a reason to relax
  the debounce further — the per-leg version is already minimal and was
  not the firmware running at the time. Separately, `datlog.errormsgs`
  was unexpectedly empty despite a deficit large enough that the 09-14
  watchdog (see above) should have caught it almost immediately; reading
  that watchdog's logic found no defect, so the likely explanation is
  that the running MATLAB session had not picked up that fix either
  (stale cached function or an older checkout) — the same "fix committed,
  never deployed" failure as the firmware, on the MATLAB side. **Lesson
  for both sides of the system:** restart MATLAB (clear cached function
  definitions) after every `git pull`, the same way the firmware requires
  a re-upload, and do not assume a committed fix is active without
  runtime confirmation — `diagnostics/auditHreflexStimTiming.m`'s
  firmware-fingerprint check (added after this incident) can provide
  that confirmation from the datlog alone, no C3D required, **but only
  when the trial has drops on either leg** (the fingerprint classifies
  gate-to-drop-echo latency into old-vs-new-firmware bands; with zero
  drops there is nothing to classify and it reports "inconclusive" by
  design — see the 09-17 entry below, where a clean trial could not
  self-certify its own firmware this way). The 2026-09-18 pilot added a
  corollary: commit a changed function and its callers together, and
  never treat a fix written after a trial as having been live for it —
  the Tied Fastest stimulation that day ran on code whose fix was
  committed 16 minutes *after* the trial, and for two hours the
  committed tree could not even regenerate profiles (the generator's
  argument list had changed without its caller).
- **Per-leg debounce fix validated, 2026-09-17 pilot:** the first pilot
  run on a freshly re-flashed Arduino carrying the 09-14 per-leg debounce
  fix, deliberately run as a stress test — a light participant (52.5 kg)
  at fast speed (1.525 m/s) is the exact condition that broke 09-08 (15%
  stride loss) and 09-16 (131/132 gates dropped, unflashed firmware).
  Result: **120/120 gates delivered, 0 dropped, `errormsgs` empty,
  `ardStep` monotonic on both legs** — confirmed with
  `diagnostics/auditHreflexStimTiming.m` and by direct inspection of the
  saved datlog. A direct per-leg cross-check (`diff(ardStep)` vs.
  `diff(matStep)` between consecutive delivered pulses, the same
  comparison the stride-count-deficit watchdog makes internally) found
  exactly one -1 mismatch on **each** leg, at the identical pair of
  echoes on both legs (ardStep +8 vs. matStep +7, ~7.8 s apart) — the
  signature of a rest break, where the Arduino's gait-event state
  machine can register one spurious stance-change while both feet are
  stationary (the exact scenario the EWMA outlier clamp already exists
  to keep out of `estSS`; see the 2026-06-28 fix). Not a genuine dropped
  or duplicated walking stride, and not what the existing deficit
  watchdog would flag (it only warns when the Arduino falls *behind*
  MATLAB, i.e. a positive deficit; this was the opposite sign). MATLAB-
  perceived double support this visit had a median of 49 ms, roughly
  *half* `timeDebounce` (100 ms) — under the old cross-leg debounce this
  would have blanked nearly every toe-off; the per-leg version lost
  nothing. The fix is now validated under a harder condition than any
  prior visit. (`auditHreflexStimTiming`'s firmware
  fingerprint reports "inconclusive" for this trial, as expected for a
  zero-drop trial — see the fingerprint caveat in the 09-16 entry
  above; the behavioral evidence above is the confirmation instead.)
  **Confirmed on the Vicon clock at the 2026-09-18 pilot** (`SAYA90`,
  short-statured, 154.2 cm, 61.6 kg; every walking stim trial captured
  in Vicon with both trigger channels and force plates): trigger-sync
  edges matched every gate on all 15 stim trials (60/60 per calibration
  trial, 100/100 per bout trial, 5/5 on the Tied Fastest trial), and
  the Arduino stride-count deficit was 0 within every walking bout on
  both legs — including the Tied Fastest trial at 1.48 m/s, where true
  (force-plate) double support averaged 65 ms (minimum 46 ms), well
  under `timeDebounce`.

  Two unrelated tooling bugs found in the 09-17 analysis are fixed (no
  firmware change): `Hreflex.plotCal` (labTools) no longer crashes on an
  unsaturated M-wave fit (no third-derivative peak) or a one-leg
  trial's missing fit fields; and `LogForcesArduinoSerial.m`'s
  `readline` timeout guard now reports its real cause — production
  firmware has `logForceData()` commented out, so nothing streams —
  instead of crashing on a `||` non-scalar operand.

  **Stim-timing precision and placement (ground truth, 2026-09-18).**
  Three measures exist and are not interchangeable:
  - *Device-only* `|dtStimMs - estSSms/2|` (the Arduino hitting its own
    target) was 0–1 ms on every trial (mean ≈ 0.5, sd ≈ 0.29 ms, i.e.,
    the `millis()` resolution floor) — indistinguishable from 09-17
    (mean 0.49, median 0.50, max 0.95 ms, n = 120). It says nothing
    about physiological placement.
  - *Stored* `pctSS` (one-stride-stale denominator) is an upper bound
    only: on `CalibrationFast` (0.988 m/s) its sd was 4.4 pp (L) /
    5.6 pp (R), vs. 09-17's 6.4 / 4.2 pp — about twice the true spread.
  - *True* placement, `100 × (stim − single-stance onset) / single-
    stance duration` from the Vicon trigger and force-plate channels
    (the acceptance measure): on `CalibrationFast`, L mean 53.8%, sd
    2.0, median 53.6, IQR 52.8–55.1, range 48.1–58.8 (n = 60); R mean
    54.0%, sd 2.5, median 54.3, IQR 52.9–55.2, range 45.9–61.0 (n = 60;
    Lilliefors normality p = 0.42 L, 0.04 R, so prefer the robust
    summary for R). The spread matches 09-02/09-08 (sd 2.4–2.8 pp), but
    placement is **systematically late**: mean +2.5 to +6.7 pp across
    all 15 trials, only 68–72% of `CalibrationFast` pulses within 50 ±
    5% (every miss late), and 33–57% within it at slow speed.
  - *Cause (measured):* the Arduino's `estSS` exceeds true single
    stance by +19 to +71 ms (larger at slower speed) while its toe-off
    reference is accurate to within a few ms, so firing at `estSS/2`
    lands late by about half that bias. A steady EWMA cannot hold a
    constant positive bias through continuous walking, so this is
    heel-strike registration lag from `threshFzUp` — which settles the
    09-14/09-17 open question and makes the threshold calibration below
    the top timing item after 2026-09-29.
  - *Accounting:* every bout trial showed exactly one gate with no
    echo — always the trial's final gate, whose pulse the Vicon trigger
    channel shows did fire; its echo arrived during the blocking final
    rest and was discarded by the controller's teardown
    `flush(portArduino)`. Since 2026-09-22 the controller drains echoes
    before that flush, so the accounting identity holds exactly.
- **Firmware threshold analysis (2026-09-17, no `.ino` change made):**
  quantified the open bits-to-newtons calibration item below using the
  one archived Arduino bit-domain log
  (`HreflexStimArduino/Troubleshooting_Arduino/force_data.csv`, July
  2025): baseline noise is negligible (sd 0.09 bits, `threshFzDown = 2`
  sits ~20 sd above it), and `threshFzUp = 30` bits is **~25.5% of
  median peak stance force** (117–119 bits), not "~30 bits above
  baseline" as the prior guidance implied — corroborating the 09-14
  entry's inferred 280–320 N effective threshold at roughly 10 N/bit.
  Because the threshold is a fixed bit value, that fraction of peak
  scales inversely with participant weight across visits: ~22% (09-02
  fast, 1377 N peak) to ~54% (09-16, 563 N peak) to ~42% (09-17, 723 N
  peak). At ~54% of peak, heel-strike registration lag grows and
  perceived double support collapses — the same mechanism as the 09-14
  fix, now with numbers attached. **Deliberately not changed this
  pass:** today's flash is the first build validated under the
  fast/light stress case, and any `.ino` edit forces a re-flash and the
  full dry-run checklist below; the threshold change is deferred to land
  together with a genuine bench bits-to-newtons calibration (step known
  loads onto each plate while logging raw bits — see
  `HreflexStimArduino/README.md`), so re-flash/re-validation happens
  once, not twice. Decision rule for that pass: target `threshFzUp` at
  ≤15% of the lightest expected participant's peak stance force, floored
  at ≥10× the bench-measured baseline sd of the *current* plates
  (the archived 0.09-bit figure is 14 months old and `.ino:31-33`'s own
  TODO warns left-plate noise may now be worse), and re-check the
  `estSS`-vs-`durSS` bias above after any change. **Priority raised
  2026-09-18:** the ground truth above measured this bias as the cause
  of late stim placement; lighter paretic-limb loading and slower belts
  in participants with stroke should enlarge it. Kept deliberately
  after 2026-09-29, with its own re-flash and dry run, rather than
  changing a validated flash the week of the first outside
  participant.
- **Date/time modernization (2026-07):** `now`/`datestr`/`clock`/`etime`
  calls in `NirsHreflexArduinoOpenLoopWithAudio.m` were replaced with
  `datetime`/`char`/`tic`-`toc` equivalents to clear MATLAB Code
  Analyzer warnings, with no change to trial behavior, timing, or the
  saved datlog. Two categories are deliberately left as-is with a
  `%#ok` suppression rather than converted: (1) the hot-path fields
  that store a raw serial date number consumed by in-loop datenum
  arithmetic (`RTOTime`/`LTOTime`/`RHSTime`/`LHSTime`, `stim.{L,R}`
  GateSendTime, `commSendTime`, `messages`, `framenumbers`/`forces`/
  `stepdata`/`TreadmillCommands` "U Time" columns, and `buildtime`) —
  converting the call would either change the stored type or add a
  per-frame `datetime` construction cost to the stim control loop; and
  (2) the teardown `etime(datevec(...))` relative-time columns that
  labTools' `SyncDatalog` reads in seconds, where a `datetime`-based
  replacement was measured to differ by up to ~5e-5 s from the
  original — small, but not the bit-identical match those columns
  need. Genuine storage-format modernization for both is deferred to a
  coordinated ExperimentalGUI + labTools change.

## Validation Before Collection

The controller logs per-iteration loop timing and gate lead time to the
additive `datlog.diagnostics` field. Before participant collection,
confirm:

- **0 missed stims** — intended stims (count of `1`s in the `stimL` /
  `stimR` profile columns) equal delivered pulses (Vicon-recorded
  Arduino trigger count). *Met 2026-09-18 (all 15 stim trials).*
- **Tight stim timing** — stimulus fires near 50% of single stance;
  check the distribution from labTools `computeHreflexParameters`
  (`stimTimeFromSingleStanceSlow/Fast`). *Reopened 2026-09-18:* first
  measured on the Vicon clock, placement is consistently late (mean
  ~54% at fast walking; ~30% of pulses outside 50 ± 5%, more at slow
  speed) — see the stim-timing entry above; fix via the `threshFzUp`
  calibration after 2026-09-29.
- **Loop timing** — review `datlog.diagnostics.loopSegMs` (median, p95,
  max) and `gateLeadMs*` (positive = gate arrived that many ms *before*
  single-stance onset; expect roughly a double-support duration of lead).
- **Arduino stride-count deficit = 0 within every walking bout** — each
  leg's Arduino `ardStep` increment between consecutive delivered
  pulses should equal how many true strides actually elapsed (from the
  C3D force plates). This is the load-bearing check for the 2026-09-14
  failure mode above: it is not caught by loop timing or by the
  pre-existing `ardStep`-decreased sentinel, since the counter still
  increases, just too slowly. Gaps that span a rest break are reported
  separately and excluded: standing weight shifts can register a
  spurious stance change on either side, in either direction (±1–5 per
  trial on 2026-09-18), which is not a walking stride. *Met 2026-09-18
  (0 on every leg of all 15 trials).*
- **Double-support margin — resolved 2026-09-18; now a reported
  diagnostic, not an acceptance criterion.** The old rule (true double
  support ≥ `timeDebounce` + ~40 ms) was derived for the *cross-leg*
  debounce. With the per-leg debounce, 2026-09-18 delivered every gate
  with 0 within-bout deficit at a true (force-plate) double support of
  99 ms mean on `CalibrationFast` (about half the intervals < 100 ms)
  and 65 ms mean (minimum 46 ms) on the 1.48 m/s Tied Fastest trial, so
  short double support no longer predicts failure; the within-bout
  deficit above is the acceptance check.
- **Bench check** — run `HreflexStimArduino/LogForcesArduinoSerial.m`
  (see that folder's README for the firmware prerequisite) and confirm
  the printed baseline-noise-to-`threshFzUp` margin is clean and stance
  excursions cross `threshFzUp` reliably before trusting the state
  machine's event detection in a live trial.

[`diagnostics/auditHreflexStimTiming.m`](../../diagnostics/auditHreflexStimTiming.m)
runs the missed-stims, stim-timing, loop-timing, and (given the matching
C3D) stride-count-deficit and double-support checks above in one call
against a saved datlog — see its help text for the full check list and
output fields. It splits the stride-count deficit into within-bout and
rest-spanning gaps (using each pulse's gate step and the profile's rest
pads), flags the known teardown signature (one unaccounted gate, the
last, sent after the last echo; fixed for datlogs from 2026-09-22 on),
and needs the Statistics and Machine Learning Toolbox (`prctile`).

### Dummy-Profile Dry Run (treadmill only, no participant)

Run this after any change to the serial encoding or firmware timing
guards (e.g., the 2026-08-06 or 2026-09-14 fixes above), before the next
pilot or participant visit. **Re-flash the Arduino first** if the
firmware changed — see `HreflexStimArduino/README.md`'s upload workflow
(COM4).

**Setup**

- [ ] Upload the current firmware; bench-check per
      `HreflexStimArduino/README.md`'s "Validating Stim Timing" step 2,
      including the outlier-clamp and drop-guard checks.
- [ ] DS8R output disconnected or intensity at zero. The Vicon sync
      pins stay live regardless, so echoes and sync pulses are still
      produced — full end-to-end timing validation with nothing
      delivered to a person.
- [ ] Dummy profile: ~40 tied strides at the slow calibration speed,
      stim on every 2nd stride; then repeat with stim on **every**
      stride (the `CtrlBouts` pattern that exposed the original 35%
      loss on the left leg, and the harder test).
- [ ] Repeat both dummy-profile runs at the **fast** calibration speed
      — fast walking is the stress case for double support (see the
      2026-09-14 fix above) and the slow-speed runs alone would not
      have caught it.
- [ ] Experimenter walks on the treadmill for each run; for at least one
      fast run, use a **light or short-statured** experimenter (short
      double support) rather than whoever is tallest/heaviest available,
      to reproduce the condition that exposed the 2026-09-14 bug.

**Acceptance** (load the saved `datlogs/*.mat` after each run). Checks 2-3
reference `stim.deviceDrop`, which exists only in datlogs collected with
this fix (2026-08-06 or later) — guard with
`isfield(datlog.stim,'deviceDrop')` if comparing against an older log
(e.g., the 2026-08-05 pilot files), which predate the field entirely.

1. **`ardStep` climbs monotonically per leg into the tens.** The
   load-bearing check: the direct regression test for the encoding bug,
   and proof that exactly one byte went out per command. Any `{0, 1}`
   pattern means the fix did not take.
2. **Full accounting:** `size(stim.L,1) + size(stim.R,1)` equals
   `size(stim.deviceEcho.data,1) + size(stim.deviceDrop.data,1)` — no
   gate unexplained. (Datlogs before 2026-09-22 come up one short on
   every bout trial — the final gate's echo was lost at teardown; the
   audit tool flags that case.)
3. **`stim.deviceDrop` is empty.** If not, the firmware's lateness or
   gate-expiry guard fired — read the dropped rows' `dtStimMs` for how
   late. Empty here isolates the encoding fix (check 1) from the
   firmware guards (this check).
4. **Zero missed pulses:** `size(deviceEcho.data,1)` equals the number
   of `1`s in the profile's `stimL`/`stimR` columns for strides walked.
5. **On-target timing:** `abs(dtStimMs - estSSms/2) <= 5` for every
   delivered row, and `pctSS` within 50 ± 5%.
6. **`gateLeadMs*` all positive**, roughly a double-support duration.
   Negative or near-zero means the gate is arriving at onset rather
   than during the preceding double support.
7. **Loop timing unchanged:** `diagnostics.loopSegMs` median and p95
   comparable to prior pilots (median ~10-11 ms, p95 ~70-90 ms). The
   added logging must not touch the hot path's cost.
8. **Stop actually stops** (new behavior — command `3` previously
   self-cancelled via the same encoding bug): after STOP, confirm no
   further echoes arrive and the Arduino's stim/Vicon pins read LOW.
9. **Arduino stride-count deficit = 0 within bouts**, at both slow and
   fast speed. The direct regression test for the 2026-09-14 fix: run
   `diagnostics/auditHreflexStimTiming.m` against the dry-run datlog
   with the matching C3D and confirm `strideDeficit` (within-bout) is 0
   for both legs.
10. **Report true double support** on the fast-speed runs (same tool,
    `groundTruth.doubleSupportMs`) as a diagnostic; it is no longer an
    acceptance threshold (see Validation Before Collection above).

The Vicon-sync placement test (`100 × (stimVsync − RTO) / (RHS − RTO)`
on the Vicon clock, target 50 ± 5%; `HreflexStimArduino/README.md`
acceptance steps 4-5) was first run on 2026-09-18 and failed for ~30%
of pulses at fast walking, all late (see the stim-timing entry above).
**Still unvalidated:** a live lab dry run of the H-Reflex M-Wave
Monitor tool (below) — it is replay-validated against real prior
calibration data but not yet run live in the lab.

## Study History

| Archive folder | Description |
|---|---|
| `History-PilotStudy1/` | Original pilot — simpler tied/split structure; no fNIRS bout design. Scripts: `SpinalAdaptProtocol.m`, `GenerateProfileSpinalStudy.m`. |
| `History-PilotStudy2/` | Bout-based protocol — participants SABH01 through at least SABH16+ (July 2023–2025). Speed ratio changed from 0.5 to 0.7 after SABH16 (July 2024); ramp-to-split option added then later removed. Scripts reformatted to CLAUDE.md style (June 2026). |

2026-08-13 redesign of the active files (this folder's current templates,
not yet archived): ramp strides per bout reduced 10 → 3; bout-start cue
simplified from a 3-2-1 countdown to a single "Walk"; belt-stop cue
simplified to `stopAndRest.mp3` only, no countdown; inter-trial break
reduced from ~150 s to ~90 s wall clock; `TMBaselineFast/Slow` and
`OGBaselineFast/Slow` profiles and the `baseOnly` generator mode removed
(the fast/slow leg assignment they supported is now a direct
`fastLeg` input rather than derived from a TM baseline trial).

The active files in this folder are templates for the next protocol version.
Initial protocol design is incorporated (bout structure described below);
verify all parameters against the final approved protocol before collection.

## Key Scripts

| Script | Status | Purpose |
|---|---|---|
| `RunProtocol_SpinalAdaptBouts.m` | Template | Main protocol runner |
| `generateProfiles_SpinalAdaptBouts.m` | Template | Speed and stim profile generator |
| `generateProfile_SixMinuteWalk.m` | Active | Speed-independent 6MWT profile generator |
| `runWalkingCalibrations.m` | Active | H-reflex walking calibration helper |
| `transferData_SpinalAdaptBouts.m` | Active | Data transfer and archival |

## H-Reflex Electrode Placement

At the start of each visit, before the H-reflex walking calibrations,
find the stimulating bar electrode's site over each leg's tibial nerve
with
[`HreflexMappingTool`](../../HreflexMappingTool/README.md) (repo root).
Run it once per leg, in a MATLAB instance separate from the one
running `RunProtocol_SpinalAdaptBouts`. It fires single DS8R pulses
through the Digitimer COM API, so no controller should be stimulating
while it runs. When prompted for a parent folder, choose this visit's
Vicon Nexus folder
(`...\SpinalAdaptStudy\<participant ID>\Visit0N`). Each visit's
`LeftNerveLocalization/` and `RightNerveLocalization/` logs and Center
figures then stay with that visit, and `transferData_SpinalAdaptBouts`
copies them to the server with the rest of that folder (under
`Data\<ID>\Visit0N\Vicon\`). The tool leaves the DS8R output disabled
and its `Demand`/`PulseWidth`/`DemandLimit` settings changed. Check
both DS8Rs and re-enable their output before the calibrations. See that
folder's README for the procedure, outputs, and open lab checks.

## H-Reflex M-Wave Monitor

A near-real-time M-wave monitor helps the experimenter hold each leg's
H-reflex M-wave within ~±10% of its calibration baseline during a
visit by watching a live plot and adjusting DS8R current
accordingly. It runs in a **separate MATLAB instance** from this
study's control/stimulation instance, so it cannot perturb
`NirsHreflexArduinoOpenLoopWithAudio`'s control-loop timing.

Built for SpinalAdapt, the tool now lives outside this folder, at
[`HreflexMwaveMonitor/`](../../HreflexMwaveMonitor/README.md) (repo
root), since H-reflex measurement may not stay unique to this study —
see that folder's README for the full file list, phase status,
real-data validation results, and known gaps.

## H-Reflex Calibration Processing

After each walking dynamic H-reflex calibration trial, a Vicon Nexus
2.12 processing pipeline automatically runs
`labTools/fun/misc/GenerateHreflexRecruitmentCurves.m`. This script
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

**The Nexus pipeline, `GenerateHreflexRecruitmentCurve`, is currently
broken** (reported after the 2026-09 dry run). It runs three steps —
**Combined Processing**, **Save Trial - C3D + VSK**, then **Run MatLab
Operation** — and fails at the last step, **Run MatLab Operation**.
Since the first two steps succeed (the C3D/VSK files are produced),
the fault is isolated to how that step invokes MATLAB, not to trial
processing or file export. The pipeline config and the script itself
both live outside this repo, so there is nothing here to patch
directly. To diagnose on the lab PC:
1. Open `GenerateHreflexRecruitmentCurve` in Nexus's Pipeline tool and
   inspect the **Run MatLab Operation** step's configured script
   name/path (and working directory, if set).
2. Compare that against the real file at
   `C:\Users\cntctsml\Documents\GitHub\labTools\fun\misc\` — confirm
   the current filename/casing there (`GenerateHreflexRecruitmentCurves.m`,
   PascalCase; prior documentation here incorrectly used camelCase).
3. Run that step manually (or the whole pipeline) on a saved
   calibration trial and read the exact MATLAB/Nexus error —
   "undefined function"/"not found" points to a stale name left over
   from a prior rename, while a path-not-found or "cannot start
   MATLAB" error points to a broken MATLAB executable/working-directory
   reference in the step's own configuration — then update the
   pipeline's script reference (or MATLAB path config) to match.

**Until the pipeline is fixed, run the script manually** after each
calibration trial's C3D is saved (in MATLAB, run
`GenerateHreflexRecruitmentCurves`; with Nexus not driving it, it asks
for the C3D via a file dialog). That pipeline-step fault is separate
from the script crash below.

**Script crash with the full muscle list (2026-09-18, fixed
2026-09-22).** Entering all 7 muscles per leg (`RF`, `VL`, `BF`, `TA`,
`PER`, `LG`, `SOL`) crashed the script ("Index exceeds the number of
array elements. Index must not exceed 3."). Its muscle list had been
trimmed to the lower-leg muscles, so an unrecognized name fell into
the re-entry prompt's `'sync'` check, which read the name's first four
characters — past the end of any 3-letter name such as `RRF`. The
script now uses labTools' full muscle list (as `loadTrials.m` does)
and a short-name-safe check; the 09-18 workaround (every sensor except
SOL/TAP entered as `NA`) is no longer needed. Validated headless on the
real script: the full list now runs with results identical to the
workaround's, and `SABH02` `Trial03` is unchanged. (`loadTrials.m:196`
has the same latent `(1:4)` check but never reaches it, since its list
already includes the thigh muscles.)

**`+Hreflex` functions called by this pipeline** (all in
`labTools/fun/+Hreflex/`):

| Function | Role |
|---|---|
| `extractStimArtifactIndsFromTrigger` | Locate the artifact peak in a window anchored to each trigger pulse |
| `plotStimArtifactPeaks` | Plot detected peaks for QC |
| `extractSnippets` | Extract per-pulse EMG windows |
| `plotSnippets` | Plot per-pulse snippets for QC |
| `extractBackgroundEMG` | Compute pre-stimulus background level |
| `computeAmplitudes` | Peak-to-peak M- and H-wave amplitudes |
| `fitCal` | Fit recruitment curves to amplitude vs. current |
| `plotNoiseHistogram` | Plot background EMG noise distribution |
| `plotCal` | Plot fitted recruitment curves |

### Collection-Side Prerequisite: Trigger Sync Channels

The trial **must** record the two stimulator trigger sync channels
(`Stimulator_Trigger_Sync_Right_Stimulator` and
`Stimulator_Trigger_Sync_Left__Stimulator`, 0 → ~4.3 V). They anchor a
±100 ms search window around each pulse — wide enough to span the
~50 ms Delsys wireless EMG transmission delay — and that anchoring is
what makes artifact localization reliable. Without them the script has
to search the whole trial blind. **Confirm the channels appear in the
Vicon Nexus analog device configuration before collection: the
`HreflexEMGDataCollection` system/pipeline profile must be selected in
Nexus for these trigger channels to be recorded.** The
2026-08-21 dry run's C3D had neither, and the script silently degraded;
it now stops and asks (Abort / Continue with threshold detection)
instead.

### 2026-08-21 Dry Run: Findings and Fixes (2026-08-26)

That calibration trial produced no recruitment curves. Four
independent causes, all now fixed:

1. **`Hreflex.plotStimArtifactPeaks` crashed at both call sites** — the
   one `+Hreflex` function never migrated to an `arguments` block, so
   it parsed the script's name-value pairs positionally. Converted; it
   now also accepts `labels` (the artifact muscle per leg) and
   `isWeak`, which draws flagged stimuli as red circles.
2. **The artifact is negative-dominant** — a sharp downward deflection
   with a smaller positive rebound ~1.5 ms later. Both localization
   paths searched for a signed-positive peak above a 1 mV height gate,
   so they either locked onto the rebound or, when the artifact was
   small, found nothing and fell back to the raw maximum over a 200 ms
   window. Both now take the largest **absolute** deflection from the
   window median. This was never dry-run-specific: SABH02 `Trial03`
   is negative-dominant too (|min|/max ≈ 2.0 on both TAP channels) and
   worked only because a larger artifact made the rebound clear 1 mV.
3. **No trigger sync channels** (see the prerequisite above).
4. **Only the left leg was stimulated**, but the script required
   RTAP/LTAP/RSOL/LSOL and assumed two legs throughout. A leg is now
   analyzed only if stimulation amplitudes were entered for it —
   **leave a leg's amplitude field blank when it was not stimulated**
   — and every figure, fit, and curve is per leg.

Also changed in that pass:

- **Muscle selection.** Two new dialog fields (appended, so older
  config files are padded with defaults rather than rejected): the
  H-reflex muscle (default `SOL`) and the artifact localization muscle.
  Since 2026-09-22 the artifact muscle defaults to `TA` and resolves
  per leg through the tibialis anterior family — the requested name
  first, then `TAP`, `TA`, `TAD` — before falling back to the H-reflex
  muscle, printing the channel used per leg. A visit that records a
  single `RTA`/`LTA` channel and a historical one with `RTAP`/`RTAD`
  both work from either entry; no channel is renamed.
- **Artifact threshold is now a quality control floor, not a gate**,
  in both paths: a stimulus below it is flagged and drawn in red, not
  discarded. On the dry run a 0.3 mV gate excluded 3 of 60 real
  artifacts. Without a trigger pulse the script instead ranks
  candidate deflections by size and keeps the number of stimuli
  entered, which located all 60.
- **Per-leg QC summary** printed to the console: stimuli located vs.
  expected, median peak artifact, and flagged count. This is how a
  dead leg reads at a glance — the dry run's right SOL peaked at
  0.047 mV against the left leg's 3.5 mV.
- **Config files shrank from ~200 MB to <1 KB** — the analog data and
  the BTK handle are no longer saved alongside `answer`, which is all
  that is ever loaded back (SABH02 had ≈1.4 GB of them).
- Default minimum time between stimulation pulses lowered from 5 s to
  1 s: at most one stimulus per stride per leg, and a stride is ≳1 s.
  At 5 s the fallback could not resolve the dry run's ~3.5 s per-leg
  interval.

**Verified.** On SABH02 `Trial03` (known-good reference) the new
localization keeps all 60 stimuli per leg, shifts every index 1.5 ms
earlier (max 2.0 ms) onto the artifact's initial deflection, and moves
mean M-wave amplitude by −0.23% (right) and +0.57% (left). On the dry
run trial the script now runs to completion: 60/60 left-leg stimuli
located, 3 flagged weak, M-wave fit R² = 0.98, plateau ≈3.3 mV.

**Still open, not addressed:** on that trial the left M-wave trough
lands at ~18.5 ms, close to the 20 ms edge of `computeAmplitudes`'
M-wave window, and the 20–25 ms "noise" window rides the M-wave tail
so noise amplitude tracks M amplitude (up to ~1.7 mV). The window
definitions were left alone; revisit them separately.

## Hardware

H-reflex stimulation requires an Arduino Uno running the firmware in
`HreflexStimArduino/`. See
[HreflexStimArduino/README.md](../../HreflexStimArduino/README.md)
for the upload procedure, wiring diagram, and pre-experiment
checklist.

## See Also

[EXPERIMENT_SETUP.md](../../EXPERIMENT_SETUP.md).
