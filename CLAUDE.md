# CLAUDE.md — ExperimentalGUI Repository Instructions

## Architecture

### Entry Point & User Input
`AdaptationGUI.m` is a MATLAB GUIDE GUI (requires its companion `.fig`).
On launch it initializes global state (see Key Patterns), audio players,
and keyboard polling. The experimenter selects a speed profile and
controller type via popup menus, then clicks Execute.

`Execute_button_Callback` reads these selections, loads the corresponding
speed profile vectors (`velL`, `velR`), and calls the selected controller
function, passing the profiles as arguments.

### Data Loading Pipeline
Speed profiles (`velL`, `velR`) are Nx1 column vectors in **m/s**
generated and saved to disk by `generateProfiles_*` scripts inside each
study's folder. `Execute_button_Callback` converts to mm/s
(`round(velL*1000)`) only at the call-site boundary, immediately before
passing the profiles as arguments to the selected controller function —
controller functions themselves receive and operate on mm/s. A NaN value
at position k means stride k is self-paced (the controller holds or
queries treadmill speed rather than applying a predetermined value).
There is no file-based loading at runtime beyond this load-and-convert
step.

### Processing Pipeline
Every controller function follows the same template:

1. **Initialize** — open Vicon (`NexusGetFrame`) and treadmill
   (`sendTreadmillPacket`) connections, allocate the `datlog` struct,
   create animated-line plots for real-time feedback.
2. **Main loop** (`while ~STOP`) — each iteration:
   - Poll Vicon: `NexusGetFrame` → extract ankle/hip/pelvis marker
     positions and velocities.
   - Detect gait events: heel strike via `FindKinHS` (local maximum of
     limb angle); toe-off via vertical marker velocity / force-plate Fz
     threshold.
   - On ipsilateral toe-off: advance the profile index, call
     `getPayload` to format the 64-byte treadmill packet, send via
     `sendTreadmillPacket`.
   - Append event timestamps and kinematic parameters to log arrays.
3. **Teardown** — on STOP: save `datlog` as a timestamped `.mat` file
   to `datlogs/`, then call `utils.transferData` to archive to the
   server.

### Key Patterns

**Global flags** — All controllers declare `global STOP PAUSE` at the
top. Do not shadow these with local variables. Other globals (`SSspeed`,
`SSstdev`, `addLog`, etc.) carry state shared with the GUI.

**Profile index** — advances once per stride (on ipsilateral toe-off).
A NaN at position k means stride k is self-paced; the controller holds
or queries treadmill speed rather than commanding a preset value.

