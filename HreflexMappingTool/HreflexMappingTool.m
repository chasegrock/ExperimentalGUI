%HREFLEXMAPPINGTOOL Live H-reflex electrode-placement mapping tool.
%
%   Streams EMG from Vicon (via the DataStream SDK), watches the Tibialis
% Anterior (TA) channel for the stimulation artifact, and on each
% detected stimulus grabs a 100 ms window (10 ms pre-artifact to 90 ms
% post) of TA and Soleus (SOL) EMG. Each trial is plotted in a screen
% location that matches the electrode position (center/left/up/right/
% down) so multiple stimulation sites can be compared at a glance. The
% Soleus M-wave and H-reflex peaks are found automatically and
% annotated with:
%     (1) artifact -> H-reflex peak latency (ms)
%     (2) M-wave   -> H-reflex peak latency (ms)
%
%   Run it once per leg. It starts with CLEARVARS and CLOSE ALL, so run
% it in a MATLAB instance of its own, never in the instance running
% ADAPTATIONGUI or a controller. All session work happens inside the
% RUNMAPPINGSESSION local function, so the DS8R output is disabled and
% the Vicon client disconnected on normal exit, on error, and on Ctrl+C.
% The trials, session metadata, and site figure handles are returned to
% the base workspace when it finishes.
%
%   HARDWARE / SOFTWARE ASSUMPTIONS
%   - Stimulator: Digitimer DS8R + bar electrode, triggered from MATLAB
%     through the DS8R COM API. There is no separate sync/trigger
%     channel in Vicon, so the artifact is detected from TA EMG. Falls
%     back to MANUAL triggering if the COM server or device is
%     unavailable (or cfg.useDS8R is false).
%   - Recording: Delsys Trigno via Vicon. EMG effective rate 2000 Hz,
%     streamed as sub-samples inside 100 Hz Vicon frames.
%   - Vicon device name = 'EMG', output name = 'Sensor #', output
%     component = 'IM EMG#' (# = the sensor number entered at startup).
%   - MATLAB R2021a or later, DataStream SDK v1.11, Win64.
%
%   DETECTION / TIMING DEFAULTS (all tunable in the configuration below)
%   - Adaptive artifact threshold on raw TA (robust median/MAD
%     baseline), gated by a rising-edge (derivative) criterion to reject
%     volitional TA bursts during walking.
%   - Soleus M-wave search window: 5-22 ms after the artifact.
%   - Soleus H-reflex search window: 25-65 ms after the artifact
%     (deliberately wide; the soleus H-reflex interval is ~35-50 ms
%     post-stimulus per Thompson et al., Front. Rehabil. Sci. 2022).
%   - Display band-pass: 10-500 Hz, zero-phase.
%
%   FILES WRITTEN (to <chosen parent folder>\<Leg>NerveLocalization\)
%   - <Leg>NerveLocalization_log_<yyyyMMdd_HHmmss>.csv - one summary
%     row per trial (all sites), rewritten after every trial
%   - <Leg>NerveLocalization_log_<yyyyMMdd_HHmmss>.mat - 'trials'
%     (summary + raw and filtered waveform windows) and 'session'
%     (metadata), rewritten after every trial
%   - Center_<yyyyMMdd_HHmmss>_<current>.fig/.png - every Center trial
%
% NOTE: EMG amplitude is plotted in whatever units Vicon streams (device
% scaling dependent, typically volts for Trigno). Axes are labelled
% "EMG (units)".
%
% Toolbox Dependencies:
%   Signal Processing Toolbox (optional; without it the display falls
%   back to DC removal only and warns)
%   External: Vicon DataStream SDK (.NET), Digitimer DS8R software
%   (COM server 'DigitimerDS8R.DS8RController')
%
% See also HREFLEXMONITOR.RUNHREFLEXMWAVEMONITOR.

clearvars;
close all;

%% Configure the Tool
cfg = struct();

% --- Connection / SDK ---
cfg.hostName    = 'localhost:801';
cfg.sdkPath     = 'C:\Program Files\Vicon\DataStream SDK\Win64';
cfg.sdkAssembly = 'ViconDataStreamSDK_DotNET.dll';
cfg.deviceName  = 'EMG';     % Vicon device name for the EMG system

% --- Acquisition timing ---
cfg.fsNominal = 2000;  % expected EMG rate (Hz); actual is measured
cfg.preMs     = 10;    % window start, before artifact (ms)
cfg.postMs    = 90;    % window end, after artifact (ms)

% --- Artifact detection (on RAW TA) ---
cfg.baselineMs = 200;  % trailing window for baseline stats (ms)
cfg.guardMs    = 5;    % gap between baseline window and "now" (ms)
cfg.kAmp       = 8;    % amplitude threshold = median + kAmp*sigma
cfg.kDeriv     = 6;    % rising-edge threshold = kDeriv*sigma(diff)
cfg.absFloor   = [];   % optional absolute |TA| floor (units); [] = off
cfg.timeoutS   = 120;  % give up watching after this many seconds

% --- Peak search windows (ms after artifact) ---
cfg.mWinMs         = [5 22];   % Soleus M-wave search window
cfg.hWinMs         = [25 65];  % Soleus H-reflex search window (wide)
cfg.mPresentFactor = 3;        % M-wave "present" if p2p > factor *
                               % noise p2p

% --- Display filtering ---
cfg.bpBand  = [10 500];  % band-pass for display/peak-picking (Hz)
cfg.bpOrder = 4;         % Butterworth order

% --- Screen layout ---
% Figures are kept short so the Up/Center/Down column does not overlap;
% SITEPOSITIONS also hard-clamps the height to fit 3 stacked figures.
cfg.figFracW       = 0.32;  % each figure width as fraction of screen
cfg.figFracH       = 0.30;  % each figure height as fraction of screen
cfg.dialogMarginPx = 20;    % gap from the top-right screen corner (px)

cfg.sites = {'Center', 'Left', 'Up', 'Right', 'Down'};

% --- DS8R stimulator (Digitimer COM API) ---
cfg.useDS8R         = true;   % true: MATLAB triggers the DS8R.
                              % false (or COM unavailable): MANUAL
                              % triggering (experimenter fires the
                              % pulse by hand/pedal).
cfg.ds8rProgID      = 'DigitimerDS8R.DS8RController';
cfg.confirmEachStim = true;   % require a click to confirm each pulse
cfg.startDemandMa   = 5;      % default starting stimulus current (mA)
cfg.maxDemandMa     = 50;     % SOFTWARE safety cap on stimulus current
                              % (mA); set to the protocol/ethics ceiling
cfg.pulseWidthUs    = 1000;   % stimulus pulse width (us); 1 ms typical
                              % for H-reflex. [] = leave the DS8R's own
                              % setting.
cfg.recoveryPct     = [];     % [] = leave device setting (biphasic only)
cfg.dwellUs         = [];     % [] = leave device setting

%% Run the Mapping Session
[trials, session, figMap] = runMappingSession(cfg);

%% ======================= LOCAL FUNCTIONS ============================

function [trials, session, figMap] = runMappingSession(cfg)
%RUNMAPPINGSESSION Run one leg's electrode-mapping session.
%
%   Prompts for the leg, save folder, and EMG sensors; connects to Vicon
% and the DS8R; then loops over site selection, stimulation, capture,
% and display until the experimenter picks Finish. Runs in a function
% workspace rather than the script's base workspace so its onCleanup
% objects fire on normal return, on error, and on Ctrl+C alike, leaving
% the DS8R output disabled and the Vicon client disconnected (onCleanup
% objects in a script's base workspace only fire when the base
% workspace is cleared).
%
% Inputs:
%   cfg - configuration struct built at the top of HREFLEXMAPPINGTOOL
%
% Outputs:
%   trials  - struct array, one element per logged trial (see LOGTRIAL)
%   session - session metadata struct (see BUILDSESSION); empty struct
%             if cancelled before the session started
%   figMap  - struct of site figure handles, one field per site plotted
%
% Toolbox Dependencies:
%   None

fsTolFrac = 0.05;  % warn if the measured EMG rate is >5% off nominal

trials  = emptyTrials();
session = struct();
figMap  = struct();

%% Prompt for the Leg and Save Folder
% The protocol runs once per leg, so keep the two legs in separate
% folders.
leg = choiceDialogTR(cfg, 'Which leg is being tested?', ...
    'Leg under test', {'Left', 'Right'});
if isempty(leg)
    fprintf('Cancelled at leg selection. Exiting.\n');
    return;
end
% Ask once for a parent folder; create "<Leg>NerveLocalization" in it.
saveDir = ensureNLFolder(leg);  % '' if the user cancels (nothing saved)

%% Prompt for the EMG Sensor Numbers
[answ, ok] = inputDialogTR(cfg, ...
    {'TA (Tibialis Anterior) sensor number:', ...
     'SOL (Soleus) sensor number:'}, ...
    'EMG sensor assignment', {'1', '2'});
if ~ok
    fprintf('Cancelled at sensor entry. Exiting.\n');
    return;
end
taNum      = str2double(answ{1});
solNum     = str2double(answ{2});
sensorNums = [taNum solNum];
if any(isnan(sensorNums)) || any(sensorNums < 1) ...
        || any(sensorNums ~= round(sensorNums))
    error('Sensor numbers must be positive integers.');
end

ch.TA.output  = sprintf('Sensor %d', taNum);
ch.TA.comp    = sprintf('IM EMG%d', taNum);
ch.SOL.output = sprintf('Sensor %d', solNum);
ch.SOL.comp   = sprintf('IM EMG%d', solNum);
fprintf('TA : %s / %s\nSOL: %s / %s\n', ch.TA.output, ch.TA.comp, ...
    ch.SOL.output, ch.SOL.comp);

%% Connect to Vicon
viconClient  = connectVicon(cfg);
cleanupVicon = onCleanup(@() safeDisconnect(viconClient));

%% Measure the Effective EMG Rate
fs = measureRate(viconClient, cfg, ch);
fprintf('Measured EMG rate: %g Hz (%d sub-samples/frame).\n', fs, ...
    round(fs / getFrameRate(viconClient)));
if abs(fs - cfg.fsNominal) > fsTolFrac * cfg.fsNominal
    warning(['Measured EMG rate (%g Hz) differs from nominal (%g Hz). ' ...
        'Using measured value.'], fs, cfg.fsNominal);
end

%% Precompute Screen Positions and the Display Filter
figPos = sitePositions(cfg);       % figPos.(site) = [x y w h]
bp     = designBandpass(fs, cfg);  % filter coefficients ([] if no
                                   % toolbox)

%% Connect the DS8R Stimulator
stim = connectDS8R(cfg);  % [] if manual / unavailable
% Disable output and release the COM server on exit/error.
cleanupStim  = onCleanup(@() safeStim(stim));
lastDemandMa = cfg.startDemandMa;

%% Initialize the Per-Trial Log
% One CSV and one MAT per session, written to the same "Nerve
% Localization" folder and rewritten after every trial (crash-
% resilient). The MAT also stores the raw + filtered windows for later
% re-analysis.
sessionTag = char(datetime('now', 'Format', 'yyyyMMdd_HHmmss'));
logStem    = sprintf('%sNerveLocalization_log_%s', leg, sessionTag);
csvPath    = '';
matPath    = '';
if ~isempty(saveDir)
    csvPath = fullfile(saveDir, [logStem '.csv']);
    matPath = fullfile(saveDir, [logStem '.mat']);
    fprintf('Trial log: %s(.csv/.mat)\n', fullfile(saveDir, logStem));
