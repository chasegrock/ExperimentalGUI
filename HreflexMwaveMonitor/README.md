# H-Reflex M-Wave Monitor

A near-real-time tool that shows the experimenter the most recent
H-reflex M-wave amplitude per leg during a walking H-reflex session,
so DS8R stimulation current can be adjusted to hold the M-wave within
±10% of its calibration baseline. Built for **SpinalAdapt** (the only
study currently using H-reflex measurements), but deliberately kept
study-agnostic — living here, outside `studies/SpinalAdapt/`, rather
than inside it — since other studies may adopt H-reflex measurement in
the future.

It is designed to run in a **separate MATLAB instance** from the
control/stimulation instance (its own Vicon DataStream client, device
data only), so it cannot perturb `NirsHreflexArduinoOpenLoopWithAudio`'s
control-loop timing; it never opens the Arduino serial port and never
writes to the controller's `datlog`. See the H-reflex timing contract
in the repository root `CLAUDE.md` for the control-loop side this tool
must not interfere with.

## Namespace

All monitor logic lives in the `+hreflexMonitor` package
(`HreflexMwaveMonitor/+hreflexMonitor/`), called as
`hreflexMonitor.functionName(...)` — e.g.
`hreflexMonitor.runHreflexMwaveMonitor(...)`. This mirrors the
repository root's existing `+utils` package convention
(`utils.transferData`, etc.) and keeps the tool's public surface
grouped and collision-free as it grows. Test files are plain
(non-namespaced) siblings in this folder, calling into the package
with the qualified name.