**Treadmill hard limits** — enforced by `getPayload` (treadmill comm
layer on `C:\Users\Public\Documents\MATLAB\`): speed ±6500 mm/s,
acceleration ≤ 3000 mm/s².

**datlog fields** — top-level struct fields (not to be confused with a
controller's own args/outputs, e.g. `RTOTime`/`commSendTime`, which are
separate): `buildtime`, `session_name`, `errormsgs`, `messages`,
`framenumbers.data` (frame #, U Time, Relative Time), `forces.data`
(frame #, U Time, Rfz, Lfz, Relative Time), `stepdata.{RHS,LHS,RTO,
LTO}data` (Step#, U Time, frame #, Relative Time), `inclineang`,
`speedprofile.{velL,velR}`, `TreadmillCommands.{read,sent}` (RBS, LBS,
angle, U Time, Relative Time) and `.firstSent`, `audioCues`,
`stim.{L,R}` (Step#, StimDelayTarget(ms), GateSendTime) plus the
additive `stim.deviceEcho`, `stim.deviceDrop`, and `diagnostics`
fields (see the H-reflex timing contract below). Saved to
`datlogs/<timestamp>_<profile>.mat` on STOP. For a consolidated
per-frame view (belt speeds, gait events, stim gate flags joined onto
one timetable), see `utils.buildDatlogFrameTable` — a read-side
helper computed on demand, not a field stored in the log.

See [EXPERIMENT_SETUP.md](EXPERIMENT_SETUP.md) for the controller
reference table and protocol creation guide.

## Active Studies

**BrainWalk** — longitudinal (visits 1 year apart); lead
experimenters: Shuqi Liu, Jiwon Choi. Do not make functional changes
to `studies/BrainWalk/BrainWalkProtocol.m` or the controllers it
calls: `OGNBackTask`, `NirsAutomaticityAssessment`,
`controlSpeedWithSteps_edit1_AudioCountDown`, `HreflexOGWithAudio`.
Style/formatting edits are acceptable; logic changes are not.

**C3** — active (~3 participants remaining; est. completion July 2026).
Lead: Nate Brantly (doctoral thesis); co-experimenter: Anna Annello.
Functional changes require care; consult the user before modifying
protocol scripts.

**SpinalAdapt** — rebooting; data collection begins 2026-09-29 (the
first outside participant, with stroke). Lead: Chase Rock
(post-doctoral fellow); key experimenters: Shuqi Liu, Nate Brantly.
Primary protocol: `studies/SpinalAdapt/RunProtocol_SpinalAdaptBouts.m`.
The study lead prefers **"visit"**, not "session", in SpinalAdapt
comments, variable names, and documentation. Every participant —
young adult `SAYA##`, stroke `SAST##`, matched control `SAMC##`
(`SABH##` = Pilot Study 2 and earlier) — completes two visits; the
visit participant ID adds `_V01`/`_V02` (e.g., `SAST01_V01`), and the
Vicon Nexus, Oxysoft, and server visit folders are `Visit01`/`Visit02`
inside the participant-ID folder. The fast belt carries the dominant
(young adult) / non-paretic (stroke) / matched (matched control) leg
in Visit 1 and the other leg in Visit 2. The protocol script asks for
the visit participant ID and fast leg by dialog (never edited into the
file) and confirms the leg; Visit 1 runs the overground 6-minute walk
test first (its speed sets every other trial's belt speed) and
generates every profile, including both fast-leg split profiles
(`AdaptSplitFastR.mat`/`AdaptSplitFastL.mat`), into a profile folder
both visits share; Visit 2 skips both and loads them. Conditions: a
tied fastest-speed trial, then pre-adaptation, adaptation, and
post-adaptation bouts, with a fixed ~2.5 min break after every
bout-based condition except the last; every fNIRS event
`NirsHreflexArduinoOpenLoopWithAudio` logs to Oxysoft is prefixed with
its condition (e.g. `PreAdaptSlow_Rest01`), and its "stop" cue plays on
each bout's last step, about half a stride before the belts stop (the
rest timing after it is unchanged) — see `studies/SpinalAdapt/README.md`'s
Protocol Notes. There is no fNIRS or H-reflex during the tied
fastest-speed trial, so it does not use that controller at all: it
runs on the plain `controlSpeedWithSteps_edit1_AudioCountDown` (slot
11, shared with C3/BrainWalk), which gives it its own spoken
"treadmill will start/stop in 3-2-1" countdown instead of the usual
cues. `transferData_SpinalAdaptBouts(participantID, visitNum,
threshTime)` copies each visit to `W:\Chase\SpinalAdapt\`
(`Data\<ID>\SpeedProfiles`, shared; `Data\<ID>\Visit0N\...`;
`RawBackupData\<ID>\Visit0N\...`). H-reflex stimulation timing is
controlled by an Arduino Uno running
`HreflexStimArduino/triggerStimWithGaitStateMachine_SpeedIndependent/`
(see `HreflexStimArduino/README.md` for upload and wiring details). Do
not change the serial command protocol in MATLAB controllers without
re-uploading compatible Arduino firmware.

**H-reflex timing contract** — `NirsHreflexArduinoOpenLoopWithAudio`
paired with firmware `triggerStimWithGaitStateMachine_SpeedIndependent`
is the authoritative, Arduino-timed path. The deprecated
`NirsHreflexOpenLoopWithAudio` (`controllers/Deprecated/`, paired with
`Dual_Stim_Matlab.ino`) is a frozen bench/emergency fallback only — do
not extend it or treat it as a starting point. The Arduino runs its
own gait state machine and fires locally at 50% of an EWMA-estimated
single-stance duration (`alpha = 0.70`, each candidate clamped to
100-1000 ms before the update to reject doubled/missed detections);
MATLAB mirrors the same alpha and clamp in its diagnostics EWMA — do
not change either without re-validating in the lab. Per stride, MATLAB
sends only a gate byte (`1` = stim left, `2` = stim right) during the
double support phase immediately preceding single-stance onset (never
at onset or mid-stance — early is always safe, late risks a missed or
mistimed stim) and owns the start (`0`)/stop (`3`) handshake; this
inbound `0`/`1`/`2`/`3` protocol is frozen with the firmware — do not
change it without re-uploading compatible firmware. The protocol is
frozen at **one byte (`uint8`) per command**, not just at these four
values: MATLAB must send with `write(portArduino,cmd,'uint8')`, since
a wider precision pads a trailing zero byte that the firmware reads as
a spurious extra command `0` (`resetStateMachine()`) one loop pass
later — this was the root cause of the 2026-08-05 pilot's missed and
wrong-stride stims (see `studies/SpinalAdapt/README.md`). The firmware
additionally drops (does not fire) a gate that is still pending well
past its 50% target or whose expected single-stance onset never
arrives, and echoes each delivered pulse's or dropped gate's actual
timing back over serial (`echoStimRecord`, tagged `S`/`D`); MATLAB
logs this one-way, informational echo to the additive
`datlog.stim.deviceEcho` (delivered) / `datlog.stim.deviceDrop`
(dropped) fields as a lab ground-truth check — neither feeds the
firing decision. MATLAB also watches the echoed Arduino-side step
counter (`ardStep`) for a decrease, the direct signature of an
unintended state-machine reset, and warns once per leg into
`datlog.errormsgs` if it happens; at teardown it drains any
still-waiting echoes before flushing the port, so the accounting
identity (gates = delivered + dropped echoes) holds exactly. An
explicit all-zero `stimL`/`stimR` schedule means no stimulation; only
a profile with no stim variables at all gets the controller's legacy
every-10th-stride default (the 2026-09-18 Tied Fastest trial was
stimulated through that default). Keep display work off the control
loop's hot path. See `studies/SpinalAdapt/README.md` for the full
timing history, root-cause note, display-pattern detail, the measured
(slightly late) stim placement, and the dummy-profile dry-run
checklist.

**H-reflex M-wave monitor** — a companion tool, `HreflexMwaveMonitor/`
(repo root; the `+hreflexMonitor` namespace — see Code Style below),
built for SpinalAdapt but kept study-agnostic since other studies may
adopt H-reflex measurement later. Must keep running in its own
**separate MATLAB instance** with its own Vicon DataStream client
(device data only): it must never open the Arduino serial port or
write to `datlog`, since that would perturb the control loop above.
`detectStimArtifactOnline` is a causal re-implementation of (not a
call into) the offline `Hreflex.extractStimArtifactIndsFromTrigger`,
pinned by a replay parity test; `stepHreflexMonitor` recomputes
amplitudes over the full accumulated snippet set per new stimulus
(not per-stimulus) because `Hreflex.computeAmplitudes`' outlier
correction is a population statistic. See
`HreflexMwaveMonitor/README.md` for phase status, file list, and
real-data validation results.

**H-reflex mapping tool** — `HreflexMappingTool/HreflexMappingTool.m`
(repo root; a single script with local functions, no namespace) finds
the bar-electrode site over the tibial nerve: per site (Center / Left
/ Up / Right / Down) it fires one DS8R pulse through the Digitimer COM
API, detects the artifact on raw TA EMG (there is no sync channel),
and plots TA and Soleus with automatic M-wave/H-reflex peaks and
latencies in a plus-shaped figure layout. Used in SpinalAdapt once per
leg each visit, before the walking calibrations, but kept
study-agnostic. Run it in its **own MATLAB instance** (it starts with
`clearvars; close all`); it never touches the Arduino serial port or
`datlog`. Keep its safety rules: confirm dialog with no default button,
a software current cap, and DS8R output disabled between trials and on
any exit (its session runs in a local function so `onCleanup` fires on
error/Ctrl+C). Its CSV columns and MAT `trials`/`session` fields are a
saved format — keep them stable. Claude cannot run its Vicon/DS8R
path, so every change needs lab verification. See
`HreflexMappingTool/README.md`.

**NirsAutomaticityProtocol**, **Perceptual Adaptation**, and **Weber
Perception** — completed; consult the lead experimenter (see
EXPERIMENT_SETUP.md for study leads) before modifying scripts in these
folders.

## MATLAB Version Compatibility
All code must be compatible with MATLAB R2021a through the current
release.

## Code Style Requirements
- Wrap lines at 76 characters
- Use spaces around `=` and binary comparison operators
- No brackets around a single output: `out = func()` not `[out] = func()`
- Suffix no-argument method calls with `()`: `obj.method()` not
  `obj.method`
- Use an `arguments` block when it meaningfully constrains input type/
  size or replaces a `nargin` check with a declared default. Place it
  immediately after the documentation comment. Default values must be
  compile-time constants — compute argument-dependent defaults in the
  function body. Multiline validators indent to align with the argument
  name (see CONTRIBUTING.md for full examples).
- camelCase for function files, PascalCase for scripts. Do not rename
  existing files. Choose descriptive variable names; abbreviations are
  acceptable when unambiguous (`tbl`, `fig`, `lme`, `pval`).
- Namespace (`+package`) folder names: camelCase, matching the
  repository root's own `+utils` precedent (e.g. `+hreflexMonitor` in
  `HreflexMwaveMonitor/`) — distinct from labTools' own `+Hreflex`
  (PascalCase) namespace convention, which this repository does not
  follow. Reach for a namespace when a tool's functions are numerous
  enough, or likely to grow or be reused across studies enough, that
  grouping and collision-avoidance are worth the `package.function(...)`
  call-site cost; a handful of one-off, study-specific helper functions
  do not need one.
- Do not use `i` or `j` as loop indices (reserved for imaginary unit).
  For stride loops use `st`; for generic enumeration use `ii`, `jj`,
  `kk`. Preferred short names: `mscl`, `mrkr`, `lbl`, `tr`, `con`,
  `fp`, `ch` (see CONTRIBUTING.md's Naming Conventions table for
  meanings). Never use `iMuscle`-style names.
- Do not indent the base level of code inside functions
- Align `=` within a group of closely related assignments
- Write `0.5` not `.5`
- Use `mean(x, 'omitnan')` not `nanmean(x)` (similarly for `median`,
  `std`, `sum`). For `min`/`max`: `min(x, [], 'omitnan')`.
- Define unexplained numeric literals as named constants (camelCase)
  with an end-of-line comment giving their source or rationale.
- Prefer `fullfile(...)` over string concatenation with `filesep`:
  `fullfile(dir, 'file.mat')` not `[dir filesep 'file.mat']`

### Arduino / C++ (`.ino` files)

See CONTRIBUTING.md "Arduino / C++ Code Style" for full examples.

- **Naming** — camelCase for mutable variables and functions;
  camelCase for typed `const` variables (e.g., `threshFzUp`,
  `pinInFzL`); UPPER_SNAKE_CASE for `#define` macros and `enum`
  constants.
- **Serial protocol command bytes** — define as named `const int`
  with an end-of-line comment; bytes are frozen per the H-reflex
  timing contract — do not change without re-uploading firmware.
- **Brace style** — Allman: opening `{` on its own line for all
  functions, `if`, `for`, `while`, and `switch`.
- **Indentation** — 2 spaces (Arduino IDE default).
- **Line length** — 76 characters, same as MATLAB.
- **File header** — required `//` block: filename, one-line
  description, longer description if needed, date started, authors.
- **Function comments** — a `//` comment block immediately above
  each non-trivial function describing its purpose; the section
  separator `// --- Name ---` alone suffices for trivial ones.
- **Numeric literals** — write `0.5` not `.5`; trailing zeros
  (e.g., `0.50`) are not required.
- **Loop variables** — `i` and `j` are acceptable in C++ (no
  imaginary-unit concern; the MATLAB restriction does not apply).
- **Named constants** — same rule as MATLAB: unexplained numeric
  literals must be `const` with an end-of-line source comment.

## Documentation Comments
Every function requires a standard doc block after the definition line.

**H1 line** — immediately after `function`, no space between `%` and
the function name; name in ALL CAPS:
```matlab
%MYFUNCTION Compute stride-by-stride parameters from GRF data.
```

**Description** — one blank comment line after H1; first line indented
three spaces, continuation lines one space.

**Inputs / Outputs** — use separate `% Inputs:` and `% Outputs:`
headers; list each argument as `%   argName - description`; blank
comment line between the two headers.

**Toolbox Dependencies** — list required toolboxes; `None` if only
core MATLAB.

**See Also** — ALL CAPS for clickable hyperlinks:
`% See also RELATEDFUNCTION, ANOTHERFUNCTION.`

### GUI Code (GUIDE-Generated Files)
GUIDE-generated GUI files are exempt from:
- The `end` keyword after each function definition (GUIDE omits it).
- H1 comment format for auto-generated stub callbacks (empty
  `_Callback` / `_CreateFcn` bodies with no logic).
- The 76-character line limit inside `% Begin/End initialization
  code - DO NOT EDIT` blocks.

All other style rules apply, including:
- Loop variables: no `i`/`j`; use `ii`, `jj`, or named vars
  (`con`, `tr`, `gg` for groups).
- Property strings: PascalCase (`'Enable'`, `'String'`, `'Value'`,
  `'BackgroundColor'`, `'ForegroundColor'`); value strings also
  PascalCase (`'On'`, `'Off'`, `'White'`, etc.). MATLAB is
  case-insensitive for property values — this is a style convention.
- Spaces around `=` and after `,`.
- Full doc blocks on all meaningful callbacks (`OpeningFcn`,
  `OutputFcn`, and any callback containing substantive logic).
- Full doc blocks on any hand-written local helper subfunction
  (e.g. a factored `setStatus`/`pulseSerialPort`). The stub-callback
  exemption covers ONLY auto-generated empty `_Callback`/`_CreateFcn`
  bodies — not helpers you add.
- Trailing semicolons on output-producing statements (`set`, `disp`,
  `error`, `load`, `plot`, etc.); prefer `disp`/`fprintf` over the
  discouraged `display`. Suppress stray unsuppressed expressions and
  use an explicit `disp(...)` when console output is intended.
- Section banners: this file uses exemplar-style full-width
  `% ====` banners (see `GetInfoGUI.m`) to group callbacks into
  logical panels, in place of `%%` headers, because GUIDE callbacks
  are independent top-level functions rather than sequential phases.

GUIDE callbacks keep their fixed `(hObject, eventdata, handles)`
signature even when an argument is unused — do NOT replace unused
callback arguments with `~`, and ignore the matching `checkcode`
"input argument might be unused" advisory for callbacks (it does not
apply to the GUIDE dispatch signature). The "global variables are
inefficient" advisory is likewise expected for the shared
`STOP`/`PAUSE` and UI globals and is not a defect to silence here.

## Code Organization
- Use `%%` section headers for all named logical phases; header text
  names the phase, not the code.
- Separate sections with a single blank line before `%%`. Separate
  logically distinct statement groups within a section with a blank
  line.

### Writing Comments
**Write a comment when:** starting a new `%%` section; a non-obvious
algorithm needs a block summary; a line encodes a domain rule or
formula; a magic number needs a source; a decision could have gone
another way. **Omit** when identifiers already make the purpose clear.

Special prefixes: `% TODO:` for known incomplete work; `% NOTE:` for
important caveats or non-obvious constraints.

When editing existing files, preserve: step-labeling comments,
WHY comments, commented-out alternative code, and end-of-line
clarifications (units, roles). Remove only comments that restate what
identifiers already make obvious.
