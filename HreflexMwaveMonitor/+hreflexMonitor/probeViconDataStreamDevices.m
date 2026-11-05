function report = probeViconDataStreamDevices(options)
%PROBEVICONDATASTREAMDEVICES Read-only Vicon DataStream device probe.
%
%   Opens a second, independent Vicon DataStream SDK client and lists
% every streamed device, output, and component, enabling ONLY device
% data (EnableDeviceData()) -- never marker, segment, or unlabeled-marker
% data, which this probe (and the monitor it gates) never needs. This is
% the gating first deliverable for the near-real-time H-reflex M-wave
% monitor: it confirms, on the machine the monitor will run on, that the
% Delsys EMG channels and the Arduino Stimulator_Trigger_Sync_* trigger
% channels are actually exposed as live DataStream device outputs (not
% just written to the C3D), at the expected ~2 kHz analog subsample rate,
% before any monitor code is built against that assumption.
%
%   Read-only: connects, samples frames, prints a report, and disconnects
% (on error or Ctrl+C too). Never opens the Arduino serial port, never
% sends a treadmill or stimulation command, never writes to any datlog.
% Nexus's DataStream server supports multiple concurrent ClientPull
% clients, but this probe's CPU load has not been measured alongside the
% control loop: run it first with no control instance running.
%
%   RUN WITH THE RIGHT NEXUS SETUP: Nexus must be in Live mode with the
% HreflexEMGDataCollection system/pipeline profile selected, since the
% trigger channels are absent otherwise (see studies/SpinalAdapt/
% README.md). Trigger channels read flat unless a pulse fires while the
% probe samples, so fire stimuli during the run to see 0 to ~4.3 V.
%
%   NOTE ON UNVERIFIED SDK SURFACE: the connection sequence, device
% wait, subsample count, and four-argument value read below mirror
% HREFLEXMAPPINGTOOL, which uses them against live EMG. The enumeration
% calls (GetDeviceName, GetDeviceOutputCount,
% GetDeviceOutputComponentName) are not otherwise used in this repo, so
% this probe is their first exercise here. Zero-based indexing for them
% is inferred from this .NET client's other index arguments
% (GetSubjectName(0) in HREFLEXOGWITHAUDIO, subsample 0 in
% HREFLEXMAPPINGTOOL). If an enumeration call errors or reports an index
% failure on the installed SDK, consult that SDK's own example scripts
% under 'C:\Program Files\Vicon\DataStream SDK\Win64\' for the exact
% method names and indexing; do not guess further without confirming
% against that reference.
%
% Inputs:
%   None
%
% Optional Name-Value Inputs:
%   hostName  - char; DataStream server address (default:
%               'localhost:801')
%   numFrames - number of frames to sample (default: 500, about 5 s at
%               100 Hz; long enough to catch a trigger pulse during a
%               stimulation trial, which stimulates at least every 2
%               strides outside intensity changes)
%
% Outputs:
%   report - struct with fields:
%              deviceNames    - cell array of every streamed device name
%              channels       - table, one row per device output
%                               component: device, output, component,
%                               isEMG, isTrigger, subsamples (per frame,
%                               on the last frame it was read), stdValue,
%                               minValue, maxValue (NaN if never read).
%                               EMG and trigger rows use every subsample;
%                               other rows use each frame's first
%                               subsample, to bound the probe's load.
%              indexFailures  - cell array of the enumeration calls that
%                               did not return Success; non-empty suggests
%                               the indexing assumption above is wrong
%              numFramesRead  - frames successfully read
%              hasEMG         - true if any output or component name
%                               contains 'EMG'
%              hasStimTrigger - true if any device, output, or component
%                               name contains 'Stimulator Trigger Sync',
%                               ignoring spaces and underscores
%
% Toolbox Dependencies:
%   None (external: Vicon DataStream SDK, .NET assembly)
%
% See also RUNHREFLEXMWAVEMONITOR, HREFLEXMAPPINGTOOL,
%   NIRSHREFLEXARDUINOOPENLOOPWITHAUDIO.

arguments
    options.hostName  (1,:) char = 'localhost:801'
    options.numFrames (1,1) double ...
        {mustBePositive, mustBeInteger} = 500
end

deviceTimeoutS = 15;   % s; wait this long for any device to appear,
                       % same as HREFLEXMAPPINGTOOL

%% Connect a Second, Independent DataStream Client (Device Data Only)
client = connectDataStream(options.hostName);
cleanupClient = onCleanup(@() safeDisconnect(client));

%% Enumerate Devices, Outputs, and Components
waitForDevices(client, deviceTimeoutS);
[deviceNames, channels, indexFailures] = enumerateChannels(client);