end
session = buildSession(sessionTag, fs, ch, cfg, saveDir, leg);

%% Pick a Site, Set Intensity, Stimulate, Capture, and Plot
if isempty(stim)
    fprintf(['\nReady (MANUAL trigger). Pick a site, deliver ONE ' ...
        'stimulation, inspect, repeat.\n']);
else
    fprintf(['\nReady (DS8R serial %d). Pick a site, set intensity, ' ...
        'stimulate, inspect, repeat.\n'], stim.serial);
end
while true
    site = choiceDialogTR(cfg, 'Select stimulation site to record:', ...
        'Stimulation site', [cfg.sites, {'--- Finish ---'}]);
    if isempty(site) || strcmp(site, '--- Finish ---')
        break;  % Finish / cancelled
    end

    % Determine the intensity and build the trigger action.
    demandMa = NaN;
    if isempty(stim)
        triggerFcn = [];  % experimenter fires manually
    else
        [answ, ok] = inputDialogTR(cfg, ...
            {sprintf('Stimulus current for %s (mA), max %g:', site, ...
            cfg.maxDemandMa)}, ...
            'Stimulus intensity', {num2str(lastDemandMa)});
        if ~ok
            continue;  % cancelled -> back to site menu
        end
        demandMa = str2double(answ{1});
        % NOTE: 0 mA is rejected too: it can never produce an artifact,
        % so the trial would only sit until cfg.timeoutS.
        if isnan(demandMa) || demandMa <= 0
            warning(['Invalid current (must be greater than 0 mA); ' ...
                'skipping.']);
            continue;
        end
        % Enforce the software cap.
        [demandUa, demandMa] = clampDemand(demandMa, cfg);
        lastDemandMa = demandMa;

        if cfg.confirmEachStim
            confirm = choiceDialogTR(cfg, sprintf(['Site: %s\n' ...
                'Current: %.2f mA\nPulse width: %s\n\n' ...
                'Arm the recorder and STIMULATE?'], site, demandMa, ...
                pwStr(cfg)), ...
                'Confirm stimulation', {'Stimulate', 'Cancel'});
            if ~strcmp(confirm, 'Stimulate')
                continue;
            end
        end
        % Push current + pulse width and enable output.
        setStim(stim, cfg, demandUa);
        triggerFcn = @() fireStim(stim);  % fired once the recorder is
                                          % armed
    end

    % Create or raise this site's figure in its screen location.
    figMap.(site) = ensureFigure(figMap, site, figPos.(site));
    showArmed(figMap.(site), site);

    % Arm the detector, fire the pulse (auto mode), and capture the
    % window.
    cap = captureOneStim(viconClient, ch, cfg, fs, site, triggerFcn);
    if ~isempty(stim)
        safeDisableOutput(stim);  % leave the device "cold" between
                                  % trials
    end
    if isempty(cap)
        showAborted(figMap.(site), site);
        continue;  % cancelled or timed out
    end

    % Filter, find peaks, and draw.
    trace          = processTrace(cap, cfg, bp);
    trace.demandMa = demandMa;  % NaN in manual mode
    plotSite(figMap.(site), site, trace, cfg);

    % Save Center trials to disk (.fig + .png) for the localization
    % record.
    savedImg = '';
    if strcmpi(site, 'Center') && ~isempty(saveDir)
        savedImg = saveCenterFigure(figMap.(site), saveDir, demandMa);
    end

    % Append this trial to the CSV + MAT log (all sites).
    if ~isempty(saveDir)
        trials = logTrial(trials, csvPath, matPath, session, ...
            site, demandMa, cfg, fs, trace, cap, savedImg);
    end

    fprintf(['[%s] I = %s mA | artifact->H = %.1f ms | M->H = %s | ' ...
        'H p2p = %.4g | M p2p = %.4g\n'], site, iStr(demandMa), ...
        trace.artToHMs, latStr(trace.mToHMs), trace.hP2p, trace.mP2p);
end

%% Report and Finish
fprintf('\nFinished. %d site figure(s) left open for comparison.\n', ...
    numel(fieldnames(figMap)));
if ~isempty(saveDir)
    fprintf('Logged %d trial(s) to %s(.csv/.mat).\n', numel(trials), ...
        fullfile(saveDir, logStem));
end
% Returning fires cleanupStim and cleanupVicon (DS8R output disabled,
% COM server released, Vicon disconnected). Figures remain open.
end

function viconClient = connectVicon(cfg)
%CONNECTVICON Load the DataStream SDK and connect to the Vicon server.
%
%   Loads the .NET assembly (from cfg.sdkPath, then the MATLAB path,
% then a file picker), connects, enables device data, and sets a
% one-frame ClientPull stream.
%
% Inputs:
%   cfg - configuration struct (hostName, sdkPath, sdkAssembly)
%
% Outputs:
%   viconClient - connected ViconDataStreamSDK.DotNET.Client
%
% Toolbox Dependencies:
%   None (external: Vicon DataStream SDK .NET assembly)

connectTimeoutS = 30;    % give up connecting after this long (s)
connectRetryS   = 0.05;  % pause between connection attempts (s)

fprintf('Loading Vicon DataStream SDK ...');
asmPath = fullfile(cfg.sdkPath, cfg.sdkAssembly);
if exist(asmPath, 'file') ~= 2
    % Fall back to the MATLAB path, then to a file picker.
    onPath = which(cfg.sdkAssembly);
    if ~isempty(onPath)
        asmPath = onPath;
    else
        [fileName, folder] = uigetfile('*.dll', ...
            'Locate ViconDataStreamSDK_DotNET.dll');
        if isequal(fileName, 0)
            error('SDK assembly not found; cannot continue.');
        end
        asmPath = fullfile(folder, fileName);
    end
end
NET.addAssembly(asmPath);
fprintf(' done.\n');

viconClient = ViconDataStreamSDK.DotNET.Client();
fprintf('Connecting to %s ', cfg.hostName);
tConn = tic;
while ~viconClient.IsConnected().Connected
    viconClient.Connect(cfg.hostName);
    fprintf('.');
    if toc(tConn) > connectTimeoutS
        error('Could not connect to Vicon at %s within %g s.', ...
            cfg.hostName, connectTimeoutS);
    end
    pause(connectRetryS);
end
fprintf(' connected.\n');

viconClient.EnableDeviceData();
viconClient.SetBufferSize(1);
viconClient.SetStreamMode( ...
    ViconDataStreamSDK.DotNET.StreamMode.ClientPull);
