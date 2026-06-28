function [RTOTime,LTOTime,RHSTime,LHSTime,commSendTime,commSendFrame] = ...
    NirsHreflexArduinoOpenLoopWithAudio(velL,velR,FzThreshold, ...
    profilename,numAudioCountDown,isCalibration,oxysoft_present, ...
    hreflex_present,stimL,stimR)
%NIRSHREFLEXARDUINOOPENLOOPWITHAUDIO Open loop split-belt controller with
%fNIRS event markers, audio feedback, and Arduino-timed H-reflex
%stimulation.
%
%   This is adapted from the open loop controller with audio feedback.
%   NIRS events for tied, ramp, split, rest (optional, if exists, always
%   rest for 20 seconds) are added. When to log a NIRS event is
%   determined by parsing velL/velR (0 speeds are treated as rest; the
%   parse also finds tied, ramp, split, and post segments).
%
%   H-reflex stimulation timing is split between this controller and the
%   Arduino running
%   HreflexStimArduino/triggerStimWithGaitStateMachine_SpeedIndependent/.
%   The Arduino owns the precise 50%-single-stance pulse timing: it runs
%   its own gait-event state machine and fires the stimulus locally. This
%   controller sends serial command 0 once (before the main loop) to
%   start the Arduino's state machine, sends a per-stride gate byte (1 =
%   stim left, 2 = stim right) at single-stance onset to flag which leg
%   to stimulate, and sends command 3 (in the closing routine) to stop
%   the Arduino's state machine. Do not change these command bytes
%   without re-uploading compatible Arduino firmware.
%
%   --- Doc from the open loop controller (controlSpeedWithSteps_edit1
%   with audio countdown) ---
%   This function takes two vectors of speeds (one for each treadmill
%   belt) and successively updates the belt speed upon ipsilateral
%   toe-off. The function only updates the belts alternately, i.e., a
%   single belt speed cannot be updated twice without the other being
%   updated. The first value for velL and velR is the initial desired
%   speed, and new speeds will be sent for the following N-1 steps,
%   where N is the length of velL.
%
%   Feature Improvement TODO: at this point, the arguments isCalibration,
%   oxysoft_present, hreflex_present are not really accessible when going
%   through the UI flow of using AdaptationGUI; they are only settable
%   via code and setting params to be global.
%
% Inputs:
%   velL - Nx1 left belt speed profile (mm/s); NaN entries are
%          self-paced strides
%   velR - Nx1 right belt speed profile (mm/s); NaN entries are
%          self-paced strides
%   FzThreshold - force-plate stance threshold (N); overridden to a
%          robust hard floor inside the function regardless of input
%   profilename - name used for the saved datlog filename
%   numAudioCountDown - stride indices at which to play a 3-2-1 audio
%          countdown before a speed change, terminated by -1 (count down
%          at treadmill start/stop only)
%   isCalibration - true for an H-reflex calibration trial (disables
%          fNIRS, plays per-side calibration audio instead of NIRS cues)
%   oxysoft_present - true to connect to Oxysoft fNIRS software
%   hreflex_present - true to open the Arduino serial port and run
%          H-reflex stimulation
%   stimL - Nx1 logical/numeric flag of which left strides to stimulate;
%          empty selects every 10th stride
%   stimR - Nx1 logical/numeric flag of which right strides to
%          stimulate; empty selects every 10th stride
%
% Outputs:
%   RTOTime - right toe-off timestamps (datenum) per stride
%   LTOTime - left toe-off timestamps (datenum) per stride
%   RHSTime - right heel-strike timestamps (datenum) per stride
%   LHSTime - left heel-strike timestamps (datenum) per stride
%   commSendTime - treadmill command send timestamps (clock vectors)
%   commSendFrame - frame numbers at treadmill command send
%
% Toolbox Dependencies: None
%
% See also NIRSHREFLEXOPENLOOPWITHAUDIO, HREFLEXOGWITHAUDIO, GETPAYLOAD.

arguments
    % FzThreshold has no default here even though the body always
    % overrides it to 100 a few lines down: it must stay required because
    % 'profilename'/'numAudioCountDown' are required positional arguments
    % that follow it (required arguments cannot follow optional ones).
    velL              (:,1) double
    velR              (:,1) double
    FzThreshold       (1,1) double
    profilename       (1,:) char
    numAudioCountDown (1,:) double
    isCalibration     (1,1) logical = false
    oxysoft_present   (1,1) logical = true
    hreflex_present   (1,1) logical = true
    stimL             (:,1) double = []
    stimR             (:,1) double = []
end

% argument-dependent defaults: an empty stimL/stimR means "no explicit
% per-stride stim schedule was provided", handled below via stimInterval
if isempty(stimL)
    stimL = zeros(numel(velL),1);
end

if isempty(stimR)
    stimR = zeros(numel(velR),1);
end

%% Open Arduino Serial Communication (If H-reflex Is Enabled)
%These parameters should ONLY BE CHANGED IF YOU KNOW WHAT YOU ARE DOING.
percentSS2Stim = 0.50; % target fraction of single stance for the stim (diagnostic only; Arduino applies its own copy of this target)
alpha          = 0.7;  % MATLAB-side smoothing factor for estSSL/R (diagnostic only, 0 < alpha <= 1); matches the Arduino firmware's alpha so the logged estSS mirrors the device
estSSLInit     = 396.6; % initial single-stance duration estimate (ms); from Liu et al. 2014 normative gait data, see Arduino sketch header for derivation
estSSRInit     = 396.6;

if hreflex_present
    try
        % configure and open serial port communication with Arduino
        fprintf('Opening Arduino serial port...\n');
        portArduino = serialport('COM4',115200);
        fprintf('Arduino serial port opened successfully.\n');
    catch ME
        warning(ME.identifier,'Failed to open Arduino serial port: %s', ...
            ME.message);
        % if this is the case, check that all Arduino software is closed
        % set to false to bypass stimulation if Arduino connection fails
        hreflex_present = false;
        return;
    end

    if isCalibration        % if H-reflex calibration trial, ...
        oxysoft_present = false;    % disable fNIRS in H-reflex calibration

        % load calibration audio for left and right stimulation events
        [audio_data,audio_fs] = audioread('L.mp3');
        CalibAudioL = audioplayer(audio_data,audio_fs);
        [audio_data,audio_fs] = audioread('R.mp3');
        CalibAudioR = audioplayer(audio_data,audio_fs);
    end

    if any(stimL) || any(stimR)
        % an explicit per-stride stim schedule was provided
        stimInterval = nan;
    else
        stimInterval = 10;  % stimulate every 10 strides
    end
    canStim = false; % latches true at single-stance onset; allows exactly one gate send per stance
    estSSL = estSSLInit; % running estimate of left single-stance duration (ms, diagnostic only)
    estSSR = estSSRInit;
    durSSL = estSSLInit; % most recent measured left single-stance duration (ms); seeded with the normative estimate until the first stride completes
    durSSR = estSSRInit;
    stimDelayL = estSSLInit * percentSS2Stim; % diagnostic-only target delay (ms), logged alongside each stim
    stimDelayR = estSSRInit * percentSS2Stim;
    echoBuf = ''; % partial serial line carried across iterations for the device stim echo
end

%% Load GUI Handle and Audio Files for Countdown
global PAUSE STOP
STOP = false;

if ~ismember(-1,numAudioCountDown)  % if '-1' not included, throw an error
    error('Incorrect input: -1 must be included in numAudioCountDown.');
end