%% Sample Frames for Subsample Counts and Signal Statistics
[subsamples, samples, numFramesRead] = ...
    sampleChannels(client, channels, options.numFrames);

%% Summarize Each Channel
numChannels = numel(channels);
stdValue = nan(numChannels, 1);
minValue = nan(numChannels, 1);
maxValue = nan(numChannels, 1);
for cc = 1:numChannels
    if ~isempty(samples{cc})
        stdValue(cc) = std(samples{cc}, 'omitnan');
        minValue(cc) = min(samples{cc}, [], 'omitnan');
        maxValue(cc) = max(samples{cc}, [], 'omitnan');
    end
end

device     = {channels.device}';
output     = {channels.output}';
component  = {channels.component}';
isEMG      = [channels.isEMG]';
isTrigger  = [channels.isTrigger]';
channelTbl = table(device, output, component, isEMG, isTrigger, ...
    subsamples, stdValue, minValue, maxValue);

report.deviceNames    = deviceNames;
report.channels       = channelTbl;
report.indexFailures  = indexFailures;
report.numFramesRead  = numFramesRead;
report.hasEMG         = any(isEMG);
report.hasStimTrigger = any(isTrigger);

printReport(report, options.numFrames);

end

function client = connectDataStream(hostName)
%CONNECTDATASTREAM Load the SDK and connect a device-data-only client.
%
%   Mirrors HREFLEXMAPPINGTOOL's connection sequence: the assembly comes
% from the installed SDK folder, then the MATLAB path, then a file
% picker, and the connection is retried until a timeout.
%
% Inputs:
%   hostName - char; DataStream server address
%
% Outputs:
%   client - connected ViconDataStreamSDK.DotNET.Client
%
% Toolbox Dependencies:
%   None (external: Vicon DataStream SDK .NET assembly)

sdkPath         = 'C:\Program Files\Vicon\DataStream SDK\Win64';
sdkAssembly     = 'ViconDataStreamSDK_DotNET.dll';
connectTimeoutS = 30;     % s; give up connecting after this long
connectRetryS   = 0.05;   % s; pause between connection attempts

asmPath = fullfile(sdkPath, sdkAssembly);
if exist(asmPath, 'file') ~= 2
    asmPath = which(sdkAssembly);
    if isempty(asmPath)
        [fileName, folder] = uigetfile('*.dll', ...
            'Select ViconDataStreamSDK_DotNET.dll');
        if isequal(fileName, 0)
            error('probeViconDataStreamDevices:sdkNotFound', ...
                'SDK assembly not found; cannot continue.');
        end
        asmPath = fullfile(folder, fileName);
    end
end
NET.addAssembly(asmPath);

client = ViconDataStreamSDK.DotNET.Client();
tConn = tic;
while ~client.IsConnected().Connected
    client.Connect(hostName);
    if toc(tConn) > connectTimeoutS
        error('probeViconDataStreamDevices:connectTimeout', ...
            'Could not connect to Vicon at %s within %g s.', ...
            hostName, connectTimeoutS);
    end
    pause(connectRetryS);
end

client.EnableDeviceData();     % device data ONLY -- see header note
client.SetBufferSize(1);
client.SetStreamMode(ViconDataStreamSDK.DotNET.StreamMode.ClientPull);

end

function safeDisconnect(client)
%SAFEDISCONNECT Disconnect from Vicon, ignoring teardown errors.
%
% Inputs:
%   client - ViconDataStreamSDK.DotNET.Client
%
% Outputs:
%   None
%
% Toolbox Dependencies:
%   None (external: Vicon DataStream SDK .NET assembly)

try
    if client.IsConnected().Connected
        client.Disconnect();
    end
catch
    % ignore errors during teardown
end

end

function waitForDevices(client, timeoutS)
%WAITFORDEVICES Pull frames until the server reports a device.
%
%   Device metadata appears only one or more frames after the first
% successful GetFrame() (see HREFLEXMAPPINGTOOL's lab-pilot design
% rules), so a count read straight after connecting can falsely be 0.
%
% Inputs:
%   client   - connected ViconDataStreamSDK.DotNET.Client
%   timeoutS - give up (with an error) after this long (s)
%
% Outputs:
%   None
%
% Toolbox Dependencies:
%   None (external: Vicon DataStream SDK .NET assembly)

pollS = 0.02;   % s; pause between frame polls

tWait = tic;
while true
    if isSuccess(client.GetFrame()) ...
            && double(client.GetDeviceCount().DeviceCount) > 0
        return;
    end
    if toc(tWait) > timeoutS
        error('probeViconDataStreamDevices:noDevices', ...
            ['Connected to Vicon, but no devices appeared within ' ...
            '%g s. Confirm Nexus is in Live mode and streaming, and ' ...
            'rule out a leftover client from a previous run ("clear ' ...
            'all" or restart MATLAB).'], timeoutS);
    end
    pause(pollS);