end

function safeDisconnect(viconClient)
%SAFEDISCONNECT Disconnect from Vicon, ignoring teardown errors.
%
% Inputs:
%   viconClient - ViconDataStreamSDK.DotNET.Client, or []
%
% Outputs:
%   None
%
% Toolbox Dependencies:
%   None (external: Vicon DataStream SDK .NET assembly)

try
    if ~isempty(viconClient) && viconClient.IsConnected().Connected
        viconClient.Disconnect();
        fprintf('Disconnected from Vicon.\n');
    end
catch
    % ignore errors during teardown
end
end

%% ---------- DS8R stimulator (Digitimer COM API) ----------

function stim = connectDS8R(cfg)
%CONNECTDS8R Start the DS8R COM server and grab the first device.
%
%   Returns [] (MANUAL triggering) if DS8R control is disabled in the
% configuration, the COM server cannot start, or no device is found.
% Prints the device's current pulse-shape settings so the experimenter
% can confirm the unit is configured as expected.
%
% NOTE: COM members (GetState, Items, Count, ...) are called exactly as
% in the lab-validated version of this tool; the DS8R COM API is not
% exercised by any automated test.
%
% Inputs:
%   cfg - configuration struct (useDS8R, ds8rProgID)
%
% Outputs:
%   stim - struct with .controller (COM server) and .serial (device
%          serial number), or [] for MANUAL triggering
%
% Toolbox Dependencies:
%   None (external: Digitimer DS8R software COM server)

inventoryTimeoutS = 5;    % wait this long for the device inventory (s)
inventoryPollS    = 0.1;  % pause between inventory polls (s)

stim = [];
if ~cfg.useDS8R
    fprintf('DS8R control disabled in config: MANUAL triggering.\n');
    return;
end
try
    ctl = actxserver(cfg.ds8rProgID);
catch ME
    warning(['Could not start the DS8R COM server (%s). Is the DS8R ' ...
        'software installed? Falling back to MANUAL triggering.'], ...
        ME.message);
    return;
end
% The server inventories devices on creation; poll GetState briefly.
count = 0;
tInv  = tic;
while toc(tInv) < inventoryTimeoutS
    try
        col   = ctl.GetState;
        count = double(col.Count);
    catch
        count = 0;
    end
    if count > 0
        break;
    end
    pause(inventoryPollS);
end
if count < 1
    warning(['DS8R COM server started but found no device. Falling ' ...
        'back to MANUAL triggering.']);
    try
        delete(ctl);
    catch
    end
    return;
end
st = col.Items(0);
stim = struct();
stim.controller = ctl;
stim.serial     = double(st.SerialNumber);
fprintf('DS8R connected (serial %d).\n', stim.serial);
% Show the pulse-shape parameters that stay under device/software
% control, so the experimenter can confirm the unit is configured as
% expected.
try
    fprintf(['  Device settings: Demand=%g uA, DemandLimit=%g uA, ' ...
        'PulseWidth=%g us, Recovery=%g%%, Dwell=%g us\n'], ...
        double(st.Demand), double(st.DemandLimit), ...
        double(st.PulseWidth), double(st.Recovery), double(st.Dwell));
catch
end
end

function [demandUa, demandMa] = clampDemand(demandInMa, cfg)
%CLAMPDEMAND Apply the software current cap and DS8R resolution.
%
% Inputs:
%   demandInMa - requested stimulus current (mA)
%   cfg        - configuration struct (maxDemandMa)
%
% Outputs:
%   demandUa - clamped current rounded to the DS8R resolution (uA)
%   demandMa - the same current in mA
%
% Toolbox Dependencies:
%   None

demandResUa = 100;  % DS8R demand resolution (uA)

demandMa = min(max(demandInMa, 0), cfg.maxDemandMa);
demandUa = round(demandMa * 1000 / demandResUa) * demandResUa;
demandMa = demandUa / 1000;
end

function setStim(stim, cfg, demandUa)
%SETSTIM Push the stimulus settings to the DS8R and enable output.
%
%   Sets the current (plus optional pulse width / recovery / dwell) and
% enables output. A fresh state is fetched first, as recommended by the
% API (the state object is a static snapshot).
%
% Inputs:
%   stim     - struct from CONNECTDS8R
%   cfg      - configuration struct (maxDemandMa, pulseWidthUs,
%              recoveryPct, dwellUs)
%   demandUa - stimulus current (uA), already clamped by CLAMPDEMAND
%
% Outputs:
%   None
%
% Toolbox Dependencies:
%   None (external: Digitimer DS8R software COM server)

apiMinLimitUa = 100000;  % lowest DemandLimit the DS8R API accepts (uA)

col = stim.controller.GetState;
st  = col.Items(0);
% NOTE: the hardware demand limit must be >= 100 mA (API minimum), so
% the finer cfg.maxDemandMa cap is enforced in software by CLAMPDEMAND
% before this point.
try
    st.DemandLimit = max(cfg.maxDemandMa * 1000, apiMinLimitUa);
catch
end
st.Demand = demandUa;
if ~isempty(cfg.pulseWidthUs)
    st.PulseWidth = cfg.pulseWidthUs;
end
if ~isempty(cfg.recoveryPct)
    st.Recovery = cfg.recoveryPct;
end
if ~isempty(cfg.dwellUs)
    st.Dwell = cfg.dwellUs;
end
st.OutputEnable = true;
invoke(stim.controller, 'SetState', st, true);  % blocking apply
end

function fireStim(stim)
%FIRESTIM Trigger one immediate pulse with the device's current state.
%
% Inputs:
%   stim - struct from CONNECTDS8R
%
% Outputs:
%   None
%
% Toolbox Dependencies:
%   None (external: Digitimer DS8R software COM server)

col = stim.controller.GetState;
st  = col.Items(0);
invoke(st, 'Trigger');
end

function safeDisableOutput(stim)
%SAFEDISABLEOUTPUT Disable DS8R output without releasing the device.
%
%   Leaves the device "cold" between trials. Errors are ignored.
%
% Inputs:
%   stim - struct from CONNECTDS8R, or []
%
% Outputs:
%   None
%
% Toolbox Dependencies:
%   None (external: Digitimer DS8R software COM server)

if isempty(stim)
    return;
end
try
    col = stim.controller.GetState;
    st  = col.Items(0);
    st.OutputEnable = false;
    invoke(stim.controller, 'SetState', st, true);
catch
end
end

function safeStim(stim)
%SAFESTIM Disable DS8R output and release the COM server.
%
%   Safe to call with [] or more than once.
%
% Inputs:
%   stim - struct from CONNECTDS8R, or []
%
% Outputs:
%   None
%
% Toolbox Dependencies:
%   None (external: Digitimer DS8R software COM server)

if isempty(stim)
    return;
end
safeDisableOutput(stim);
try
    delete(stim.controller);
    fprintf('DS8R output disabled and COM server released.\n');
catch
end
end

%% ---------- Save folder & Center-plot saving ----------

function saveDir = ensureNLFolder(leg)
%ENSURENLFOLDER Create the "<Leg>NerveLocalization" save folder.
%
%   Asks for a parent folder and creates "<Leg>NerveLocalization"
% inside it (or reuses it if it already exists).
%
% Inputs:
%   leg - 'Left' or 'Right'
%
% Outputs:
%   saveDir - full path of the save folder, or '' if the user cancels
%             or it cannot be created (nothing is then saved)
%
% Toolbox Dependencies:
%   None

saveDir    = '';
folderName = sprintf('%sNerveLocalization', leg);
parent     = uigetdir(pwd, sprintf(['Select the folder in which to ' ...
    'create the "%s" folder'], folderName));
if isequal(parent, 0)
    warning('No save folder selected: nothing will be saved this session.');
    return;
end
nlDir = fullfile(parent, folderName);
if exist(nlDir, 'dir') ~= 7
    [ok, msg] = mkdir(nlDir);
    if ~ok
        warning('Could not create "%s" (%s). Nothing will be saved.', ...
            nlDir, msg);
        return;
    end
end
saveDir = nlDir;
fprintf('Saving to: %s\n', saveDir);
end

function baseName = saveCenterFigure(fig, saveDir, demandMa)
%SAVECENTERFIGURE Save a Center trial as .fig and .png.
%
%   Files are named by timestamp (and current, when known) so repeated
% Center trials do not overwrite each other.
%
% Inputs:
%   fig      - Center site figure handle
%   saveDir  - folder to save into
%   demandMa - stimulus current (mA); NaN in manual mode
%
% Outputs:
%   baseName - base filename (no extension), or '' on failure
%
% Toolbox Dependencies:
%   None

pngDpi = 150;  % PNG resolution (dpi), legible but small on disk

if isnan(demandMa)
    currentTag = 'NA';
else
    currentTag = strrep(sprintf('%.2fmA', demandMa), '.', 'p');
end
baseName = sprintf('Center_%s_%s', ...
    char(datetime('now', 'Format', 'yyyyMMdd_HHmmss')), currentTag);
