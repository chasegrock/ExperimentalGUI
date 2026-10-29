# H-Reflex Mapping Tool

A live tool for finding where to place the stimulating bar electrode
over the tibial nerve so that it reliably elicits a Soleus H-reflex.
The experimenter stimulates at a center site and at sites moved left,
up, right, and down from it. Each trial's TA and Soleus EMG is drawn
in a figure placed on screen where that site sits relative to Center,
so the sites can be compared side by side. Built for **SpinalAdapt**
and used there once per leg at the start of every visit (see
[`studies/SpinalAdapt/README.md`](../studies/SpinalAdapt/README.md)).
Like [`HreflexMwaveMonitor/`](../HreflexMwaveMonitor/README.md), it
lives at the repository root rather than in a study folder because it
does not depend on any study.

`HreflexMappingTool.m` is a single script with local functions. It
uses no namespace, since its helpers are specific to this tool.

## Running It

1. Start Vicon Nexus in **Live** mode, with the Delsys Trigno EMG
   device streaming. Open the DS8R control software on the PC, unless
   you will trigger by hand.
2. In a MATLAB instance **of its own**, run `HreflexMappingTool`. The
   script starts with `clearvars; close all`, so never run it in the
   instance running `AdaptationGUI` or a controller.
3. Answer the startup dialogs:
   - the leg under test (Left / Right);
   - a parent folder, inside which it creates
     `LeftNerveLocalization/` or `RightNerveLocalization/`. Cancelling
     here runs the session without saving anything;
   - the TA and SOL Trigno sensor numbers.
4. For each trial:
   1. pick a site;
   2. enter the current in mA (capped at `cfg.maxDemandMa`, default
      50 mA);
   3. click **Stimulate**.

   The recorder arms on a 200 ms baseline, MATLAB fires one DS8R
   pulse, and the trial is plotted in that site's figure. Pick
   **Finish** to end the session. The site figures stay open for
   comparison, and `trials`, `session`, and `figMap` are left in the
   workspace.
5. Repeat for the other leg.

All dialogs open at the top-right of the screen so they never cover
the Center plot. The DS8R output is enabled only for the moment of
each pulse and is disabled again after every trial. It is also
disabled, and the Vicon client disconnected, whenever the session
ends: on Finish, on an error, and on Ctrl+C.

If the DS8R COM server or device is unavailable, or
`cfg.useDS8R = false`, the tool falls back to **manual triggering**:
it arms the recorder and waits up to `cfg.timeoutS` (120 s) for the
experimenter to fire one pulse by hand.

## What It Shows

- **Top axes, TA (the detection channel)**: band-passed EMG with the
  stimulus artifact at t = 0.
- **Bottom axes, Soleus**:
  - the M-wave (5–22 ms) and H-reflex (25–65 ms) search windows,
    shaded;
  - the detected M-wave and H-reflex peaks;
  - the **artifact → H** and **M → H** latencies.

  M → H shows `n/a` when the M-wave is weak or absent (peak-to-peak
  under 3× the pre-stimulus noise).
- A red banner appears if a Vicon frame was dropped inside the 100 ms
  window.

The H-reflex window is deliberately wide. The soleus H-reflex
typically peaks ~35–50 ms after the stimulus (Thompson et al., Front.
Rehabil. Sci. 2022), but this varies between participants.

## Files Written