end

end

function [deviceNames, channels, indexFailures] = ...
    enumerateChannels(client)
%ENUMERATECHANNELS List every device output component in the stream.
%
%   Indices are zero-based -- see the header note on unverified SDK
% surface. A failed call is recorded rather than thrown, so one bad
% index cannot hide the rest of the stream.
%
% Inputs:
%   client - connected ViconDataStreamSDK.DotNET.Client, on a frame that
%            already reports devices
%
% Outputs:
%   deviceNames   - cell array of device names that resolved
%   channels      - struct array with fields device, output, component,
%                   isEMG, isTrigger
%   indexFailures - cell array of descriptions of failed calls
%
% Toolbox Dependencies:
%   None (external: Vicon DataStream SDK .NET assembly)

deviceNames   = {};
indexFailures = {};
channels = struct('device', {}, 'output', {}, 'component', {}, ...
    'isEMG', {}, 'isTrigger', {});

deviceCount = double(client.GetDeviceCount().DeviceCount);
for dd = 0:deviceCount - 1
    deviceInfo = client.GetDeviceName(uint32(dd));
    if ~isSuccess(deviceInfo)
        indexFailures{end+1, 1} = sprintf( ...
            'GetDeviceName(%d)', dd); %#ok<AGROW>
        continue;
    end
    deviceName = char(deviceInfo.DeviceName);
    deviceNames{end+1, 1} = deviceName; %#ok<AGROW>

    outputCount = double( ...
        client.GetDeviceOutputCount(deviceName).DeviceOutputCount);
    for oo = 0:outputCount - 1
        outputInfo = client.GetDeviceOutputComponentName( ...
            deviceName, uint32(oo));
        if ~isSuccess(outputInfo)
            indexFailures{end+1, 1} = sprintf( ...
                'GetDeviceOutputComponentName(''%s'', %d)', ...
                deviceName, oo); %#ok<AGROW>
            continue;
        end
        outputName = char(outputInfo.DeviceOutputName);
        compName   = char(outputInfo.DeviceOutputComponentName);

        % C3D names replace the live names' spaces with underscores
        % (live 'Sensor 7' / 'IM EMG7' is C3D Sensor_7_IM_EMG7), so match
        % ignoring both. Device names count for the trigger only: every
        % output of the 'EMG' device would otherwise match as EMG.
        isEMG = contains(normalizeName([outputName compName]), 'emg');
        isTrigger = contains( ...
            normalizeName([deviceName outputName compName]), ...
            'stimulatortriggersync');

        channels(end+1, 1) = struct('device', deviceName, ...
            'output', outputName, 'component', compName, ...
            'isEMG', isEMG, 'isTrigger', isTrigger); %#ok<AGROW>
    end
end

end

function normalized = normalizeName(name)
%NORMALIZENAME Lowercase a channel name and drop spaces and underscores.
%
% Inputs:
%   name - char; channel name
%
% Outputs:
%   normalized - char; name in a form comparable across live and C3D
%                naming
%
% Toolbox Dependencies:
%   None

normalized = lower(regexprep(name, '[\s_]', ''));

end

function [subsamples, samples, numFramesRead] = ...
    sampleChannels(client, channels, numFrames)
%SAMPLECHANNELS Read each channel's subsamples over a run of frames.
%
%   Each frame's subsamples take one .NET call apiece, so only the EMG
% and trigger channels this monitor depends on are read in full; every
% other channel contributes its first subsample per frame.
%
% Inputs:
%   client    - connected ViconDataStreamSDK.DotNET.Client
%   channels  - struct array from ENUMERATECHANNELS
%   numFrames - number of frames to attempt
%
% Outputs:
%   subsamples    - numChannels x 1 subsamples per frame, from the last
%                   frame each channel was read (0 if never read)
%   samples       - numChannels x 1 cell array of sampled values (column
%                   vectors; NaN marks a failed read)
%   numFramesRead - frames successfully read
%
% Toolbox Dependencies:
%   None (external: Vicon DataStream SDK .NET assembly)

numChannels   = numel(channels);
subsamples    = zeros(numChannels, 1);
samples       = cell(numChannels, 1);
numFramesRead = 0;