figPath = fullfile(saveDir, [baseName '.fig']);
pngPath = fullfile(saveDir, [baseName '.png']);
try
    savefig(fig, figPath);
    print(fig, pngPath, '-dpng', sprintf('-r%d', pngDpi));
    fprintf('Saved Center trial: %s(.fig/.png)\n', ...
        fullfile(saveDir, baseName));
catch ME
    warning('Could not save Center figure (%s).', ME.message);
    baseName = '';
end
end

%% ---------- Per-trial logging (CSV + MAT) ----------

function session = buildSession(sessionTag, fs, ch, cfg, saveDir, leg)
%BUILDSESSION Build the session-level metadata saved with the trials.
%
%   Field names are part of the saved MAT format; keep them stable.
%
% Inputs:
%   sessionTag - session start timestamp (yyyyMMdd_HHmmss)
%   fs         - measured EMG rate (Hz)
%   ch         - channel struct (TA/SOL output and component names)
%   cfg        - configuration struct
%   saveDir    - save folder
%   leg        - 'Left' or 'Right'
%
% Outputs:
%   session - metadata struct
%
% Toolbox Dependencies:
%   None

session = struct();
session.SessionStart  = sessionTag;
session.Leg           = leg;
session.Fs_Hz         = fs;
session.TA_output     = ch.TA.output;
session.TA_component  = ch.TA.comp;
session.SOL_output    = ch.SOL.output;
session.SOL_component = ch.SOL.comp;
session.PulseWidth_us = cfg.pulseWidthUs;
session.MaxDemand_mA  = cfg.maxDemandMa;
session.PreMs         = cfg.preMs;
session.PostMs        = cfg.postMs;
session.MwinMs        = cfg.mWinMs;
session.HwinMs        = cfg.hWinMs;
session.BandpassHz    = cfg.bpBand;
session.SaveDir       = saveDir;
end

function trials = emptyTrials()
%EMPTYTRIALS Return a 0x0 trial struct array with every field defined.
%
%   Defining the fields up front keeps appends uniform. Field names are
% part of the saved CSV/MAT format; keep them stable.
%
% Inputs:
%   None
%
% Outputs:
%   trials - 0x0 struct array with the trial fields
%
% Toolbox Dependencies:
%   None

fieldNames = {'Trial', 'Timestamp', 'Leg', 'Site', 'Current_mA', ...
    'PulseWidth_us', 'Fs_Hz', 'ArtifactToM_ms', 'ArtifactToH_ms', ...
    'MToH_ms', 'M_peak', 'M_p2p', 'H_peak', 'H_p2p', 'M_present', ...
    'FrameGap', 'SavedImage', 't_ms', 'TA_filt', 'SOL_filt', ...
    'TA_raw', 'SOL_raw'};
args   = [fieldNames; repmat({{}}, 1, numel(fieldNames))];
trials = struct(args{:});
trials = trials([]);  % make it 0x0 but with the fields
end

function trials = logTrial(trials, csvPath, matPath, session, ...
    site, demandMa, cfg, fs, trace, cap, savedImg)
%LOGTRIAL Append one trial and rewrite the CSV and MAT logs.
%
%   The CSV holds the summary columns only; the MAT holds the full
% record (summary + raw and filtered waveform windows) and the session
% metadata. Both are rewritten in full after every trial so a crash
% loses at most the trial in progress.
%
% Inputs:
%   trials   - trial struct array so far (see EMPTYTRIALS)
%   csvPath  - summary CSV path ('' to skip)
%   matPath  - full-record MAT path ('' to skip)
%   session  - session metadata struct (see BUILDSESSION)
%   site     - stimulation site name
%   demandMa - stimulus current (mA); NaN in manual mode
%   cfg      - configuration struct
%   fs       - measured EMG rate (Hz)
%   trace    - processed trace struct (see PROCESSTRACE)
%   cap      - captured window struct (see CAPTUREONESTIM)
%   savedImg - saved Center image base name, or ''
%
% Outputs:
%   trials - trial struct array with this trial appended
%
% Toolbox Dependencies:
%   None

nTrial = numel(trials) + 1;
rec = struct();
rec.Trial          = nTrial;
rec.Timestamp      = char(datetime('now', ...
    'Format', 'yyyy-MM-dd HH:mm:ss'));
rec.Leg            = session.Leg;
rec.Site           = site;
rec.Current_mA     = demandMa;  % NaN in manual mode
rec.PulseWidth_us  = valOrNaN(cfg.pulseWidthUs);
rec.Fs_Hz          = fs;
rec.ArtifactToM_ms = iff(trace.mPresent, trace.mWave.tPk, NaN);
rec.ArtifactToH_ms = trace.artToHMs;
rec.MToH_ms        = trace.mToHMs;  % NaN if M absent
rec.M_peak         = trace.mWave.vPk;
rec.M_p2p          = trace.mP2p;
rec.H_peak         = trace.hReflex.vPk;
rec.H_p2p          = trace.hP2p;
rec.M_present      = double(trace.mPresent);
rec.FrameGap       = double(trace.gap);
rec.SavedImage     = savedImg;
% Waveforms (MAT only), stored as row vectors
rec.t_ms     = trace.t(:).';
rec.TA_filt  = trace.taFilt(:).';
rec.SOL_filt = trace.solFilt(:).';
rec.TA_raw   = cap.TA(:).';
rec.SOL_raw  = cap.SOL(:).';

if isempty(trials)
    trials = rec;
else
    trials(nTrial) = rec;
end

% Rewrite the CSV (summary columns only).
if ~isempty(csvPath)
    try
        summ = rmfield(trials, ...
            {'t_ms', 'TA_filt', 'SOL_filt', 'TA_raw', 'SOL_raw'});
        writetable(struct2table(summ, 'AsArray', true), csvPath);
    catch ME
        warning(['Could not write CSV (%s). If it is open in another ' ...
            'program (e.g. Excel), close it; the log will update on ' ...
            'the next trial.'], ME.message);
    end
end
% Rewrite the MAT (full record).
if ~isempty(matPath)
    try
        save(matPath, 'trials', 'session');
    catch ME
        warning('Could not write MAT (%s).', ME.message);
    end
end
end

function out = valOrNaN(val)
%VALORNAN Return VAL, or NaN if it is empty.
%
% Inputs:
%   val - any value, possibly []
%
% Outputs:
%   out - VAL, or NaN if VAL is empty
%
% Toolbox Dependencies:
%   None

if isempty(val)
    out = NaN;
else
    out = val;
end
end

%% ---------- Custom dialogs anchored top-right ----------
% MATLAB's built-in dialogs open screen-centered and cover the Center
% plot. Repositioning them after the fact was unreliable (it races
% their layout), so these build their own windows and set the position
% AT CREATION.

function [x, y] = topRightBox(cfg, width, height)
%TOPRIGHTBOX Bottom-left pixel origin for a top-right-anchored window.
%
% Inputs:
%   cfg    - configuration struct (dialogMarginPx)
%   width  - window width (px)
%   height - window height (px)
%
% Outputs:
%   x, y - window origin (px) placing it cfg.dialogMarginPx from the
%          screen's top-right corner
%
% Toolbox Dependencies:
%   None

screen = get(0, 'ScreenSize');
x = max(screen(3) - width - cfg.dialogMarginPx, 1);
y = max(screen(4) - height - cfg.dialogMarginPx, 1);
end

function [vals, ok] = inputDialogTR(cfg, prompts, titleStr, defaults)
%INPUTDIALOGTR Modal multi-field text-entry dialog, anchored top-right.
%
%   Pressing Enter in any field is the same as clicking OK. Moving focus
% out of a field (Tab, or clicking another field or Cancel) does NOT
% submit the dialog: an edit box's Callback fires on focus loss too, so
% it only submits when Enter caused it.
%
% Inputs:
%   cfg      - configuration struct (dialogMarginPx)
%   prompts  - char or cellstr of field prompts
%   titleStr - window title
%   defaults - cellstr of default field values (optional)
%
% Outputs:
%   vals - cellstr of entered values, one per prompt
%   ok   - true if OK/Enter was pressed, false if cancelled/closed
%
% Toolbox Dependencies:
%   None

dlgW     = 340;  % dialog width (px)
rowH     = 50;   % height per prompt + field row (px)
padTop   = 16;   % space above the first row (px)
padBot   = 50;   % space for the button row (px)
padSide  = 16;   % left/right inset of prompts and fields (px)
labelH   = 16;   % prompt text height (px)
editH    = 24;   % edit field height (px)
btnW     = 74;   % button width (px)
btnH     = 30;   % button height (px)
btnGap   = 8;    % gap between the OK and Cancel buttons (px)
btnBot   = 12;   % button row distance from the bottom (px)