**Put `HreflexMwaveMonitor/` (not `+hreflexMonitor/` itself) on the
MATLAB path** — same rule as every other folder in this repository.
This repository does not ship a `startup.m` or persisted `pathdef.m`,
so path setup is manual (e.g. MATLAB's "Set Path > Add with
Subfolders" from the repo root, run once and saved); confirm
`HreflexMwaveMonitor` is included wherever this tool will run.

## File Table

| File | Phase | Purpose |
|---|---|---|
| `+hreflexMonitor/probeViconDataStreamDevices.m` | 0 | Read-only DataStream device/output/component enumeration, with per-channel subsample counts and signal statistics — run this first in the lab (Nexus in Live mode, `HreflexEMGDataCollection` profile selected, firing stimuli) to confirm EMG + `Stimulator_Trigger_Sync_*` are exposed live (not just in the C3D) before relying on a live source in a later phase. |
| `+hreflexMonitor/detectStimArtifactOnline.m` | 1 | Causal, streaming re-implementation of `Hreflex.extractStimArtifactIndsFromTrigger`'s onset/artifact-peak detection (largest absolute deflection in the window; see Artifact Localization Rule below). |
| `+hreflexMonitor/stepHreflexMonitor.m` | 1-2 | Per-chunk pipeline step: buffers EMG, calls the detector, and — once each stim's full snippet window has arrived — recomputes M-/H-wave/noise amplitudes over the *entire accumulated snippet set* via `Hreflex.computeAmplitudes` (required for exact parity with the offline batch statistic), and re-derives which peak/trough sample indices that computation used (`state.mWaveInds`) so a caller's marker matches the displayed, possibly outlier-corrected, amplitude. |
| `+hreflexMonitor/hreflexSourceReplayC3D.m` | 1 | Loads a prior H-reflex trial C3D (via BTK) for replay validation. |
| `+hreflexMonitor/mapHreflexAnalogChannels.m` | 1 | BTK-independent channel-mapping logic used by the loader above: EMG channels are named by sensor number in the C3D. The real field naming (confirmed on SABH02 `Trial03.c3d`) has TWO fields per sensor, `Sensor_<n>_EMG<n>` and `Sensor_<n>_IM_EMG<n>`; for every sensor checked in that file the plain `EMG<n>` field was completely flat (`std(Sensor_7_EMG7) = 0`) while `IM_EMG<n>` carried the real signal (`std(Sensor_7_IM_EMG7) ≈ 6e-5 V`) — the plain field appears to be an unpopulated placeholder in this export configuration, not real EMG. Both this mapping and `GenerateHreflexRecruitmentCurves.m` resolve a sensor's channel via the same `strfind(...,'EMG')` + trailing-digit parse and, because `IM_EMG<n>` iterates after `EMG<n>` in this file's field order, both end up selecting the live `IM_EMG<n>` field here (`relData(:,idxList) = relDataTemp`'s last-write-wins behavior in the offline script — inferred by reading that code, not executed, since it is external/out-of-repo and not something to run changes against). This has only been confirmed for this one file; it is not proven as a structural invariant across all SpinalAdapt sessions — see Real-Data Validation below. — the muscle assignment is session-specific placement metadata, not derivable from the file, so this mirrors `GenerateHreflexRecruitmentCurves`'s own sensor-order mapping (`emgSensorMap`, same default). Factored out so this mapping is unit-testable without BTK. |
| `+hreflexMonitor/promptHreflexMuscle.m` | 1 | Shared "which muscle is the H-reflex channel" prompt (SOL default, MG/LG allowed) — used by the replay source now and, in a later phase, by the live source too. |
| `+hreflexMonitor/promptHreflexBaseline.m` | 2 | Prompts for a leg's baseline M-wave amplitude (mV), read off that leg's walking-calibration recruitment curve, since no baseline is currently persisted by `GenerateHreflexRecruitmentCurves.m` for this tool to load automatically (see Flagged Upstream Item below). |
| `+hreflexMonitor/computeMwaveTolerance.m` | 2 | Pure ±10% (default) tolerance-bound arithmetic around a baseline M-wave value. |
| `+hreflexMonitor/generateSyntheticHreflexTrial.m` | 1 (test) | Hardware/BTK-free synthetic trial fixture for CI. |
| `+hreflexMonitor/runHreflexMwaveMonitor.m` | 1-3 | Entry point: replays a trial through the pipeline, updating one persistent two-axes figure in place per stim — snippet with the M-wave peak/trough marked (top), M-wave amplitude vs. stimulus number with the baseline and ±10% bounds, an in/out-of-tolerance indicator, and a last-N-out-of-tolerance counter (bottom). Single-leg only for now (`leg` argument); a later phase removes it and monitors both legs at once. |
| `testDetectStimArtifactOnline.m` | 1 (test) | Unit + online-vs-offline parity tests for the causal detector, including the negative-dominant artifact regression fixture (see Artifact Localization Rule below). |
| `testHreflexMwaveMonitorReplay.m` | 1-2 (test) | Integration parity between the online pipeline and the offline `+Hreflex` batch pipeline, including the marker-index fix and a lab-only real-C3D replay test. |
| `testMapHreflexAnalogChannels.m` | 1 (test) | BTK-free unit tests for the channel-mapping logic. |
| `testComputeMwaveTolerance.m` | 2 (test) | Unit tests for the tolerance-bound arithmetic. |

## Real-Data Validation (2026-08-14)

Phase 1's real-data gap (previously open — no BTK-for-Windows binary on
the development machine) is now closed. Using BTK for Windows at
`Z:\Nathan\btk` (**a local testing copy — not confirmed to be what the
lab PC has installed**; re-verify BTK's location/version there) and a
copy of pilot participant SABH02's `Trial03.c3d` (real SpinalAdapt
walking H-reflex calibration data, from
`Z:\SpinalAdaptStudy\Data\SABH02\Vicon\`):

- **Exact stim-count parity, right leg**: the online causal detector
  (`detectStimArtifactOnline`) and the offline whole-trial helper
  (`Hreflex.extractStimArtifactIndsFromTrigger`) both find **60**
  stimuli — a direct, non-synthetic confirmation of the parity
  guarantee `testDetectStimArtifactOnline`/`testHreflexMwaveMonitorReplay`
  establish on synthetic data.
- **M-wave magnitudes match production output**: computed M-wave
  amplitudes ranged ~0.02–3.5 mV (mean 1.66, std 1.45) across the
  trial's ascending-current stimuli, closely tracking the real
  recruitment-curve plateau (~3.4–3.5 mV) in
  `Z:\SpinalAdaptStudy\Data\SABH02\Vicon\HreflexCalFigs\SABH02_HreflexRecruitmentCurve_Trial03_RightLeg.png`
  (and the corresponding left-leg figure) — confirming the channel
  mapping resolves the correct, live physiological EMG signal
  (`IM_EMG<n>`), not the flat placeholder (`EMG<n>`, `std = 0`) or
  some other mismatched channel that happens not to error. Verify
  `std(...) > 0` on the resolved H-muscle channel for a new
  participant/export before trusting this same field selection.
- **Growing-set recompute cost, real stimulus counts**: at N=60 stimuli
  (chunk size 10), per-stimulus recompute time was median 5.3 ms, p95
  29.8 ms, max 754 ms (one-off, consistent with first-call JIT
  warm-up). Scaling roughly linearly with N (the recompute is
  O(numStimSoFar) by design — see `stepHreflexMonitor.m`), a full
  ~400-stimulus calibration trial would be expected to cost on the
  order of ~100 ms at its largest N — comfortably inside a gait
  cycle's double-support window and the "bounded per-update work"
  isolation requirement. Still worth a real timing check at an actual
  ~400-stim trial in the lab before fully retiring this caveat.
- The gated real-C3D integration test now passes:
  `runtests('testHreflexMwaveMonitorReplay')` with
  `HREFLEX_REPLAY_TEST_C3D` pointed at a real calibration C3D exercises
  this exact comparison (stim count + amplitude parity, `AbsTol` 1e-6)
  end to end.
- The full driver (`runHreflexMwaveMonitor`, Phase 1-3) was also
  smoke-tested against this real trial (right leg, explicit baseline to
  skip the interactive prompt) and produces the expected two-axes
  figure: a clean sigmoid-shaped M-wave-vs-stimulus trend matching the
  real recruitment curve's shape, correct peak/trough marker placement,
  and a working tolerance indicator/counter.

## Artifact Localization Rule (2026-08-26)

`Hreflex.extractStimArtifactIndsFromTrigger`'s private
`findStimArtifactInds` and this tool's causal mirror,
`detectStimArtifactOnline`, both take the artifact as the sample of
largest **absolute** deflection from the search window median. The
stimulation artifact is commonly negative-dominant — its initial
deflection is downward, with a smaller positive rebound ~1.5 ms later —
so the previous signed-positive `findpeaks` search with a
`minArtifactPeak` height gate either locked onto the rebound or, when
the artifact was small, found nothing and fell back to the raw maximum
over the whole 200 ms window. Absolute deflection is polarity agnostic
and needs no threshold, because the window is already anchored to a
known trigger pulse; `findpeaks` (and its
`findpeaks:largeMinPeakHeight` warning, previously suppressed here) is
gone from both implementations.

Measured on SABH02 `Trial03.c3d`, the rule change moves every one of
the 120 stimuli 1.5 ms earlier (max 2.0 ms) and shifts mean M-wave
amplitude by less than 0.6%. `minArtifactPeak` survives only in the
offline helper, repurposed from a detection gate into a quality
control floor reported through its new second output,
`isWeakArtifact`; `detectStimArtifactOnline` no longer takes it.
`testDetectStimArtifactOnline` pins the shared rule with a
negative-dominant fixture whose artifact sits below the old 1 mV gate.

## Known Gaps Before This Is Lab-Ready

- **Live Vicon DataStream source** (`hreflexSourceDataStream.m`, Phase
  3) is not yet built — replay-only so far. Needs a lab dry-run
  alongside the control instance before real use.
- **Second-leg simultaneous monitoring** (Phase 3) is not yet built;
  `runHreflexMwaveMonitor`'s `leg` argument still selects one leg per
  call. Deferred as a bigger structural change (two independent
  pipeline states/figures, per-leg baseline prompts) rather than
  bundled into this pass.
- `probeViconDataStreamDevices.m` has not been run against a *live*
  stream (only the offline BTK/C3D path has real-data coverage so far)
  — run this first in the lab. Its connection, device wait, subsample
  count, and value read mirror `HreflexMappingTool`'s live EMG path,
  but its enumeration calls (`GetDeviceName`, `GetDeviceOutputCount`,
  `GetDeviceOutputComponentName`) are used nowhere else in this
  repository, and their zero-based indexing is inferred from the same
  client's other calls. `report.indexFailures` or a warning at the end
  of its output flags a wrong assumption. Its CPU load alongside the
  control loop is also unmeasured, so run it without a control instance
  first.
- `promptHreflexMuscle.m` and `promptHreflexBaseline.m`'s interactive
  dialogs (`listdlg`, `inputdlg`) are untested interactively (every
  automated test passes `muscle`/`baselineMwaveMv` explicitly to
  bypass them).

## Validate With

```matlab
runtests('testDetectStimArtifactOnline')
runtests('testMapHreflexAnalogChannels')
runtests('testComputeMwaveTolerance')
runtests('testHreflexMwaveMonitorReplay')
```

The last suite's `testReplayAgainstRealCalibrationC3D` is lab-only,
skipped (not failed) unless the `HREFLEX_REPLAY_TEST_C3D` environment
variable points at a real calibration trial C3D — see Real-Data
Validation above for a worked example.

## Flagged Upstream Item (Not Built Here)

`GenerateHreflexRecruitmentCurves.m` (labTools) does not currently
persist a per-leg baseline M-wave value anywhere a downstream tool
could load automatically — `promptHreflexBaseline.m` above asks the
experimenter to type it in instead. Having that script (or a small new
`+Hreflex` function) persist an `<id>HreflexBaseline.mat` upstream in
labTools would let this tool load the baseline instead of prompting;
this is a separate, coordinated labTools change, not built as part of
this tool.

## See Also

[Repository root `CLAUDE.md`](../CLAUDE.md) (H-reflex timing contract,
active studies), [`studies/SpinalAdapt/README.md`](../studies/SpinalAdapt/README.md)
(the study this tool was built for), `labTools/fun/+Hreflex/` (the
offline batch pipeline this tool mirrors).