for ff = 1:numFrames
    if ~isSuccess(client.GetFrame())
        continue;
    end
    numFramesRead = numFramesRead + 1;

    for cc = 1:numChannels
        ch = channels(cc);
        countInfo = client.GetDeviceOutputSubsamples( ...
            ch.device, ch.output, ch.component);
        if ~isSuccess(countInfo)
            continue;   % skip a bad read; try again next frame
        end
        subsamples(cc) = double(countInfo.DeviceOutputSubsamples);

        numToRead = min(subsamples(cc), 1);
        if ch.isEMG || ch.isTrigger
            numToRead = subsamples(cc);
        end
        values = nan(numToRead, 1);
        for sub = 0:numToRead - 1   % subsample index is zero-based
            valueInfo = client.GetDeviceOutputValue( ...
                ch.device, ch.output, ch.component, uint32(sub));
            if isSuccess(valueInfo)
                values(sub + 1) = double(valueInfo.Value);
            end
        end
        samples{cc} = [samples{cc}; values];
    end
end

end

function tf = isSuccess(sdkOutput)
%ISSUCCESS True if a DataStream SDK call's output reports Success.
%
% Inputs:
%   sdkOutput - output object of a DataStream SDK call
%
% Outputs:
%   tf - logical
%
% Toolbox Dependencies:
%   None (external: Vicon DataStream SDK .NET assembly)

tf = sdkOutput.Result == ViconDataStreamSDK.DotNET.Result.Success;

end

function printReport(report, numFrames)
%PRINTREPORT Print the channel list, checks, and warnings.
%
% Inputs:
%   report    - report struct assembled by PROBEVICONDATASTREAMDEVICES
%   numFrames - number of frames attempted
%
% Outputs:
%   None
%
% Toolbox Dependencies:
%   None

tbl = report.channels;

fprintf('=== Vicon DataStream Device Probe ===\n');
fprintf('Frames read: %d of %d\n', report.numFramesRead, numFrames);
fprintf('Devices found: %d\n', numel(report.deviceNames));
for dd = 1:numel(report.deviceNames)
    fprintf('  %s (%d channels)\n', report.deviceNames{dd}, ...
        sum(strcmp(tbl.device, report.deviceNames{dd})));
end

fprintf('\nDevice | Output | Component | Subsamples/frame | Std | ');
fprintf('Min | Max | Tag\n');
for cc = 1:height(tbl)
    tag = '';
    if tbl.isEMG(cc)
        tag = 'EMG';
    elseif tbl.isTrigger(cc)
        tag = 'TRIGGER';
    end
    if ~(tbl.stdValue(cc) > 0)
        tag = strtrim([tag ' FLAT']);
    end
    fprintf('%s | %s | %s | %d | %.3g | %.3g | %.3g | %s\n', ...
        tbl.device{cc}, tbl.output{cc}, tbl.component{cc}, ...
        tbl.subsamples(cc), tbl.stdValue(cc), tbl.minValue(cc), ...
        tbl.maxValue(cc), tag);
end

numLiveEMG = sum(tbl.isEMG & tbl.stdValue > 0);
fprintf('\nEMG channels found: %d (%d not flat)\n', ...
    sum(tbl.isEMG), numLiveEMG);
fprintf('Stimulator trigger channels found: %d\n', sum(tbl.isTrigger));
fprintf(['NOTE: expect ~20 subsamples/frame for 2 kHz EMG at 100 Hz ' ...
    'Vicon frames. In prior C3D exports, the plain EMG<n> field was ' ...
    'flat and IM_EMG<n> carried the signal.\n']);

%% Warn About Results That Would Block the Monitor
if ~isempty(report.indexFailures)
    warning('probeViconDataStreamDevices:indexFailures', ...
        ['%d enumeration call(s) failed, so channels may be missing ' ...
        '(zero-based indexing may be wrong; see the header note):' ...
        '\n  %s'], numel(report.indexFailures), ...
        strjoin(report.indexFailures, '\n  '));
end
if ~report.hasEMG
    warning('probeViconDataStreamDevices:noEMG', ...
        'No EMG channels found. Check the listing above for their names.');
elseif numLiveEMG == 0
    warning('probeViconDataStreamDevices:flatEMG', ...
        ['Every EMG channel is flat. Confirm the Delsys sensors are ' ...
        'on and streaming.']);
end
if ~report.hasStimTrigger
    warning('probeViconDataStreamDevices:noTrigger', ...
        ['No stimulator trigger channels found. Confirm the ' ...
        'HreflexEMGDataCollection profile is selected in Nexus, then ' ...
        'check the listing above in case their live names differ.']);
elseif ~any(tbl.isTrigger & tbl.stdValue > 0)
    fprintf(['NOTE: trigger channels stayed flat, as expected if no ' ...
        'pulse fired during sampling. Re-run while firing stimuli to ' ...
        'confirm they reach ~4.3 V live.\n']);
end

end