prompts = cellstr(prompts);
nFields = numel(prompts);
ok      = false;
vals    = repmat({''}, 1, nFields);
lastKey = '';
dlgH    = padTop + nFields * rowH + padBot;
[x, y]  = topRightBox(cfg, dlgW, dlgH);
fig = figure('Name', titleStr, 'NumberTitle', 'Off', ...
    'MenuBar', 'None', 'ToolBar', 'None', 'Units', 'Pixels', ...
    'Position', [x y dlgW dlgH], 'Resize', 'Off', ...
    'WindowStyle', 'Modal', ...
    'Color', get(0, 'defaultUicontrolBackgroundColor'), ...
    'Tag', 'HreflexDialog', 'CloseRequestFcn', @(~, ~) onCancel());
edits = gobjects(1, nFields);
for ii = 1:nFields
    yTop = dlgH - padTop - (ii - 1) * rowH;
    uicontrol(fig, 'Style', 'Text', 'Units', 'Pixels', ...
        'Position', [padSide, yTop - labelH, dlgW - 2*padSide, labelH], ...
        'String', prompts{ii}, 'HorizontalAlignment', 'Left');
    defaultVal = '';
    if nargin >= 4 && numel(defaults) >= ii
        defaultVal = defaults{ii};
    end
    edits(ii) = uicontrol(fig, 'Style', 'Edit', 'Units', 'Pixels', ...
        'Position', [padSide, yTop - labelH - editH, ...
        dlgW - 2*padSide, editH], ...
        'String', defaultVal, 'HorizontalAlignment', 'Left', ...
        'BackgroundColor', 'White', ...
        'KeyPressFcn', @(~, evt) onKey(evt), ...
        'Callback', @(~, ~) onEditDone());
end
uicontrol(fig, 'Style', 'PushButton', 'String', 'OK', ...
    'Units', 'Pixels', ...
    'Position', [dlgW - padSide - 2*btnW - btnGap, btnBot, btnW, btnH], ...
    'Callback', @(~, ~) onOK());
uicontrol(fig, 'Style', 'PushButton', 'String', 'Cancel', ...
    'Units', 'Pixels', ...
    'Position', [dlgW - padSide - btnW, btnBot, btnW, btnH], ...
    'Callback', @(~, ~) onCancel());
uicontrol(edits(1));  % focus the first field
uiwait(fig);
if ishandle(fig)
    delete(fig);
end

    function onKey(evt)
    %ONKEY Remember the last key pressed in a field.
    lastKey = evt.Key;
    end

    function onEditDone()
    %ONEDITDONE Submit only when Enter (not focus loss) ended the edit.
    if any(strcmp(lastKey, {'return', 'enter'}))
        onOK();
    end
    end

    function onOK()
    %ONOK Collect the field values and close the dialog as OK.
    for kk = 1:nFields
        vals{kk} = get(edits(kk), 'String');
    end
    ok = true;
    uiresume(fig);
    end

    function onCancel()
    %ONCANCEL Close the dialog as cancelled.
    ok = false;
    uiresume(fig);
    end
end

function choice = choiceDialogTR(cfg, prompt, titleStr, options)
%CHOICEDIALOGTR Modal single-choice dialog, anchored top-right.
%
%   Shows one button per option. There is deliberately no default
% button, so Enter does not pick an option such as Stimulate (a safety
% rule confirmed in lab pilots).
%
% Inputs:
%   cfg      - configuration struct (dialogMarginPx)
%   prompt   - prompt text; newline characters split it into lines
%   titleStr - window title
%   options  - char or cellstr of button labels
%
% Outputs:
%   choice - the chosen option, or '' if cancelled/closed
%
% Toolbox Dependencies:
%   None

dlgW      = 300;  % dialog width (px)
btnH      = 30;   % button height (px)
btnGap    = 8;    % vertical gap between buttons (px)
padTop    = 14;   % space above the prompt (px)
padBot    = 14;   % space below the last button (px)
padSide   = 16;   % left/right inset of the prompt (px)
btnInset  = 40;   % left/right inset of the buttons (px)
lineH     = 16;   % height per prompt line (px)
promptPad = 10;   % extra prompt height beyond its lines (px)
promptGap = 8;    % gap between the prompt and the first button (px)

options     = cellstr(options);
nOptions    = numel(options);
choice      = '';
promptLines = strsplit(prompt, newline);
promptH     = numel(promptLines) * lineH + promptPad;
dlgH        = padTop + promptH + promptGap ...
    + nOptions * (btnH + btnGap) + padBot;
[x, y] = topRightBox(cfg, dlgW, dlgH);
fig = figure('Name', titleStr, 'NumberTitle', 'Off', ...
    'MenuBar', 'None', 'ToolBar', 'None', 'Units', 'Pixels', ...
    'Position', [x y dlgW dlgH], 'Resize', 'Off', ...
    'WindowStyle', 'Modal', ...
    'Color', get(0, 'defaultUicontrolBackgroundColor'), ...
    'Tag', 'HreflexDialog', 'CloseRequestFcn', @(~, ~) onClose());
uicontrol(fig, 'Style', 'Text', 'Units', 'Pixels', ...
    'Position', [padSide, dlgH - padTop - promptH, ...
    dlgW - 2*padSide, promptH], ...
    'String', promptLines, 'HorizontalAlignment', 'Left');
yBtn = dlgH - padTop - promptH - promptGap - btnH;
for ii = 1:nOptions
    uicontrol(fig, 'Style', 'PushButton', 'String', options{ii}, ...
        'Units', 'Pixels', ...
        'Position', [btnInset, yBtn, dlgW - 2*btnInset, btnH], ...
        'Callback', @(~, ~) onPick(options{ii}));
    yBtn = yBtn - (btnH + btnGap);
end
uiwait(fig);
if ishandle(fig)
    delete(fig);
end

    function onPick(picked)
    %ONPICK Record the chosen option and close the dialog.
    choice = picked;
    uiresume(fig);
    end

    function onClose()
    %ONCLOSE Close the dialog as cancelled.
    choice = '';
    uiresume(fig);
    end
end

function waitBox = waitBoxTR(cfg, msg)
%WAITBOXTR Non-modal status window with a Cancel button, top-right.
%
%   Closing it (Cancel or the window X) is how the caller detects
% cancellation.
%
% Inputs:
%   cfg - configuration struct (dialogMarginPx)
%   msg - status text; newline characters split it into lines
%
% Outputs:
%   waitBox - figure handle of the status window
%
% Toolbox Dependencies:
%   None

dlgW     = 330;  % window width (px)
btnAreaH = 44;   % space reserved for the Cancel button row (px)
lineH    = 16;   % height per message line (px)
padTop   = 20;   % space above the message (px)
textGap  = 12;   % gap between message and button row (px)
padSide  = 14;   % left/right inset of the message (px)
btnW     = 76;   % button width (px)
btnH     = 26;   % button height (px)
btnBot   = 10;   % button distance from the bottom (px)

msgLines = strsplit(msg, newline);
dlgH     = btnAreaH + numel(msgLines) * lineH + padTop;
[x, y]   = topRightBox(cfg, dlgW, dlgH);
waitBox = figure('Name', 'Waiting for stimulus', 'NumberTitle', 'Off', ...
    'MenuBar', 'None', 'ToolBar', 'None', 'Units', 'Pixels', ...
    'Position', [x y dlgW dlgH], 'Resize', 'Off', ...
    'Color', get(0, 'defaultUicontrolBackgroundColor'), ...
    'Tag', 'HreflexWait');
uicontrol(waitBox, 'Style', 'Text', 'Units', 'Pixels', ...
    'Position', [padSide, btnAreaH, dlgW - 2*padSide, ...
    dlgH - btnAreaH - textGap], ...
    'String', msgLines, 'HorizontalAlignment', 'Left');
uicontrol(waitBox, 'Style', 'PushButton', 'String', 'Cancel', ...
    'Units', 'Pixels', ...
    'Position', [dlgW - padSide - btnW, btnBot, btnW, btnH], ...
    'Callback', @(~, ~) delete(waitBox));
drawnow;
end

%% ---------- Vicon EMG acquisition ----------

function rate = getFrameRate(viconClient)
%GETFRAMERATE Vicon camera frame rate, with a fallback if unreported.
%
% Inputs:
%   viconClient - connected ViconDataStreamSDK.DotNET.Client
%
% Outputs:
%   rate - frame rate (Hz)
%
% Toolbox Dependencies:
%   None (external: Vicon DataStream SDK .NET assembly)

fallbackRateHz = 100;  % nominal lab Vicon camera rate (Hz)

rate = double(viconClient.GetFrameRate().FrameRateHz);
if rate <= 0
    rate = fallbackRateHz;
end
end

function fs = measureRate(viconClient, cfg, ch)
%MEASURERATE Derive the effective EMG rate from the TA sub-sample count.
%
%   Waits until the stream actually reports devices, then counts TA
% sub-samples per frame. After a fresh connect the first Success
% frame(s) often carry no device metadata yet, so the channel must not
% be queried too early.
%
% Inputs:
%   viconClient - connected ViconDataStreamSDK.DotNET.Client
%   cfg         - configuration struct (deviceName)
%   ch          - channel struct (TA output and component names)
%
% Outputs:
%   fs - effective EMG rate (Hz) = frame rate * sub-samples per frame
%
% Toolbox Dependencies:
%   None (external: Vicon DataStream SDK .NET assembly)