Everything goes into `<parent>\<Leg>NerveLocalization\`:

| File | Contents |
|---|---|
| `<Leg>NerveLocalization_log_<yyyyMMdd_HHmmss>.csv` | One summary row per trial (all sites): `Trial`, `Timestamp`, `Leg`, `Site`, `Current_mA`, `PulseWidth_us`, `Fs_Hz`, `ArtifactToM_ms`, `ArtifactToH_ms`, `MToH_ms`, `M_peak`, `M_p2p`, `H_peak`, `H_p2p`, `M_present`, `FrameGap`, `SavedImage` |
| `<Leg>NerveLocalization_log_<yyyyMMdd_HHmmss>.mat` | `trials` (the CSV columns plus `t_ms`, `TA_filt`, `SOL_filt`, `TA_raw`, `SOL_raw` waveform windows) and `session` (leg, measured EMG rate, channel names, pulse width, current cap, windows, band-pass) |
| `Center_<yyyyMMdd_HHmmss>_<current>.fig/.png` | Every Center trial's figure, e.g. `Center_20261029_101500_12p30mA.png` |

The CSV and MAT files are rewritten in full after every trial, so a
crash loses at most the trial in progress. If the CSV is open in Excel
the write fails with a warning and succeeds on the next trial. The MAT
`session` struct and the column names above are the saved format, so
keep them stable.

## Configuration

Everything is set in the `cfg` block at the top of the script.

| Field | Default | Meaning |
|---|---|---|
| `hostName` | `'localhost:801'` | Vicon DataStream server |
| `sdkPath`, `sdkAssembly` | `C:\Program Files\Vicon\DataStream SDK\Win64`, `ViconDataStreamSDK_DotNET.dll` | Looked for here first, then on the MATLAB path, then with a file picker |
| `deviceName` | `'EMG'` | Vicon device; channels resolve as `Sensor <n>` / `IM EMG<n>` |
| `fsNominal` | 2000 Hz | Expected EMG rate. The actual rate is measured, with a warning if it differs by >5% |
| `preMs`, `postMs` | 10, 90 ms | Capture window around the artifact |
| `baselineMs`, `guardMs` | 200, 5 ms | Trailing baseline for the artifact detector, ending 5 ms before the newest samples |
| `kAmp`, `kDeriv` | 8, 6 | Artifact = deviation > 8 robust σ **and** first difference > 6 robust σ of the baseline's differences. The rising-edge test rejects volitional TA bursts |
| `absFloor` | `[]` | Optional absolute TA amplitude floor (off) |
| `timeoutS` | 120 s | Give up waiting for an artifact |
| `mWinMs`, `hWinMs` | [5 22], [25 65] ms | Soleus M-wave and H-reflex search windows |
| `mPresentFactor` | 3 | M-wave "present" if its p2p > 3× the pre-stimulus noise p2p |
| `bpBand`, `bpOrder` | [10 500] Hz, 4 | Zero-phase Butterworth band-pass for display and peak picking |
| `figFracW`, `figFracH`, `dialogMarginPx` | 0.32, 0.30, 20 px | Figure size as a fraction of the screen (height is also clamped so the Up/Center/Down column cannot overlap), and the dialogs' top-right margin |
| `useDS8R` | `true` | `false` forces manual triggering |
| `confirmEachStim` | `true` | Stimulate / Cancel confirmation before each pulse |
| `startDemandMa`, `maxDemandMa` | 5, 50 mA | Default first current, and the **software** current cap (set this to the protocol/ethics ceiling) |
| `pulseWidthUs` | 1000 µs | `[]` leaves the DS8R's own setting |
| `recoveryPct`, `dwellUs` | `[]` | `[]` leaves the DS8R's own settings |

## Design Rules (From Lab Pilots)

1. **Wait for DataStream device metadata.** Device metadata appears
   only one or more frames after the first successful `GetFrame()`,
   so `waitForDevices` polls before any channel is queried.
2. **No sync/trigger channel.** The artifact must be detected from raw
   TA EMG.
3. **Keep the H-reflex window wide.** Participants vary.
4. **Peak picking is fully automatic.** There is no manual input.
5. **Never reposition native dialogs after creation.** Moving them
   races their layout. Build custom dialogs at the right position
   instead (`choiceDialogTR`, `inputDialogTR`, `waitBoxTR`).
6. **Safety defaults:**
   - The confirmation offers Stimulate / Cancel buttons and has no
     default button, so Enter does not fire a pulse.
   - Current is capped in software and rounded to the DS8R's 100 µA
     resolution.
   - Output is disabled between trials and on exit (`safeStim`).
7. **Every change needs lab verification.** The Vicon and DS8R paths
   cannot run off the lab PC.

## Relationship to the Rest of the Repository

- **No Arduino involvement.** The tool fires the DS8R through its COM
  API (`actxserver('DigitimerDS8R.DS8RController')`), not through the
  Arduino gait state machine. It never opens the Arduino serial port
  and never writes a `datlog`. Run it while no controller is
  stimulating.
- **Separate artifact detector.** Its detector (rising-edge-gated
  median/MAD threshold on raw TA) is independent of
  `HreflexMwaveMonitor`'s `detectStimArtifactOnline`, which detects
  from the stimulator trigger sync channel when one is recorded. The
  two are not kept in parity.

## Known Risks and Open Checks

- **Which DS8R is controlled.** `connectDS8R` always takes the first
  device the COM server reports (`Items(0)`), whatever leg was
  selected. If both legs' DS8Rs are connected to the PC by USB,
  confirm which unit that is (the serial number is printed at
  startup) before stimulating.
- **DS8R settings persist after the tool exits.** The tool sets
  `Demand`, `PulseWidth` (1000 µs), and a hardware `DemandLimit` of at
  least 100 mA (the API minimum; the finer 50 mA cap is software only).
  It leaves these on the device at exit and disables only the output.
  Check the DS8R's settings and re-enable its output before the
  walking calibrations.
- **Changes awaiting lab verification (2026-10-29 restyle).** The
  script was reformatted to the repository's code style.
  - **Unchanged.** A replay comparison in MATLAB R2025b confirmed that
    filtering, peak detection, latencies, current clamping, figure
    layout, and the CSV/MAT formats are identical to the 2026-09-28
    version.
  - **Small fixes not yet run on the lab PC:**
    - The session now runs inside a local function
      (`runMappingSession`), so its `onCleanup` handlers fire on an
      error or Ctrl+C. Before, they lived in the script's base
      workspace and fired only when that workspace was cleared, which
      could leave the DS8R output enabled and a stale Vicon client
      connected after an error.
    - In `inputDialogTR`, moving focus out of a field (Tab, or
      clicking another field or Cancel) no longer submits the dialog.
      An edit box's callback also fires on focus loss, so the sensor
      dialog could close with the SOL field still at its default.
    - A 0 mA current is rejected (it can never produce an artifact).
    - Sensor numbers must be whole numbers.

  **In the lab, check that:**
  - Tab and clicking between the sensor fields no longer submit;
  - Enter still submits;
  - Cancel after typing cancels;
  - Ctrl+C during a capture leaves the DS8R output disabled.

## See Also

[Repository root `CLAUDE.md`](../CLAUDE.md) (active studies, H-reflex
timing contract), [`studies/SpinalAdapt/README.md`](../studies/SpinalAdapt/README.md),
[`HreflexMwaveMonitor/README.md`](../HreflexMwaveMonitor/README.md),
[`HreflexStimArduino/README.md`](../HreflexStimArduino/README.md).