if numAudioCountDown    % copied from open loop audiocountdown controller
    [audio_data,audio_fs] = audioread('TMStartIn3.mp3');
    AudioTMStart3 = audioplayer(audio_data,audio_fs);
    [audio_data,audio_fs] = audioread('TMStopIn3.mp3');
    AudioTMStop3 = audioplayer(audio_data,audio_fs);
    [audio_data,audio_fs] = audioread('2.mp3');
    AudioCount2 = audioplayer(audio_data,audio_fs);
    [audio_data,audio_fs] = audioread('1.mp3');
    AudioCount1 = audioplayer(audio_data,audio_fs);
    [audio_data,audio_fs] = audioread('now.mp3');
    AudioNow = audioplayer(audio_data,audio_fs);
    [audio_data,audio_fs] = audioread('TMChangeIn3.mp3');
    AudioTMChange3 = audioplayer(audio_data,audio_fs);
end

% get handle to the GUI so displayed data can be updated
ghandle = guidata(AdaptationGUI);

%% Set Up NIRS Communication
% Pop up window to confirm parameter setup, which is helpful in case
% debugging happened between experiment session to avoid mistakenly
% forgetting to log fNIRS data.
button = questdlg(['Confirm that NIRS is recording and ' ...
    '''oxysoft_present'' is true.']);
if ~strcmp(button,'Yes')
    return;     % abort starting the trial
end

Oxysoft = NaN;  % initialize to 'NaN' unless present
if oxysoft_present
    Oxysoft = actxserver('OxySoft.OxyApplication');
end

% connect to Oxysoft software
disp('Initial Setup');
%Event code hardcoded: I-connected, O-Relax, T-TMStopCountDown, R-Rest
%Event code from initial letter in nirsEventNames: A-AccRamp (to start),
%S-Split, M-Mid, P-PostTied, D-DccRamp2Split
%set up audio players
audioids = {'relax','rest','stopAndRest','TMStartNow'};
instructions = containers.Map();
for ii = 1:length(audioids)
    [audio_data,audio_fs] = audioread([audioids{ii} '.mp3']);
    instructions(audioids{ii}) = audioplayer(audio_data,audio_fs);
end

%this should be changed if the protocol is changing to no ramp, straight to
%start, then the event would be 'Mid'
tmStartEventName = 'AccRamp';
%save TM will start now also into key Mid. When log event Mid will also
%play audio.
instructions(tmStartEventName) = instructions('TMStartNow');

%% Parse Speed Profiles for NIRS Event Logging
[nirsEventSteps,nirsEventNames] = ...
    parseEventsFromSpeeds(velL(:,1),velR(:,1));
restIdx = strcmp(nirsEventNames,'Rest');
%this is safe to call even if there is no rest in the protocol.
restSteps = nirsEventSteps(restIdx);

%% Ask User for Train Index
if length(restSteps) > 1 %at least 2 rest exist, then ask which one to start from.
    trainIdx = inputdlg('Which split trainIdx would you like to start from (Valid entries: 1-4. Enter 1 if starting from the beginning)? ');
    disp(['Starting the Split trainIdx from ' trainIdx{1}]);
    trainIdx = str2double(trainIdx{1});
    if trainIdx > 1     % skipping some beginning trains
        restSteps = restSteps(trainIdx:end);
        velL = velL(restSteps(1):end,:);    % only keep portions of profile that's after the starting rest.
        velR = velR(restSteps(1):end,:);
        stimL = stimL(restSteps(1):end,:); %only keep portions of profile that's after the starting rest.
        stimR = stimR(restSteps(1):end,:);
        % parse new 'velL' and 'velR' again to get correct event steps and index
        [nirsEventSteps,nirsEventNames] = parseEventsFromSpeeds(velL(:,1),velR(:,1));
        restIdx = strcmp(nirsEventNames,'Rest');
        restSteps = nirsEventSteps(restIdx); % this is safe to call even if there is no rest in the protocol.
        manualLoadProfile([],[],ghandle,[],velL(:,1)/1000, velR(:,1)/1000);
    end
    trainIdx = trainIdx - 1; % will be used later for audioCue event suffix (typically starts with Rest1, if entered start from TrainIdx3, should log Rest 3 (nextRest=1 + train3-1)
else
    trainIdx = 0; % will be used later for audioCue event suffix (typically Rest1+0, this is initialized to avoid calling a non-exist variable later)
end

nirsEventSteps(restIdx) = []; % remove rest from this array
nirsEventNames(restIdx) = [];
need2LogEvent = false; % initialize to false;
if ~isempty(restSteps)
    need2LogEvent = true;
end
nextRestIdx = 1;
restDurations = [23 21 22 25 20 20 24 24 20 23 25 21 21 20 21 25 24 21 24 21 22 25 24 22 21];
% this is generated by rng(100); randi([20 25],1,25)

if ~isempty(nirsEventSteps)
    need2LogEvent = true;
end
nextNirsEventIdx = 1;

%% Initialize Data Logging Structure (Preallocated)
datlog = struct();
datlog.buildtime = now(); % timestamp
temp = datestr(datlog.buildtime,'yyyy_mm_dd_HH_MM_SS');
[d,n] = fileparts(which(mfilename));
savename = fullfile(d,'..','datlogs',[temp '_' profilename]);
set(ghandle.sessionnametxt,'String',[temp '_' n]);
datlog.session_name = savename;
datlog.errormsgs = {};
datlog.messages = cell(1,2);
datlog.framenumbers.header = {'frame #','U Time','Relative Time'};
numFramesEst = 300 * length(velR) + 7200;
datlog.framenumbers.data = nan(numFramesEst,2);
datlog.forces.header = {'frame #','U Time','Rfz','Lfz','Relative Time'};
datlog.forces.data = nan(numFramesEst,4); %check file cleaning, how you initialized it should be how you clean it up in the end
%e.g., if you initialize nan, when saving datlog, should check for first
%row of nan and remove all entries after to have a clean datlog and have
%relative time calculated properly. If you initialize to 0, when saving
%datlog, should check for first row of 0.
datlog.stepdata.header = {'Step#','U Time','frame #','Relative Time'};
datlog.stepdata.RHSdata = zeros(numel(velR)+50,3); % empty cell theoretically big enough to house all the steps taken
datlog.stepdata.RTOdata = zeros(numel(velR)+50,3);
datlog.stepdata.LHSdata = zeros(numel(velL)+50,3);
datlog.stepdata.LTOdata = zeros(numel(velL)+50,3);
datlog.inclineang = [];
datlog.speedprofile.velL = velL(:,1);
datlog.speedprofile.velR = velR(:,1);
datlog.TreadmillCommands.header = {'RBS','LBS','angle','U Time','Relative Time'};
datlog.TreadmillCommands.read = nan(numFramesEst,4);
datlog.TreadmillCommands.sent = nan(numFramesEst,4);
datlog.audioCues.start = [];    % initialize audioCue log fields
datlog.audioCues.audio_instruction_message = {};
datlog.stim.header = {'Step#','StimDelayTarget(ms)','TimeSinceContraTO(SerialDate#)'};
datlog.stim.L = [];
datlog.stim.R = [];
% Device stim echo (additive; NOT consumed by labTools/SyncDatalog). One
% row per pulse the Arduino actually delivered, echoed back over serial as
% timing ground truth (see firmware echoStimRecord). Columns:
%   leg       - 1 = left, 2 = right
%   ardStep   - Arduino-side ipsilateral step counter at the pulse
%   matStep   - MATLAB-side step counter when the echo was drained
%   stimMs    - Arduino millis() time the pulse fired
%   toRefMs   - Arduino millis() of the contralateral toe-off reference
%   estSSms   - Arduino single-stance estimate at the pulse (ms)
%   dtStimMs  - stimMs - toRefMs, i.e., elapsed time into single stance
%   durSSms   - MATLAB-measured single-stance duration used as denominator
%   pctSS     - 100 * dtStimMs / durSSms, the actual % of single stance
% NOTE: pctSS mixes an Arduino-detected toe-off (numerator) with a
% MATLAB-detected single-stance duration (denominator), so it carries a
% small cross-detector error and is an online gross-error check only. The
% Vicon analog sync pulse (Arduino pins 11/12) recorded on the same clock
% as the force-plate events is the gold-standard acceptance measurement.
datlog.stim.deviceEcho.header = {'leg','ardStep','matStep', ...
    'stimMs','toRefMs','estSSms','dtStimMs','durSSms','pctSS'};
datlog.stim.deviceEcho.data = [];
% Loop-timing diagnostics (additive; NOT consumed by labTools/SyncDatalog).
% loopSegMs columns: [iterTotal, drawnow/GUI, Vicon read+interop, control+
% stim], all in ms. gateLeadMs* record (gate send time - single-stance
% onset time), i.e., how soon after onset MATLAB flagged the stride to
% the Arduino, in ms.
datlog.diagnostics.header = {'iterTotalMs','guiMs','viconMs','ctrlMs'};
datlog.diagnostics.loopSegMs = zeros(numFramesEst,4);
datlog.diagnostics.gateLeadMsL = [];
datlog.diagnostics.gateLeadMsR = [];

%do initial save
try
    save(savename,'datlog');
catch ME
    disp(ME);
end

%% Force Plate Threshold Setup
if FzThreshold < 30
    datlog.messages{end+1,1} = 'Warning: Fz threshold too low to be robust to noise, using 30N instead';
    disp('Warning: Fz threshold too low to be robust to noise, using 30N instead');
end

forcePlateRobustThreshold = 100; % N; force plates are noisy (+-60N), so this floor is always imposed below
FzThreshold = forcePlateRobustThreshold;
datlog.messages{end+1,1} = 'Fz threshold is set to 100N for robust noise handling';
disp('Fz threshold is set to 100N for robust noise handling');

% check that velL and velR are of equal length
N = length(velL) + 1;
if length(velL) ~= length(velR)
    disp('WARNING: Velocity vectors of different length!');
    datlog.messages{end+1,1} = 'Velocity vectors of different length selected';
end

%% Initialize Nexus & Treadmill Communications
try
    HostName = 'localhost:801';
    addpath('..\dotNET');
    dssdkAssembly = which('ViconDataStreamSDK_DotNET.dll');
    if isempty(dssdkAssembly)
        [file,path] = uigetfile('*.dll');
        dssdkAssembly = fullfile(path,file);
    end

    NET.addAssembly(dssdkAssembly);
    MyClient = ViconDataStreamSDK.DotNET.Client();
    MyClient.Connect(HostName);
    MyClient.EnableSegmentData();
    MyClient.EnableMarkerData();
    MyClient.EnableUnlabeledMarkerData();
    MyClient.EnableDeviceData();
    MyClient.SetStreamMode(ViconDataStreamSDK.DotNET.StreamMode.ClientPull);
catch ME
    disp('Error creating Nexus Client Object/communications. See datlog for details.');
    datlog.errormsgs{end+1} = 'Error creating Nexus Client Object/communications.';
    datlog.errormsgs{end+1} = ME;   % store specific error
    disp(ME);
end

try
    fprintf('Open TM Comm. Date Time: %s\n',datestr(now(),'yyyy-mm-dd HH:MM:SS:FFF'));
    t = openTreadmillComm();
    fprintf('Done Opening. Date Time: %s\n',datestr(now(),'yyyy-mm-dd HH:MM:SS:FFF'));
catch ME
    disp('Error creating TCP connection to Treadmill. See datlog for details.');
    datlog.errormsgs{end+1} = 'Error creating TCP connection to Treadmill.';
    datlog.errormsgs{end+1} = ME;
    disp(ME);
end

try     % so that if something fails, communications are closed properly
    MyClient.GetFrame();
    datlog.messages(end+1,:) = {'Nexus and Bertec Interfaces initialized: ',now()};

    % initialize trial variables
    new_stanceL = false;
    new_stanceR = false;
    phase = 0; % 0 = Double Support, 1 = single L support, 2 = single R support
    LstepCount = 1;
    RstepCount = 1;
    RTOTime(N) = now();
    LTOTime(N) = now();
    RHSTime(N) = now();
    LHSTime(N) = now();
    commSendTime = zeros(2*N-1,6);
    commSendFrame = zeros(2*N-1,1);

    [RBS,LBS,cur_incl] = readTreadmillPacket(t); % read treadmill incline angle
    lastRead = now();
    datlog.inclineang = cur_incl;
    read_theta = cur_incl;

    % Nimbus start sync
    % create file on hard drive, then delete later after task is finished
    time1 = now();
    syncname = fullfile(tempdir,'SYNCH.dat');
    fid = fopen(syncname,'wb');
    fclose(fid);
    time2 = now();
    fprintf('Sync file creation time (s): %.3f\n',etime(datevec(time2),datevec(time1)));

    % audio countdown
    % if no rest (regular adapt block) or 1st stride speed is non 0, start with audio count down.
    if (isempty(restSteps) || velL(1,1) ~=0) && numAudioCountDown %No rest, will start right away. Add a 3-2-1 count down.
        fprintf('Ready to count down. Date Time: %s\n',datestr(now(),'yyyy-mm-dd HH:MM:SS:FFF'));
        play(AudioTMStart3);
        pause(2.5);
        play(AudioCount2);
        pause(1);
        play(AudioCount1);
        pause(1);
        play(AudioNow);
        % log it without saying "TM will start now" again.
        datlog = nirsEvent('Mid_noaudio','M',['Mid' num2str(nextRestIdx-1)],instructions,datlog,Oxysoft,oxysoft_present);
    end

    % Send first speed command and log it
    acc = 1500; %used to be 3500, made it smaller for start to be more smooth, 1500 would achieve 1.5m/s in 1second, which is beyond the expected max speed we will ever use in this protocol.
    payload = getPayload(velR(1,1),velL(1,1),acc,acc,cur_incl);
    sendTreadmillPacket(payload,t);
    datlog.TreadmillCommands.firstSent = [velR(RstepCount,1) velL(LstepCount,1) acc acc cur_incl now()];
    commSendTime(1,:) = clock;
    datlog.TreadmillCommands.sent(1,:) = [velR(RstepCount,1) velL(LstepCount,1) cur_incl now()];
    datlog.messages(end+1,:) = {'First speed command sent',now()};
    datlog.messages{end+1,1} = ['Lspeed = ' num2str(velL(LstepCount,1)) ', Rspeed = ' num2str(velR(RstepCount,1))];

    %% Start Arduino State Machine
    % Send this right before walking starts (not immediately after opening
    % the serial port) so the Arduino's step/phase counters reset close to
    % actual walking onset instead of sitting idle through NIRS setup and
    % the audio countdown above, which could otherwise skew the first
    % estSSL/estSSR estimate with spurious phase transitions.
    if hreflex_present
        try
            fprintf('Sending start command to Arduino state machine...\n');
            write(portArduino,0,'int16');    % reset step counters & start
            % Clear any bytes left in the OS input buffer from a prior
            % session before the loop starts draining stim echoes; command
            % 0 produces no echo, so nothing of ours is discarded here.
            flush(portArduino,'input');
            fprintf('Start command sent successfully.\n');
        catch ME
            warning(ME.identifier,['Failed to send start command to ' ...
                'Arduino: %s'],ME.message);
        end
    end

    %% Main Loop
    old_velR = libpointer('doublePtr',velR(1,1));
    old_velL = libpointer('doublePtr',velL(1,1));
    frameind = libpointer('doublePtr',1);
    framenum = libpointer('doublePtr',0);

    if numAudioCountDown    % adapted from open loop audio countdown
        countDownPlayed = repmat(false,1,5*length(numAudioCountDown));
        %if there are speed changes in between, will have 4 counts for
        %each: 3-2-1-now & 1 for complete, moving on to next.
        %the last 4 index will be used for 3-2-1-now(stop) and will be reused
        %for each rest stop in between.
        countDownIdx = 1;
        countDownIdxOffset = 0;
        if length(numAudioCountDown) > 1 % there is speed change in between
            speedChangeStride = numAudioCountDown(1); %set to first target
        end
        prevChangeTime = datetime('now');
    end

    loopCount = 0;          % number of completed main-loop iterations
    lastUIUpdate = now();   % last time belt-speed textboxes were refreshed
    handrailHigh = false;   % current handrail-force warning color state
    % Reusable per-leg marker lines: append a point per heel strike via
    % addpoints instead of creating a new plot object every stride (which
    % accumulated thousands of objects and inflated drawnow within a trial).
    % profileaxes has hold on and legend AutoUpdate off (see manualLoadProfile)
    hAnimMarkR = animatedline(ghandle.profileaxes,'LineStyle','none', ...
        'Marker','o','MarkerFaceColor',[1 0.6 0.78], ...
        'MarkerEdgeColor','r');
    hAnimMarkL = animatedline(ghandle.profileaxes,'LineStyle','none', ...
        'Marker','o','MarkerFaceColor',[0.68 0.92 1], ...
        'MarkerEdgeColor','b');

    while ~STOP     % only runs trial loop if stop button is not pressed
        while PAUSE % only runs if pause button is pressed
            pause(0.2);
            datlog.messages(end+1,:) = {'Loop paused at ',now()};
            disp(['Paused at ' num2str(clock)]);
            % bring treadmill to a stop and keep it there!...
            payload = getPayload(0,0,500,500,cur_incl);
            sendTreadmillPacket(payload,t);
            % do a quick save
            try
                save(savename,'datlog');
            catch ME
                disp(ME);
            end
            old_velR.Value = 1; % change the old values so that the treadmill knows to resume when the pause button is resumed
            old_velL.Value = 1;
        end
        tIter = tic;            % start per-iteration loop timer
        tSeg = tic;
        drawnow limitrate;      % throttle redraws; still flushes UI callbacks
        segGuiMs = toc(tSeg)*1000;
        tSeg = tic;
        old_stanceL = new_stanceL;
        old_stanceR = new_stanceR;

        % read frame, update necessary structures
        MyClient.GetFrame();
        framenum.Value = MyClient.GetFrameNumber().FrameNumber;
        datlog.framenumbers.data(frameind.Value,:) = [framenum.Value now()];

        % read treadmill, if enough time has elapsed since last read
        if (now() - lastRead)*86400 > 0.1     % only read if enough time has elapsed
            [RBS,LBS,read_theta] = readTreadmillPacket(t);  % also read what the treadmill is doing
            lastRead = now();
        end
        datlog.TreadmillCommands.read(frameind.Value,:) = [RBS LBS read_theta now()];
        % throttle textbox refresh to limit per-iteration graphics work
        if (now() - lastUIUpdate)*86400 > 0.1     % refresh at ~10 Hz
            set(ghandle.RBeltSpeed_textbox,'String',num2str(RBS/1000));
            set(ghandle.LBeltSpeed_textbox,'String',num2str(LBS/1000));
            lastUIUpdate = now();
        end
        frameind.Value = frameind.Value + 1;

        % capture force plate data
        Fz_R = MyClient.GetDeviceOutputValue('Right Treadmill','Fz');
        Fz_L = MyClient.GetDeviceOutputValue('Left Treadmill','Fz');
        datlog.forces.data(frameind.Value,:) = [framenum.Value now() Fz_R.Value Fz_L.Value];
        Hx = MyClient.GetDeviceOutputValue('Handrail','Fx');
        Hy = MyClient.GetDeviceOutputValue('Handrail','Fy');
        Hz = MyClient.GetDeviceOutputValue('Handrail','Fz');
        Hm = sqrt(Hx.Value^2+Hy.Value^2+Hz.Value^2);
        %if handrail force is too high, notify the experimentor; only update
        %the color on a state change to avoid dirtying the figure every loop
        handrailForceThreshold = 25; % N; above this, warn the experimenter via figure color
        if (Hm > handrailForceThreshold) && ~handrailHigh
            set(ghandle.figure1,'Color',[238 5 5]./255);
            handrailHigh = true;
        elseif (Hm <= handrailForceThreshold) && handrailHigh
            set(ghandle.figure1,'Color',[1 1 1]);
            handrailHigh = false;
        end

        %% This section was on
        if ~strcmp(Fz_R.Result,'Success') || ~strcmp(Fz_L.Result,'Success') %DMMO
            Fz_R = MyClient.GetDeviceOutputValue('Right','Fz');
            Fz_L = MyClient.GetDeviceOutputValue('Left','Fz');
            if ~strcmp(Fz_R.Result,'Success') || ~strcmp(Fz_L.Result,'Success')
                STOP = 1;  %stopUnloadVicon, the GUI can't find the forceplate values
                disp('ERROR! Adaptation GUI unable to read forceplate data, check device names and function');
                datlog.errormsgs{end+1} = 'Adaptation GUI unable to read forceplate data, check device names and function';
            end
        end
        %%
        segViconMs = toc(tSeg)*1000;    % Vicon read + interop segment
        tSeg = tic;                     % start control + stim segment

        % gait event detection
        new_stanceL = Fz_L.Value < -FzThreshold;
        new_stanceR = Fz_R.Value < -FzThreshold;
        LHS = new_stanceL && ~old_stanceL;
        RHS = new_stanceR && ~old_stanceR;
        LTO = ~new_stanceL && old_stanceL;
        RTO = ~new_stanceR && old_stanceR;

        % update gait phase state machine
        switch phase
            case 0          % double support (initial phase)
                if RTO      % advance to single stance L
                    phase = 1;
                    RstepCount = RstepCount + 1;
                    RTOTime(RstepCount) = now();
                    datlog.stepdata.RTOdata(RstepCount-1,:) = [RstepCount-1 now() framenum.Value];
                elseif LTO  % advance to single stance R
                    phase = 2;
                    LstepCount = LstepCount + 1;
                    LTOTime(LstepCount) = now();
                    datlog.stepdata.LTOdata(LstepCount-1,:) = [LstepCount-1 now() framenum.Value];
                end
            case 1          % single stance L
                if RHS      % advance to double stance
                    phase = 3;
                    RHSTime(RstepCount) = now();
                    datlog.stepdata.RHSdata(RstepCount-1,:) = [RstepCount-1 now() framenum.Value];
                    % RHS marks the end of single stance L
                    % compute duration of left leg single stance phase
                    % (RHSTime/RTOTime are datenums in days; convert to ms
                    % so durSSL/estSSL stay in ms like the Arduino's copy)
                    durSSL = (RHSTime(RstepCount) - RTOTime(RstepCount)) ...
                        * 86400000; % days -> ms
                    % estimate single stance duration using exponential updating factor
                    estSSL = alpha * durSSL + (1.0 - alpha) * estSSL;
                    stimDelayL = estSSL * percentSS2Stim;
                    set(ghandle.Right_step_textbox,'String',num2str(RstepCount-1));
                    % plot cursor
                    addpoints(hAnimMarkR,RstepCount-1,velR(RstepCount,1)/1000);
                    canStim = true; % single stance R is about to begin; allow its onset gate to fire

                    if LTO %In case DS is too short and a full cycle misses the phase switch
                        phase = 2;
                        LstepCount = LstepCount + 1;
                        LTOTime(LstepCount) = now();
                        datlog.stepdata.LTOdata(LstepCount-1,:) = [LstepCount-1 now() framenum.Value];
                    end
                end
            case 2          % single stance R
                if LHS      % advance to double stance
                    phase = 4;
                    LHSTime(LstepCount) = now();
                    datlog.stepdata.LHSdata(LstepCount-1,:) = [LstepCount-1 now() framenum.Value];
                    % LHS marks the end of single stance R
                    % compute duration of right leg single stance phase
                    % (LHSTime/LTOTime are datenums in days; convert to ms
                    % so durSSR/estSSR stay in ms like the Arduino's copy)
                    durSSR = (LHSTime(LstepCount) - LTOTime(LstepCount)) ...
                        * 86400000; % days -> ms
                    % estimate single stance duration using exponential updating factor
                    estSSR = alpha * durSSR + (1.0 - alpha) * estSSR;
                    stimDelayR = estSSR * percentSS2Stim;
                    set(ghandle.Left_step_textbox,'String',num2str(LstepCount-1));
                    % plot cursor
                    addpoints(hAnimMarkL,LstepCount-1,velL(LstepCount,1)/1000);
                    canStim = true; % single stance L is about to begin; allow its onset gate to fire

                    if RTO %In case DS is too short and a full cycle misses the phase switch
                        phase = 1;
                        RstepCount = RstepCount + 1;
                        RTOTime(RstepCount) = now();
                        datlog.stepdata.RTOdata(RstepCount-1,:) = [RstepCount-1 now() framenum.Value];
                    end
                end
            case 3          % double stance, coming from single stance L
                if LTO      % advance to single stance R
                    phase = 2;
                    LstepCount = LstepCount + 1;
                    LTOTime(LstepCount) = now();
                    datlog.stepdata.LTOdata(LstepCount-1,:) = [LstepCount-1 now() framenum.Value];
                end
            case 4          % double stance, coming from single stance R
                if RTO      % advance to single stance L
                    phase = 1;  % advance to L single stance
                    RstepCount = RstepCount + 1;
                    RTOTime(RstepCount) = now();
                    datlog.stepdata.RTOdata(RstepCount-1,:) = [RstepCount-1 now() framenum.Value];
                end
        end

        if hreflex_present      % only do this if has the stimulator
            % Drain any device stim echoes the Arduino sent since the last
            % iteration and log the actual %-single-stance per delivered
            % pulse. This is telemetry only: drainStimEcho reads just the
            % bytes already waiting in the OS buffer (never blocks) and the
            % whole block is wrapped so a serial hiccup can never abort the
            % trial. A dropped echo is a non-event. With old firmware that
            % does not echo, NumBytesAvailable stays 0 and this is a no-op.
            try
                [echoBuf,echoRecs] = drainStimEcho(portArduino,echoBuf);
                for er = 1:size(echoRecs,1)
                    legNum   = echoRecs(er,1);
                    ardStep  = echoRecs(er,2);
                    stimMs   = echoRecs(er,3);
                    toRefMs  = echoRecs(er,4);
                    estSSms  = echoRecs(er,5);
                    dtStimMs = stimMs - toRefMs; % elapsed into single stance
                    if legNum == 1     % left pulse: single stance L
                        matStep = RstepCount;
                        durSSms = durSSL; % most recent measured (ms)
                    else               % right pulse: single stance R
                        matStep = LstepCount;
                        durSSms = durSSR;
                    end
                    pctSS = 100 * dtStimMs / durSSms;
                    datlog.stim.deviceEcho.data(end+1,:) = [legNum ...
                        ardStep matStep stimMs toRefMs estSSms ...
                        dtStimMs durSSms pctSS];
                    reportStimPctSS(legNum,ardStep,pctSS);
                end
            catch ME
                datlog.errormsgs{end+1} = ['Stim echo drain error: ' ...
                    ME.message];
            end

            % use contralateral leg (i.e., LHS - LTO) to determine R mid-single stance
            timeSinceLTO = now() - LTOTime(LstepCount);
            if isnan(stimInterval)
                shouldStimR = logical(stimR(RstepCount));
                shouldStimL = logical(stimL(LstepCount));
            else
                shouldStimR = mod(RstepCount,stimInterval) == 4;
                shouldStimL = mod(LstepCount,stimInterval) == 4;
            end

            % Send the gate at single-stance onset: the Arduino owns the
            % precise 50%-single-stance timing, so MATLAB only needs to flag
            % the stride early. Waiting until mid-stance left too little
            % margin and caused late or missed stims under control-loop
            % jitter.
            if (shouldStimR && phase == 2 && canStim)
                if isCalibration    % play sound
                    play(CalibAudioR);
                end

                try         % send command to Arduino to stimulate right
                    write(portArduino,2,'int16'); % hard-coded here and in Arduino. Don't change this.
                catch ME
                    warning(ME.identifier,['Failed to send right leg ' ...
                        'stimulation command to Arduino: %s'],ME.message);
                end
                canStim = false;
                datlog.stim.R(end+1,:) = [RstepCount stimDelayR timeSinceLTO];
                datlog.diagnostics.gateLeadMsR(end+1) = ...
                    timeSinceLTO*86400000;  % gate lead from LTO (ms)
            end

            % use contralateral leg (i.e., RHS - RTO) to determine L mid-single stance
            timeSinceRTO = now() - RTOTime(RstepCount);
            if (shouldStimL && phase == 1 && canStim)
                if isCalibration    % play sound
                    play(CalibAudioL);
                end

                try         % send command to Arduino to stimulate left
                    write(portArduino,1,'int16');
                catch ME
                    warning(ME.identifier,['Failed to send left leg ' ...
                        'stimulation command to Arduino: %s'],ME.message);
                end

                canStim = false;    % prevent immediate re-stimulation
                datlog.stim.L(end+1,:) = [RstepCount stimDelayL timeSinceRTO];
                datlog.diagnostics.gateLeadMsL(end+1) = ...
                    timeSinceRTO*86400000;  % gate lead from RTO (ms)
            end
        end

        %check if should log NIRS events
        if nextNirsEventIdx <= length(nirsEventSteps)
            if (LstepCount == nirsEventSteps(nextNirsEventIdx) || RstepCount == nirsEventSteps(nextNirsEventIdx)) && need2LogEvent
                %log it, move on to the next target and avoid coming here multiple
                %times.
                nirsEventString = nirsEventNames{nextNirsEventIdx};
                datlog = nirsEvent(nirsEventString, nirsEventString(1), [nirsEventString num2str(nextRestIdx-1+trainIdx)], instructions, datlog, Oxysoft, oxysoft_present);
                % wait till 2 steps later to log event again to avoid same
                % event logged multiple times.
                need2LogEvent = false;
                if strcmp(nirsEventString,tmStartEventName) %starting TM again, give an audio cue.
                    pause(2); %give some time for the instruction to play.
                end
            elseif LstepCount >= nirsEventSteps(nextNirsEventIdx)+1 && RstepCount >= nirsEventSteps(nextNirsEventIdx)+1
                %now have past the most recent change by at least 1 steps both side, reset the flag
                need2LogEvent = true;
                nextNirsEventIdx = nextNirsEventIdx + 1;
            end
        end

        if numAudioCountDown %Adapted from open loop audio countdown
            if length(numAudioCountDown) > 1 && speedChangeStride ~= -1 %there is speed change in the middle and there is more change incoming (if -1 means next is TM end)
                if (LstepCount == speedChangeStride-3 || RstepCount == speedChangeStride-3) && ~countDownPlayed(1+countDownIdxOffset)
                    fprintf(['Change at ' num2str(speedChangeStride) '-3 Stride . Date Time: ' datestr(now(),'yyyy-mm-dd HH:MM:SS:FFF') '\n']);
                    fprintf('Current step count L: %d, R:%d, countDownIdx: %d, idx offset: %d\n',LstepCount,RstepCount,countDownIdx, countDownIdxOffset)

                    %log in NIRS that audio count down is happening. FIXME
                    datlog = nirsEvent('TMStopAudioCountDown', 'D', ['TMStopAudioCountDown_Train' num2str(nextRestIdx-1+trainIdx)], instructions, datlog, Oxysoft, oxysoft_present);

                    play(AudioTMChange3);
                    countDownPlayed(countDownIdx) = true; %This should only be run once
                    countDownIdx = countDownIdx + 1;
                elseif (LstepCount == speedChangeStride-1 || RstepCount == speedChangeStride-1) && ~countDownPlayed(2+countDownIdxOffset)
                    fprintf(['Change-2 Stride . Date Time: ' datestr(now(),'yyyy-mm-dd HH:MM:SS:FFF') '\n']);
                    fprintf('Current step count L: %d, R:%d, countDownIdx: %d, idx offset: %d\n',LstepCount,RstepCount,countDownIdx, countDownIdxOffset)
                    play(AudioCount2);
                    countDownPlayed(countDownIdx) = true; %This should only be run once
                    countDownIdx = countDownIdx + 1;
                elseif (LstepCount == speedChangeStride || RstepCount == speedChangeStride) && ~countDownPlayed(3+countDownIdxOffset)
                    fprintf(['Change at ' num2str(speedChangeStride) ' Last Stride . Date Time: ' datestr(now(),'yyyy-mm-dd HH:MM:SS:FFF') '\n']);
                    fprintf('Current step count L: %d, R:%d, countDownIdx: %d, idx offset: %d\n',LstepCount,RstepCount,countDownIdx, countDownIdxOffset)
                    disp(countDownPlayed)
                    play(AudioCount1)
                    countDownPlayed(countDownIdx) = true; %This should only be run once
                    countDownIdx = countDownIdx + 1;
                elseif (LstepCount == speedChangeStride+1 || RstepCount == speedChangeStride+1) && ~countDownPlayed(4+countDownIdxOffset)
                    fprintf(['Change Stride +1. Date Time: ' datestr(now(),'yyyy-mm-dd HH:MM:SS:FFF') '\n']);
                    play(AudioNow)
                    countDownPlayed(countDownIdx) = true; %This should only be run once
                    countDownIdx = countDownIdx + 1;
                elseif (LstepCount >= speedChangeStride+2 && RstepCount >= speedChangeStride+2) && ~countDownPlayed(5+countDownIdxOffset) && seconds(datetime('now') - prevChangeTime) > 3 %don't try this again untill 3s has passed
                    %both legs are above speedChangeStride+1, finished the
                    %change, move on to next target
                    countDownIdxOffset = countDownIdxOffset + 5; %finished one change, don't do this again
                    speedChangeStride = numAudioCountDown(countDownIdxOffset/5+1); %move on to the next change target
                    fprintf('Done change. Next target: %d\n', speedChangeStride)
                    fprintf('Current step count L: %d, R:%d, countDownIdx: %d, idx offset: %d\n',LstepCount,RstepCount,countDownIdx, countDownIdxOffset)
                    countDownPlayed(countDownIdx) = true; %This should only be run once
                    countDownIdx = countDownIdx + 1;
                    prevChangeTime = datetime('now');
                end
            end %end conditional block for when there is step change in the middle

            if ~countDownPlayed(end-3) && ( ...
                    (nextRestIdx <= length(restSteps) && (LstepCount == restSteps(nextRestIdx)-4 || RstepCount == restSteps(nextRestIdx)-4)))
                fprintf(['-3 Stride . Date Time: ' datestr(now(),'yyyy-mm-dd HH:MM:SS:FFF') '\n']);
                %log in NIRS that audio count down is happening.
                datlog = nirsEvent('TMStopAudioCountDown', 'D', ['TMStopAudioCountDown_Train' num2str(nextRestIdx-1+trainIdx)], instructions, datlog, Oxysoft, oxysoft_present);
                play(AudioTMStop3); %takes 2 seconds to say "treadmill will stop in"
                countDownPlayed(end-3) = true; %This should only be run once
            elseif ~countDownPlayed(end-2) && (...
                    (nextRestIdx <= length(restSteps) && (LstepCount == restSteps(nextRestIdx)-2 || RstepCount == restSteps(nextRestIdx)-2)))
                fprintf(['-2 Stride . Date Time: ' datestr(now(),'yyyy-mm-dd HH:MM:SS:FFF') '\n']);
                play(AudioCount2);
                countDownPlayed(end-2) = true; %This should only be run once
            elseif ~countDownPlayed(end-1) && (...
                    (nextRestIdx <= length(restSteps) && (LstepCount == restSteps(nextRestIdx)-1 || RstepCount == restSteps(nextRestIdx)-1)))
                fprintf(['-1 Stride . Date Time: ' datestr(now(),'yyyy-mm-dd HH:MM:SS:FFF') '\n']);
                play(AudioCount1);
                countDownPlayed(end-1) = true; %This should only be run once
            end

            %Trial will end soon.
            if (LstepCount == N-3 || RstepCount == N-3) && ~countDownPlayed(end-3)
                fprintf(['-3 Stride . Date Time: ' datestr(now(),'yyyy-mm-dd HH:MM:SS:FFF') '\n']);
                %log in NIRS that audio count down is happening.
                datlog = nirsEvent('TMStopAudioCountDown','D',['TMStopAudioCountDown_Train' num2str(nextRestIdx-1+trainIdx)],instructions,datlog,Oxysoft,oxysoft_present);
                play(AudioTMStop3);
                countDownPlayed(end-3) = true; %This should only be run once
            elseif (LstepCount == N-1 || RstepCount == N-1) && ~countDownPlayed(end-2)
                fprintf(['-2 Stride . Date Time: ' datestr(now(),'yyyy-mm-dd HH:MM:SS:FFF') '\n']);
                play(AudioCount2);
                countDownPlayed(end-2) = true; %This should only be run once
            end
        end

        if LstepCount >= N || RstepCount >= N%if taken enough steps, stop
            if numAudioCountDown %adapted from open loop audiocoudntdown
                fprintf(['Last Stride . Date Time: ' datestr(now(),'yyyy-mm-dd HH:MM:SS:FFF') '\n']);
                play(AudioCount1);
            end
            break
            % send treadmill command only if speed changes
        elseif (velR(RstepCount,1) ~= old_velR.Value) || (velL(LstepCount,1) ~= old_velL.Value)% && LstepCount<N && RstepCount<N
            payload = getPayload(velR(RstepCount,1),velL(LstepCount,1),acc,acc,cur_incl);
            sendTreadmillPacket(payload,t);
            datlog.TreadmillCommands.sent(frameind.Value,:) = [velR(RstepCount,1) velL(LstepCount,1) cur_incl now()]; % record the command
            disp(['Packet sent, Lspeed = ' num2str(velL(LstepCount,1)) ', Rspeed = ' num2str(velR(RstepCount,1))]);
        else
            %simply record what the treadmill should be doing
            %datlog.TreadmillCommands.sent(frameind.Value,:) = [velR(RstepCount),velL(LstepCount),cur_incl,now];%record the command
            %Pablo commented out on 26/2/2018 because it is unnecessary and takes time to save later.
        end

        old_velR.Value = velR(RstepCount,1);
        old_velL.Value = velL(LstepCount,1);

        if need2LogEvent && nextRestIdx <= length(restSteps) && (LstepCount == restSteps(nextRestIdx) || RstepCount == restSteps(nextRestIdx))  %time for a rest
            need2LogEvent = false;
            %for all rest except for the 1st (starting with a rest TM is not
            %moving)
            if countDownPlayed(end-1) % just counted down from 3-2-1, probably should say TM now.
                play(AudioNow);
                countDownPlayed(end-3:end) = false; % reset countdown flag
            end

            % make sure TM is at zero and hold it there.
            [payload] = getPayload(0,0,acc,acc,cur_incl);
            sendTreadmillPacket(payload,t);
            pause(1.5); % give some time for the previous instruction to finish.
            % this function plays the audio, sends event to NIRS, and logs it in datlog
            datlog = nirsEvent('rest','R',['Rest' num2str(nextRestIdx+trainIdx)],instructions,datlog,Oxysoft,oxysoft_present);
            %instead of a full 20s pause, run a WHILE loop here so that the program wouldn't hang and would
            % respond to STOP in the rest break.
            restStarted = clock;
            restDone = false;
            restDuration = restDurations(nextRestIdx);
            while ~restDone && ~STOP
                t_diff = clock - restStarted; %aux 1x6 array in year, month, day, hour, min, sec
                t_diff = abs((t_diff(4)*3600)+(t_diff(5)*60)+t_diff(6)); % compute difference in seconds
                if t_diff >= restDuration-0.5%aux(6)>=restDuration || any(aux(1:5)>0) %enough time to rest has passed. moving on, should never be in the second or loop situation
                    restDone = true;
                else
                    pause(0.8); % pause for a bit so we are not doing the while loop nonstop.
                    [~,~,~] = readTreadmillPacket(t);   % this is to maintain communication with the treamdill to avoid lag after the break.
                end
            end
            if STOP     % anytime if STOP is pressed, quit the while loop
                break;  % break the while loop
            end
            %done, advance step count to the next walking event.(notice that
            %assumes there is always an event immediately after the rest,
            %(e.g., rest is at step 200, there will be an event at step 250,
            %and rest duration is coded as 50 steps).
            if nextNirsEventIdx <= length(nirsEventSteps) %assign stepCont to next event, only if there is still more event coming.
                LstepCount = nirsEventSteps(nextNirsEventIdx);
                RstepCount = nirsEventSteps(nextNirsEventIdx); %it appears that we always take coded stride - 1 steps (but that's how it is in open loop controller too bc stepcount started at 1 intead of 0)
            else %otherwise assume rest is the last thing the script will do.
                STOP = true;    % manually set stop to the experiments
            end
            need2LogEvent = true;
            nextRestIdx = nextRestIdx + 1;
        end

        % record per-iteration loop-timing diagnostics (additive)
        loopCount = loopCount + 1;
        datlog.diagnostics.loopSegMs(loopCount,:) = ...
            [toc(tIter)*1000, segGuiMs, segViconMs, toc(tSeg)*1000];
    end     % while, when STOP button is pressed

    % trim unused preallocated diagnostic rows
    datlog.diagnostics.loopSegMs(loopCount+1:end,:) = [];

    if STOP
        datlog.messages(end+1,:) = {'Stop button pressed at: [see next cell] ,stopping... ',now()};
        disp(['Stop button pressed, stopping... ' num2str(clock)]);
        set(ghandle.Status_textbox,'String','Stopping...');
        set(ghandle.Status_textbox,'BackgroundColor','red');
    end

    % log the final event marking trial end, without audio telling participant
    % to relax. This log could happen 1-2 seconds before TM fully stops which
    % is ok bc stopping usually could be perturbing and this probably marks a
    % better steady state ending.
    % audio cue here would be too early, so just log the event without saying anything yet (see Alt Option below).
    datlog = nirsEvent('relax_noaudio','O','Trial_End',instructions,datlog,Oxysoft,oxysoft_present);
catch ME
    datlog.errormsgs{end+1} = 'Error occurred during the control loop';
    datlog.errormsgs{end+1} = ME;
    disp('Error occurred during the control loop, see datlog for details...');
end
%% Closing Routine
% end communications
try
    save(savename,'datlog');
    delete(syncname);   % delete sync file in prep for next trial
catch ME
    disp(ME);
end

if hreflex_present      % if hreflex, stop the Arduino state machine and close communication
    % Sent here (rather than only on the no-error path inside the main
    % try) so the Arduino's state machine is stopped even if the control
    % loop above threw an error. handleStimulationTimeout() on the Arduino
    % runs regardless of the state machine, so any in-flight pulse still
    % clears safely either way.
    try
        fprintf('Sending command to stop the Arduino state machine...\n');
        write(portArduino,3,'int16');    % stop state machine
        fprintf('Stop state machine command sent successfully.\n');
    catch ME
        warning(ME.identifier,['Failed to send stop state machine ' ...
            'command to Arduino: %s'],ME.message);
    end

    datlog.messages(end+1,:) = {'Closing Arduino port...',now()};
    fprintf('Closing Arduino serial port...\n');
    try
        flush(portArduino);     % flush remaining data in the buffer
        delete(portArduino);    % close and clear the serial port object
        fprintf('Arduino serial port closed successfully.\n');
    catch ME
        warning(ME.identifier,'Failed to close Arduino port properly: %s',ME.message);
    end
end

try % stopping the treadmill
    % see if the treadmill is supposed to stop at the end of the profile
    if get(ghandle.StoptreadmillEND_checkbox,'Value') == 1 && ~STOP
        set(ghandle.Status_textbox,'String','Stopping...');
        set(ghandle.Status_textbox,'BackgroundColor','red');
        set(ghandle.figure1,'Color',[1 1 1]);
        pause(0.5); % Pablo I. wrote "Do we need this?"
        fprintf('Trying to stop treadmill (TM1) at %s\n',datestr(now(),'yyyy-mm-dd HH:MM:SS:FFF'));
        smoothStop(t);
        if numAudioCountDown % no need to say now again, changed the logic to say it earlier at stepN
            play(AudioNow);
        end
        % see if the treadmill should be stopped when the STOP button is pressed
    elseif get(ghandle.StoptreadmillSTOP_checkbox,'Value') == 1 && STOP == 1
        set(ghandle.Status_textbox,'String','Stopping');
        set(ghandle.Status_textbox,'BackgroundColor','red');
        pause(0.3);
        fprintf('Trying to stop treadmill (TM2) at %s\n',datestr(now(),'yyyy-mm-dd HH:MM:SS:FFF'));
        smoothStop(t);
    end

    %Say  "Relax" without sending another event to NIRS (last arg always false).
    %Alt Option: this could be a good time to say "Relax" and the time
    %point would be exactly when TM stopped, but logging timing is better right after the last stride without audio and before the closing routine above.
    %the activity during the closing routine shouldn't really be analyzed.
    %     datlog = nirsEvent('relax','O','Trial_End_TMStop', instructions, datlog, Oxysoft, false);

    % check if treadmill stopped, if not, try again:
    pause(1);
    fprintf('Trying to stop treadmill (TM3) at %s\n',datestr(now(),'yyyy-mm-dd HH:MM:SS:FFF'));
    [cur_speedR,cur_speedL,cur_incl] = readTreadmillPacket(t);
    stopped = (cur_speedR == 0) && (cur_speedL == 0);
    maxStopAttempts = 5;
    counter = 0;
    while ~stopped && counter < maxStopAttempts   % try a few times to stop the treadmill smoothly
        disp('Treadmill did not stop as requested. Retrying...');
        fprintf('Attempt %d to stop treadmill at %s\n',counter,datestr(now(),'yyyy-mm-dd HH:MM:SS:FFF'));
        pause(1);   % give time to smoothStop to execute everything
        [cur_speedR,cur_speedL,cur_incl] = readTreadmillPacket(t);
        stopped = (cur_speedR == 0) && (cur_speedL == 0);
        counter = counter + 1;
    end
    if counter >= maxStopAttempts
        disp('Could not stop treadmill after maximum attempts');
    end
catch ME
    datlog.errormsgs{end+1} = 'Error stopping the treadmill';
    datlog.errormsgs{end+1} = ME;
end

disp('Closing communications...');
try
    closeNexusIface(MyClient);
    closeTreadmillComm(t);
catch ME
    datlog.errormsgs{end+1} = ['Error ocurred when closing communications with Nexus & Treadmill at ' num2str(clock)];
    datlog.errormsgs{end+1} = ME;
    disp(['Error ocurred when closing communications with Nexus & Treadmill, see datlog for details ' num2str(clock)]);
    disp(ME);
end

%% Convert and Save Timing Data (Vectorized)
disp('Converting time in datlog...');
% convert time data into clock format then re-save
datlog.buildtime = datestr(datlog.buildtime);

% convert frame times
temp = find(isnan(datlog.framenumbers.data(:,1)),1,'first');
datlog.framenumbers.data(temp:end,:) = [];
for z = 1:temp-1
    datlog.framenumbers.data(z,3) = etime(datevec(datlog.framenumbers.data(z,2)),datevec(datlog.framenumbers.data(1,2)));
end
% convert force times
datlog.forces.data(1,:) = [];
temp = find(isnan(datlog.forces.data(:,1)),1,'first');
datlog.forces.data(temp:end,:) = [];
for z = 1:temp-1
    datlog.forces.data(z,5) = etime(datevec(datlog.forces.data(z,2)),datevec(datlog.forces.data(1,2)));
end
% convert RHS times
datlog.stepdata.RHSdata(temp:end,:) = [];
temp = size(datlog.stepdata.RHSdata,1) + 1;
for z = 1:temp-1
    datlog.stepdata.RHSdata(z,4) = etime(datevec(datlog.stepdata.RHSdata(z,2)),datevec(datlog.framenumbers.data(1,2)));
end
% convert LHS times
for z = 1:temp-1
    datlog.stepdata.LHSdata(z,4) = etime(datevec(datlog.stepdata.LHSdata(z,2)),datevec(datlog.framenumbers.data(1,2)));
end
% convert RTO times
for z = 1:temp-1
    datlog.stepdata.RTOdata(z,4) = etime(datevec(datlog.stepdata.RTOdata(z,2)),datevec(datlog.framenumbers.data(1,2)));
end
% convert LTO times
for z = 1:temp-1
    datlog.stepdata.LTOdata(z,4) = etime(datevec(datlog.stepdata.LTOdata(z,2)),datevec(datlog.framenumbers.data(1,2)));
end

% convert command times
temp = all(isnan(datlog.TreadmillCommands.read(:,1:4)),2);
datlog.TreadmillCommands.read = datlog.TreadmillCommands.read(~temp,:);
for z = 1:size(datlog.TreadmillCommands.read,1) % compute relative time and fill in the last column
    datlog.TreadmillCommands.read(z,5) = etime(datevec(datlog.TreadmillCommands.read(z,4)),datevec(datlog.framenumbers.data(1,2)));
end

try
    firstTMTime = datlog.TreadmillCommands.read(1,4);
    lastTMTime = datlog.TreadmillCommands.read(end,4);
    fprintf(['\n\nTreadmill First Packet Read Time. Universal Time: ' num2str(firstTMTime) '. Date Time: ' datestr(firstTMTime,'yyyy-mm-dd HH:MM:SS:FFF') '\n']);
    fprintf(['Treadmill Last Packet Read Time. Universal Time: ' num2str(lastTMTime) '. Date Time: ' datestr(lastTMTime,'yyyy-mm-dd HH:MM:SS:FFF') '\n\n']);
catch
    fprintf('Unable to get TM packets start and end time');
end

% convert audio times
datlog.audioCues.start = datlog.audioCues.start';
datlog.audioCues.audio_instruction_message = datlog.audioCues.audio_instruction_message';
temp = isnan(datlog.audioCues.start);
disp('\nConverting datalog, current starts \n');
disp(datlog.audioCues.start);
datlog.audioCues.start = datlog.audioCues.start(~temp);
datlog.audioCues.startInRelativeTime = (datlog.audioCues.start - datlog.framenumbers.data(1,2)) * 86400;
datlog.audioCues.startInDateTime = datetime(datlog.audioCues.start,'ConvertFrom','datenum');

temp = all(isnan(datlog.TreadmillCommands.sent(:,1:4)),2);
datlog.TreadmillCommands.sent = datlog.TreadmillCommands.sent(~temp,:);
for z = 1:size(datlog.TreadmillCommands.sent,1)
    datlog.TreadmillCommands.sent(z,5) = etime(datevec(datlog.TreadmillCommands.sent(z,4)),datevec(datlog.framenumbers.data(1,2)));
end

disp('Saving datlog...');
try
    save(savename,'datlog');
catch ME
    disp(ME);
end

end

%% Local Functions

function [bufOut,recs] = drainStimEcho(port,bufIn)
%DRAINSTIMECHO Non-blocking read of Arduino stim-echo records.
%
%   Reads only the bytes already waiting in the serial input buffer (it
%   never blocks), appends them to any partial line carried over from the
%   previous call, and delegates record extraction to PARSESTIMECHO. With
%   firmware that does not echo, NumBytesAvailable stays 0 and this returns
%   immediately with no records, so the controller degrades cleanly.
%
% Inputs:
%   port - open serialport object connected to the Arduino
%   bufIn - partial line text left over from the previous call
%
% Outputs:
%   bufOut - partial line text to carry into the next call
%   recs - Px5 numeric array, one row per parsed pulse:
%          [leg(1=L,2=R), ardStep, stimMs, toRefMs, estSSms]
%
% Toolbox Dependencies: None
%
% See also PARSESTIMECHO, NIRSHREFLEXARDUINOOPENLOOPWITHAUDIO.

nAvail = port.NumBytesAvailable;
if nAvail == 0      % nothing waiting (also the no-echo-firmware no-op path)
    bufOut = bufIn;
    recs = zeros(0,5);
    return;
end
[bufOut,recs] = parseStimEcho([bufIn char(read(port,nAvail,'char'))]);

end

function reportStimPctSS(legNum,ardStep,pctSS)
%REPORTSTIMPCTSS Print the device-echoed actual %-single-stance per stim.
%
%   Surfaces, on the console, where the Arduino actually delivered a pulse
%   relative to single stance so the experimenter can spot gross timing
%   errors online. Values outside the target window are flagged;
%   physically impossible values (<0 or >100) signal an echo/event
%   matching problem rather than a real out-of-tolerance stim.
%
% Inputs:
%   legNum - 1 = left, 2 = right
%   ardStep - Arduino-side step counter for the pulse
%   pctSS - actual stim point as a percentage of single stance
%
% Outputs:
%   None
%
% Toolbox Dependencies: None
%
% See also NIRSHREFLEXARDUINOOPENLOOPWITHAUDIO.

pctTargetSS    = 50; % target stim point (% of single stance)
pctToleranceSS = 5;  % acceptance half-window (%) for the online check
if legNum == 1
    legStr = 'L';
else
    legStr = 'R';
end

if pctSS < 0 || pctSS > 100
    fprintf(['Stim %s step %d: %.1f%% SS (out of range; check echo/' ...
        'event matching)\n'],legStr,ardStep,pctSS);
elseif abs(pctSS - pctTargetSS) > pctToleranceSS
    fprintf('Stim %s step %d: %.1f%% SS (OUTSIDE %d+/-%d%%)\n', ...
        legStr,ardStep,pctSS,pctTargetSS,pctToleranceSS);
else
    fprintf('Stim %s step %d: %.1f%% SS\n',legStr,ardStep,pctSS);
end

end