deviceTimeoutS  = 15;    % wait this long for any device to appear (s)
channelTimeoutS = 10;    % then this long for the TA channel (s)
pollS           = 0.02;  % pause between frame polls (s)

waitForDevices(viconClient, deviceTimeoutS);

% Devices are present; now the named EMG channel must resolve.
tChan = tic;
while true
    viconClient.GetFrame();
    out = viconClient.GetDeviceOutputSubsamples(cfg.deviceName, ...
        ch.TA.output, ch.TA.comp);
    if out.Result == ViconDataStreamSDK.DotNET.Result.Success ...
            && double(out.DeviceOutputSubsamples) >= 1
        break;
    end
    if toc(tChan) > channelTimeoutS
        error(['Devices are streaming, but "%s" / "%s" / "%s" did ' ...
            'not resolve. Check the device name and the TA sensor ' ...
            'number, and confirm the channel is visible in the Vicon ' ...
            'server device list.'], ...
            cfg.deviceName, ch.TA.output, ch.TA.comp);
    end
    pause(pollS);
end
nSub = double(out.DeviceOutputSubsamples);
fs   = getFrameRate(viconClient) * nSub;
end

function waitForDevices(viconClient, timeoutS)
%WAITFORDEVICES Pull frames until the server reports a device.
%
% Inputs:
%   viconClient - connected ViconDataStreamSDK.DotNET.Client
%   timeoutS    - give up (with an error) after this long (s)
%
% Outputs:
%   None
%
% Toolbox Dependencies:
%   None (external: Vicon DataStream SDK .NET assembly)

pollS = 0.02;  % pause between frame polls (s)

tWait = tic;
while true
    if viconClient.GetFrame().Result == ...
            ViconDataStreamSDK.DotNET.Result.Success ...
            && double(viconClient.GetDeviceCount().DeviceCount) > 0
        return;
    end
    if toc(tWait) > timeoutS
        error(['Connected to Vicon, but no devices appeared in the ' ...
            'stream within %g s.\n' ...
            '  1) Confirm the Vicon server (Nexus/Tracker) is in Live ' ...
            'mode and streaming.\n' ...
            '  2) Confirm the EMG device is present in the server''s ' ...
            'device list.\n' ...
            '  3) Rule out a leftover DataStream client from a ' ...
            'previous run: run "clear all" or restart MATLAB, then ' ...
            'try again.'], timeoutS);
    end
    pause(pollS);
end
end

function vals = getChannelSamples(viconClient, device, output, comp, ...
    nSub)
%GETCHANNELSAMPLES One channel's sub-samples from the current frame.
%
% Inputs:
%   viconClient - connected ViconDataStreamSDK.DotNET.Client
%   device      - Vicon device name
%   output      - device output name (e.g. 'Sensor 1')
%   comp        - output component name (e.g. 'IM EMG1')
%   nSub        - number of sub-samples in the current frame
%
% Outputs:
%   vals - nSub x 1 column vector, in temporal order
%
% Toolbox Dependencies:
%   None (external: Vicon DataStream SDK .NET assembly)

vals = zeros(nSub, 1);
for sub = 0:nSub - 1
    out = viconClient.GetDeviceOutputValue(device, output, comp, ...
        uint32(sub));
    vals(sub + 1) = double(out.Value);  % occluded samples come back as 0
end
end

function cap = captureOneStim(viconClient, ch, cfg, fs, site, triggerFcn)
%CAPTUREONESTIM Wait for the stimulation artifact and capture the window.
%
%   Watches raw TA for the stimulation artifact, then collects the full
% cfg.preMs to cfg.postMs window of TA and SOL. If TRIGGERFCN is a
% function handle, it is called ONCE (to fire the DS8R) as soon as the
% recorder is armed with a valid pre-stimulus baseline; if it is empty,
% the experimenter is expected to trigger the pulse manually.
%
%   Each new frame's samples are tested against a robust baseline over
% a trailing window ending cfg.guardMs before them: a sample is the
% artifact when its deviation from the baseline median exceeds
% cfg.kAmp robust sigmas AND its first difference exceeds cfg.kDeriv
% robust sigmas of the baseline's differences (the rising-edge gate
% rejects volitional TA bursts).
%
% Inputs:
%   viconClient - connected ViconDataStreamSDK.DotNET.Client
%   ch          - channel struct (TA/SOL output and component names)
%   cfg         - configuration struct
%   fs          - measured EMG rate (Hz)
%   site        - stimulation site name (for messages)
%   triggerFcn  - function handle that fires one pulse, or [] (manual)
%
% Outputs:
%   cap - struct with .TA and .SOL (column vectors), .t (ms, 0 =
%         artifact), .i0 (artifact index in the buffer), and .gap
%         (true if a Vicon frame was dropped within the window); [] if
%         cancelled or timed out
%
% Toolbox Dependencies:
%   None (external: Vicon DataStream SDK .NET assembly)

madToSigma = 1.4826;  % MAD -> sigma for Gaussian noise

nPre      = round(cfg.preMs / 1000 * fs);
nPost     = round(cfg.postMs / 1000 * fs);
nBaseline = round(cfg.baselineMs / 1000 * fs);
nGuard    = round(cfg.guardMs / 1000 * fs);
% samples required before watching starts
needBaseline = nBaseline + nGuard + nPre;

autoTrig  = ~isempty(triggerFcn);
triggered = false;

% Growing buffers; frameOf(k) = Vicon frame number of sample k
bufTA   = [];
bufSOL  = [];
frameOf = [];
i0      = [];  % artifact index (into buffers)
state   = 'baseline';

if autoTrig
    msg = sprintf(['Site "%s": arming recorder, then stimulating...' ...
        '\nClose this box to cancel.'], site);
else
    msg = sprintf(['Recording site "%s".\nDeliver ONE stimulation.' ...
        '\nClose this box to cancel.'], site);
end
stopBox = waitBoxTR(cfg, msg);
tStart  = tic;

