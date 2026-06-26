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
Speed profiles (`velL`, `velR`) are Nx1 column vectors in mm/s generated
by `generateProfiles_*` scripts inside each study's folder. A NaN value
at position k means stride k is self-paced (the controller holds or
queries treadmill speed rather than applying a predetermined value).
Profiles are passed directly to controller functions as arguments — there
is no file-based loading at runtime.

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

**datlog fields** — `buildtime` (ISO 8601), `profilename`, `mode`,
`RTOTime`, `LTOTime`, `RHSTime`, `LHSTime`, `commSendTime`. Saved to
`datlogs/<timestamp>_<profile>.mat` on STOP.

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

**SpinalAdapt** — rebooting; data collection planned to resume ~July
2026. Lead: Chase Rock (post-doctoral fellow); key experimenters:
Shuqi Liu, Nate Brantly. Measures fNIRS and H-reflex in addition to
Vicon motion capture and Delsys EMG. Primary protocol:
`studies/SpinalAdapt/RunProtocol_SpinalAdaptBouts.m`. H-reflex
stimulation timing is controlled by an Arduino Uno running
`HreflexStimArduino/triggerStimWithGaitStateMachine_SpeedIndependent/`
(see `HreflexStimArduino/README.md` for upload and wiring details). Do
not change the serial command protocol in MATLAB controllers without
re-uploading compatible Arduino firmware.

**H-reflex timing contract** — the Arduino owns the precise
50%-single-stance pulse timing: it runs its own gait state machine and
fires locally. The MATLAB controller (`NirsHreflexArduinoOpenLoopWithAudio`)
sends serial command `0` once before the main loop to start the
Arduino's state machine, and command `3` in the closing routine to stop
it; do not change this handshake without re-uploading compatible Arduino
firmware. Per stride, MATLAB only sends a gate byte (`1` = stim left,
`2` = stim right) and must send it at single-stance onset, NOT at
mid-stance. Sending late leaves too little margin before the Arduino's
50% trigger and causes missed or mistimed stims. The deprecated
`NirsHreflexOpenLoopWithAudio` (now in `controllers/Deprecated/`) pairs
with the alternative `Dual_Stim_Matlab.ino` firmware, which has no
on-board gait detection — keep it only as a fallback for that
fully-MATLAB-timed mode. Keep display work off the control
loop's hot path: `drawnow limitrate`, one reusable `animatedline` per
leg (not a new `plot` per stride), and time-throttled textbox/`set`
updates. Per-iteration loop timing and gate lead time are logged to the
additive `datlog.diagnostics` field for validation.

**NirsAutomaticityProtocol**, **Perceptual Adaptation**, and **Weber
Perception** — completed; data collection and processing finished.
Shuqi Liu led NirsAutomaticityProtocol; Marcela Gonzalez-Rubio led
Perceptual Adaptation and Weber Perception. Consult the lead
experimenter before modifying scripts in these folders.

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
- Do not use `i` or `j` as loop indices (reserved for imaginary unit).
  For stride loops use `st`; for generic enumeration use `ii`, `jj`,
  `kk`. Preferred short names: `mscl` (muscles), `mrkr` (markers),
  `lbl` (labels), `tr` (trials), `con` (conditions), `fp` (force
  plates), `ch` (channels). Never use `iMuscle`-style names.
- Do not indent the base level of code inside functions
- Align `=` within a group of closely related assignments
- Write `0.5` not `.5`
- Use `mean(x, 'omitnan')` not `nanmean(x)` (similarly for `median`,
  `std`, `sum`). For `min`/`max`: `min(x, [], 'omitnan')`.
- Define unexplained numeric literals as named constants (camelCase)
  with an end-of-line comment giving their source or rationale.
- Prefer `fullfile(...)` over string concatenation with `filesep`:
  `fullfile(dir, 'file.mat')` not `[dir filesep 'file.mat']`

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