while true
    if ~ishandle(stopBox)  % user cancelled
        cap = [];
        return;
    end
    if toc(tStart) > cfg.timeoutS
        if ishandle(stopBox)
            delete(stopBox);
        end
        if autoTrig && triggered
            warning(['No stimulation artifact detected after ' ...
                'triggering at "%s". Check that the DS8R output is ' ...
                'enabled and the current is non-zero, and that the ' ...
                'electrode is connected.'], site);
        else
            warning('Timed out waiting for a stimulus at site "%s".', ...
                site);
        end
        cap = [];
        return;
    end

    % Pull the next frame.
    if viconClient.GetFrame().Result ~= ...
            ViconDataStreamSDK.DotNET.Result.Success
        drawnow limitrate;
        continue;
    end
    frameNum = double(viconClient.GetFrameNumber().FrameNumber);
    nSub     = double(viconClient.GetDeviceOutputSubsamples( ...
        cfg.deviceName, ch.TA.output, ch.TA.comp).DeviceOutputSubsamples);
    if nSub < 1
        drawnow limitrate;
        continue;
    end

    newTA  = getChannelSamples(viconClient, cfg.deviceName, ...
        ch.TA.output, ch.TA.comp, nSub);
    newSOL = getChannelSamples(viconClient, cfg.deviceName, ...
        ch.SOL.output, ch.SOL.comp, nSub);

    prevN   = numel(bufTA);
    bufTA   = [bufTA; newTA];                      %#ok<AGROW>
    bufSOL  = [bufSOL; newSOL];                    %#ok<AGROW>
    frameOf = [frameOf; repmat(frameNum, nSub, 1)]; %#ok<AGROW>

    switch state
        case 'baseline'
            if numel(bufTA) >= needBaseline
                state = 'watch';
            end

        case 'watch'
            % Robust baseline over a trailing window ending nGuard
            % samples before the newly arrived ones.
            bEnd   = prevN - nGuard;  % last baseline sample index
            bStart = bEnd - nBaseline + 1;
            if bStart < 1
                drawnow limitrate;
                continue;
            end
            base   = bufTA(bStart:bEnd);
            med    = median(base);
            sigma  = madToSigma * median(abs(base - med)) + eps;
            dBase  = diff(base);
            sigmaD = madToSigma * median(abs(dBase - median(dBase))) ...
                + eps;
            thrAmp = cfg.kAmp * sigma;
            thrDrv = cfg.kDeriv * sigmaD;

            % The recorder is armed with a valid pre-stimulus baseline:
            % fire the pulse now (auto mode), exactly once. The artifact
            % will arrive in a later frame, after the software-trigger
            % latency.
            if autoTrig && ~triggered
                try
                    triggerFcn();
                catch ME
                    if ishandle(stopBox)
                        delete(stopBox);
                    end
                    warning(['DS8R trigger failed: %s. Aborting this ' ...
                        'trial.'], ME.message);
                    cap = [];
                    return;
                end
                triggered = true;
            end

            % Scan the newly arrived samples (with one-sample lookback
            % for diff).
            scan   = bufTA(prevN:end);  % includes last old sample
            dScan  = abs(diff(scan));
            ampHit = abs(scan(2:end) - med) > thrAmp;
            drvHit = dScan > thrDrv;
            hit    = ampHit & drvHit;
            if ~isempty(cfg.absFloor)
                hit = hit & (abs(scan(2:end) - med) > cfg.absFloor);
            end
            kHit = find(hit, 1, 'first');
            if ~isempty(kHit)
                i0    = prevN + kHit;  % absolute index of artifact
                state = 'collect';
            end

        case 'collect'
            if numel(bufTA) >= i0 + nPost
                if ishandle(stopBox)
                    delete(stopBox);
                end
                idx   = (i0 - nPre):(i0 + nPost);
                fnWin = frameOf(idx);
                gap   = ~all(diff(unique(fnWin, 'stable')) == 1);
                cap   = struct('TA', bufTA(idx), 'SOL', bufSOL(idx), ...
                    't', ((-nPre:nPost)' / fs * 1000), ...
                    'i0', i0, 'gap', gap);
                return;
            end
    end
    drawnow limitrate;
end
end

%% ---------- Filtering & peak detection ----------

function bp = designBandpass(fs, cfg)
%DESIGNBANDPASS Butterworth band-pass coefficients for display.
%
% Inputs:
%   fs  - EMG rate (Hz)
%   cfg - configuration struct (bpBand, bpOrder)
%
% Outputs:
%   bp - struct with .b and .a, or [] if the Signal Processing Toolbox
%        is unavailable (the caller then does DC removal only)
%
% Toolbox Dependencies:
%   Signal Processing Toolbox (optional)

wnMin = 1e-4;   % keep normalized cutoffs strictly inside (0, 1) for
wnMax = 0.999;  % BUTTER, even if bpBand is set near DC or Nyquist

bp = [];
if exist('butter', 'file') == 2 && exist('filtfilt', 'file') == 2
    wn = cfg.bpBand / (fs / 2);
    wn = min(max(wn, wnMin), wnMax);
    [b, a] = butter(cfg.bpOrder, wn, 'bandpass');
    bp = struct('b', b, 'a', a);
else
    warning(['Signal Processing Toolbox not found: showing ' ...
        'DC-removed EMG instead of %g-%g Hz band-pass.'], ...
        cfg.bpBand(1), cfg.bpBand(2));
end
end

function filtered = filtEMG(raw, bp)
%FILTEMG Zero-phase band-pass EMG, or DC removal if no filter.
%
% Inputs:
%   raw - EMG column vector
%   bp  - struct from DESIGNBANDPASS, or []
%
% Outputs:
%   filtered - filtered EMG, same size as RAW
%
% Toolbox Dependencies:
%   Signal Processing Toolbox (when BP is not empty)

if isempty(bp)
    filtered = raw - mean(raw);  % fallback: DC removal only
else
    filtered = filtfilt(bp.b, bp.a, raw);
end
end

function trace = processTrace(cap, cfg, bp)
%PROCESSTRACE Filter both channels and locate the M-wave and H-reflex.
%
%   The M-wave counts as present when its peak-to-peak amplitude exceeds
% cfg.mPresentFactor times the pre-stimulus Soleus noise peak-to-peak;
% the M-wave -> H-reflex latency is only reported when it is present.
%
% Inputs:
%   cap - captured window struct from CAPTUREONESTIM
%   cfg - configuration struct (mWinMs, hWinMs, mPresentFactor)
%   bp  - struct from DESIGNBANDPASS, or []
%
% Outputs:
%   trace - struct with .t, .taFilt, .solFilt, .mWave and .hReflex
%           (see PEAKINWINDOW), .mPresent, .artToHMs (artifact ->
%           H-reflex peak, ms), .mToHMs (M-wave -> H-reflex peak, ms;
%           NaN if no M-wave), .hP2p, .mP2p, and .gap
%
% Toolbox Dependencies:
%   Signal Processing Toolbox (when BP is not empty)

noiseEndMs = -1;  % pre-stimulus noise window ends 1 ms before artifact

t       = cap.t;
taFilt  = filtEMG(cap.TA, bp);
solFilt = filtEMG(cap.SOL, bp);

% Noise reference from the pre-stimulus baseline (window start to
% noiseEndMs)
preIdx = t < noiseEndMs;
if any(preIdx)
    noiseP2p = max(solFilt(preIdx)) - min(solFilt(preIdx));
else
    noiseP2p = max(solFilt) - min(solFilt);
end

mWave   = peakInWindow(solFilt, t, cfg.mWinMs);
hReflex = peakInWindow(solFilt, t, cfg.hWinMs);

mPresent = mWave.p2p > cfg.mPresentFactor * noiseP2p;

trace = struct();
trace.t        = t;
trace.taFilt   = taFilt;
trace.solFilt  = solFilt;
trace.mWave    = mWave;
trace.hReflex  = hReflex;
trace.mPresent = mPresent;
trace.artToHMs = hReflex.tPk;  % artifact -> H-reflex peak (ms)
trace.mToHMs   = iff(mPresent, hReflex.tPk - mWave.tPk, NaN);
trace.hP2p     = hReflex.p2p;
trace.mP2p     = mWave.p2p;
trace.gap      = cap.gap;
end

function pk = peakInWindow(sig, t, winMs)
%PEAKINWINDOW Largest absolute deflection and p2p within a window.
%
% Inputs:
%   sig   - signal column vector
%   t     - time vector (ms), same size as SIG
%   winMs - [start end] search window (ms)
%
% Outputs:
%   pk - struct with .tPk (peak time, ms), .vPk (signed peak value),
%        .p2p (peak-to-peak across the window), and .win (= WINMS)
%
% Toolbox Dependencies:
%   None

idx = find(t >= winMs(1) & t <= winMs(2));
seg = sig(idx);
[~, maxInd] = max(abs(seg));
pk.tPk = t(idx(maxInd));
pk.vPk = seg(maxInd);
pk.p2p = max(seg) - min(seg);
pk.win = winMs;
end

%% ---------- Figure placement & drawing ----------

function pos = sitePositions(cfg)
%SITEPOSITIONS Plus-shaped figure layout that mirrors electrode moves.
%
%   Up = top of screen, Down = bottom, Left = left, Right = right,
% Center = middle. Height is hard-clamped so the Up/Center/Down column
% (3 stacked figures plus margins) always fits the monitor without
% overlapping.
%
% Inputs:
%   cfg - configuration struct (figFracW, figFracH)
%
% Outputs:
%   pos - struct with one [x y w h] pixel position per site
%
% Toolbox Dependencies:
%   None

marginFrac = 0.02;  % screen-edge margin, fraction of the short side

screen = get(0, 'ScreenSize');  % [1 1 W H]
scrW   = screen(3);
scrH   = screen(4);
figW   = round(scrW * cfg.figFracW);
margin = round(min(scrW, scrH) * marginFrac);
figHMax = floor((scrH - 4*margin) / 3);
figH    = min(round(scrH * cfg.figFracH), figHMax);
cx    = round((scrW - figW) / 2);
cy    = round((scrH - figH) / 2);
right = scrW - figW - margin;
top   = scrH - figH - margin;
pos.Center = [cx,     cy,     figW, figH];
pos.Left   = [margin, cy,     figW, figH];
pos.Right  = [right,  cy,     figW, figH];
pos.Up     = [cx,     top,    figW, figH];
pos.Down   = [cx,     margin, figW, figH];
end

function fig = ensureFigure(figMap, site, posPix)
%ENSUREFIGURE Reuse this site's figure, or create it at its position.
%
% Inputs:
%   figMap - struct of existing site figure handles
%   site   - stimulation site name
%   posPix - [x y w h] pixel position for a new figure
%
% Outputs:
%   fig - the site's figure handle, cleared and raised
%
% Toolbox Dependencies:
%   None

if isfield(figMap, site) && ishandle(figMap.(site))
    fig = figMap.(site);
    clf(fig);
else
    fig = figure('Name', sprintf('Site: %s', site), ...
        'NumberTitle', 'Off', 'Units', 'Pixels', 'Position', posPix, ...
        'Color', 'White', 'Tag', 'HreflexSitePlot');
end
figure(fig);  % raise
end

function showArmed(fig, site)
%SHOWARMED Show an "armed, waiting for stimulation" placeholder.
%
% Inputs:
%   fig  - site figure handle
%   site - stimulation site name
%
% Outputs:
%   None
%
% Toolbox Dependencies:
%   None

clf(fig);
ax = axes('Parent', fig);
axis(ax, 'off');
text(0.5, 0.5, sprintf('ARMED: %s\n\nWaiting for stimulation ...', ...
    upper(site)), 'Parent', ax, 'HorizontalAlignment', 'Center', ...
    'FontSize', 13, 'FontWeight', 'Bold');
drawnow;
end

function showAborted(fig, site)
%SHOWABORTED Show a "capture cancelled / timed out" placeholder.
%
% Inputs:
%   fig  - site figure handle
%   site - stimulation site name
%
% Outputs:
%   None
%
% Toolbox Dependencies:
%   None

if ~ishandle(fig)
    return;
end
clf(fig);
ax = axes('Parent', fig);
axis(ax, 'off');
text(0.5, 0.5, sprintf('%s: capture cancelled / timed out', ...
    upper(site)), 'Parent', ax, 'HorizontalAlignment', 'Center', ...
    'FontSize', 12, 'Color', [0.6 0 0]);
drawnow;
end

function plotSite(fig, site, trace, cfg)
%PLOTSITE Draw one trial: TA with the artifact, Soleus with M and H.
%
%   The top axes show TA (the detection channel) with the stimulus
% artifact at t = 0; the bottom axes show Soleus with the shaded M-wave
% and H-reflex search windows, the detected peaks, and the artifact ->
% H and M -> H latencies. A warning banner appears if a Vicon frame was
% dropped within the window.
%
% Inputs:
%   fig   - site figure handle
%   site  - stimulation site name
%   trace - processed trace struct from PROCESSTRACE (plus .demandMa)
%   cfg   - configuration struct (mWinMs, hWinMs)
%
% Outputs:
%   None
%
% Toolbox Dependencies:
%   None

yPadFrac   = 0.25;  % Soleus y-limit padding, fraction of data range,
                    % leaving room for the latency annotation
labelOffFr = 0.12;  % latency label offset from the H peak, fraction
                    % of data range

figure(fig);
clf(fig);
t = trace.t;

axTA = subplot(2, 1, 1, 'Parent', fig);
plot(axTA, t, trace.taFilt, 'Color', [0.15 0.15 0.15]);
hold(axTA, 'on');
ylTA = ylim(axTA);
vline(axTA, 0, ylTA, [1 0 0]);  % stimulus artifact @ t = 0
if isfield(trace, 'demandMa') && ~isnan(trace.demandMa)
    titleTA = sprintf('%s  —  Tibialis Anterior   (I = %.2f mA)', ...
        upper(site), trace.demandMa);
else
    titleTA = sprintf('%s  —  Tibialis Anterior (detection channel)', ...
        upper(site));
end
title(axTA, titleTA);
ylabel(axTA, 'EMG (units)');
grid(axTA, 'on');
xlim(axTA, [t(1) t(end)]);

axSOL = subplot(2, 1, 2, 'Parent', fig);
% Plot the Soleus trace first so the y-limits come from the data, then
% shade the search windows to those limits (patches drawn last would
% otherwise rescale the axis).
plot(axSOL, t, trace.solFilt, 'Color', [0 0 0.55], 'LineWidth', 1);
hold(axSOL, 'on');
yRange = max(trace.solFilt) - min(trace.solFilt);
if yRange == 0
    yRange = 1;
end
yl = [min(trace.solFilt) max(trace.solFilt)] + yPadFrac * yRange * [-1 1];
ylim(axSOL, yl);
shadeWindow(axSOL, cfg.mWinMs, [0.85 0.92 1.00], yl);  % M (blue-ish)
shadeWindow(axSOL, cfg.hWinMs, [0.90 1.00 0.88], yl);  % H (green-ish)
vline(axSOL, 0, yl, [1 0 0]);  % stimulus artifact @ t = 0

% Mark the M-wave (if present) and H-reflex peaks.
if trace.mPresent
    plot(axSOL, trace.mWave.tPk, trace.mWave.vPk, 'v', ...
        'MarkerFaceColor', [0 0.4 0.8], 'MarkerEdgeColor', 'Black', ...
        'MarkerSize', 8);
    text(axSOL, trace.mWave.tPk, trace.mWave.vPk, '  M', ...
        'Color', [0 0.4 0.8], 'FontWeight', 'Bold', ...
        'VerticalAlignment', 'Bottom');
end
plot(axSOL, trace.hReflex.tPk, trace.hReflex.vPk, '^', ...
    'MarkerFaceColor', [0 0.55 0], 'MarkerEdgeColor', 'Black', ...
    'MarkerSize', 9);

% Two latencies above (or below) the H-reflex peak.
yTxt = trace.hReflex.vPk ...
    + sign(trace.hReflex.vPk + eps) * labelOffFr * yRange;
vAlign = iff(trace.hReflex.vPk >= 0, 'Bottom', 'Top');
text(axSOL, trace.hReflex.tPk, yTxt, ...
    {sprintf('artifact\\rightarrowH: %.1f ms', trace.artToHMs), ...
    sprintf('M\\rightarrowH: %s ms', latStr(trace.mToHMs))}, ...
    'Color', [0 0.4 0], 'FontWeight', 'Bold', 'FontSize', 10, ...
    'HorizontalAlignment', 'Center', 'VerticalAlignment', vAlign, ...
    'BackgroundColor', 'White', 'EdgeColor', [0 0.4 0], 'Margin', 2);

titleSOL = sprintf('Soleus  —  H p2p = %.3g   |   M p2p = %.3g%s', ...
    trace.hP2p, trace.mP2p, ...
    iff(trace.mPresent, '', ' (M-wave weak/absent)'));
title(axSOL, titleSOL);
xlabel(axSOL, 'Time re: stimulus artifact (ms)');
ylabel(axSOL, 'EMG (units)');
grid(axSOL, 'on');
xlim(axSOL, [t(1) t(end)]);
ylim(axSOL, yl);

if trace.gap
    annotation(fig, 'textbox', [0.15 0.46 0.7 0.05], 'String', ...
        ['WARNING: dropped Vicon frame(s) within this window — ' ...
        'trace may be discontinuous.'], ...
        'Color', [0.7 0 0], 'EdgeColor', 'None', ...
        'HorizontalAlignment', 'Center', 'FontWeight', 'Bold');
end

linkaxes([axTA axSOL], 'x');
drawnow;
end

function vline(ax, x, yl, color)
%VLINE Version-safe vertical line.
%
%   Avoids XLINE's axes-target syntax, which R2021a does not support.
%
% Inputs:
%   ax    - target axes
%   x     - x position
%   yl    - [ymin ymax] extent
%   color - RGB triplet
%
% Outputs:
%   None
%
% Toolbox Dependencies:
%   None

line(ax, [x x], yl, 'Color', color, 'LineWidth', 1, ...
    'HandleVisibility', 'Off');
end

function shadeWindow(ax, winMs, color, yl)
%SHADEWINDOW Shade a time window behind the axes' traces.
%
% Inputs:
%   ax    - target axes
%   winMs - [start end] window (ms)
%   color - RGB fill color
%   yl    - [ymin ymax] extent
%
% Outputs:
%   None
%
% Toolbox Dependencies:
%   None

faceAlpha = 0.6;  % keep the trace legible through the shading

patchH = patch(ax, [winMs(1) winMs(2) winMs(2) winMs(1)], ...
    [yl(1) yl(1) yl(2) yl(2)], color, 'EdgeColor', 'None', ...
    'FaceAlpha', faceAlpha, 'HandleVisibility', 'Off');
uistack(patchH, 'bottom');  % keep the shading behind the EMG trace
end

%% ---------- Small helpers ----------

function str = latStr(latMs)
%LATSTR Format a latency (ms) for display, or 'n/a' if NaN.
%
% Inputs:
%   latMs - latency (ms), possibly NaN
%
% Outputs:
%   str - formatted latency
%
% Toolbox Dependencies:
%   None

if isnan(latMs)
    str = 'n/a';
else
    str = sprintf('%.1f', latMs);
end
end

function str = iStr(demandMa)
%ISTR Format a stimulus current (mA) for display, or 'n/a' if NaN.
%
% Inputs:
%   demandMa - stimulus current (mA), possibly NaN
%
% Outputs:
%   str - formatted current
%
% Toolbox Dependencies:
%   None

if isnan(demandMa)
    str = 'n/a';
else
    str = sprintf('%.2f', demandMa);
end
end

function str = pwStr(cfg)
%PWSTR Format the configured pulse width for display.
%
% Inputs:
%   cfg - configuration struct (pulseWidthUs)
%
% Outputs:
%   str - e.g. '1000 us', or '(device setting)' if not configured
%
% Toolbox Dependencies:
%   None

if isempty(cfg.pulseWidthUs)
    str = '(device setting)';
else
    str = sprintf('%g us', cfg.pulseWidthUs);
end
end

function out = iff(cond, valTrue, valFalse)
%IFF Inline conditional: VALTRUE if COND, else VALFALSE.
%
%   Both values are evaluated before the call.
%
% Inputs:
%   cond     - logical scalar
%   valTrue  - value returned when COND is true
%   valFalse - value returned when COND is false
%
% Outputs:
%   out - the selected value
%
% Toolbox Dependencies:
%   None

if cond
    out = valTrue;
else
    out = valFalse;
end
end
