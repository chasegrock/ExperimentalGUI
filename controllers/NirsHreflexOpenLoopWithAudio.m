function [RTOTime,LTOTime,RHSTime,LHSTime,commSendTime,commSendFrame] = ...
    NirsHreflexOpenLoopWithAudio(velL,velR,FzThreshold, ...
    profilename,numAudioCountDown,isCalibration,oxysoft_present, ...
    hreflex_present,stimL,stimR)
%This is the adapted from Open loop controller with audio feedback, added
%NIRS events for tied, ramp, split, rest (optional, if exists, always rest
%for 20 seconds). Also send H reflex stimulations every 10 strides during
%mid stance throughout the protocol.
%When to do NIRS event is determined by parsing the velL and velR (0 speeds
%are treated as rest, parse will also find tied, ramp, split, and post)
%
%--- Doc from the OPEN loop controller (controlSpeedWithSteps_edit1 with
% audio countdown) ----
%This function takes two vectors of speeds (one for each treadmill belt)
%and succesively updates the belt speed upon ipsilateral Toe-Off
%The function only updates the belts alternatively, i.e., a single belt
%speed cannot be updated twice without the other being updated
%The first value for velL and velR is the initial desired speed, and new
%speeds will be sent for the following N-1 steps, where N is the length of
%velL
% numAudioCountDown: how many count downs to perform, default [-1], means
% do count down at the end, use -1 as the reserved value. Will play
% audio "Treadmill will start in 3 - 2 - 1 - now" at the beginning, and
% "Treadmill will stop in 3 - 2 - 1 - now" in the end.
% For trials with a change of speed in between, the numAudioCountDown would
% be an array of what stride the speed will change, appended with -1, for
% example [25,225,-1] means to play count down for speed change at stride
% 25 and 225, and then at also count down for treadmill start and stop. The
% last -1 is required in the array.
%Feature Improvement TODO: at this point, the arguments: isCalibration,
%oxysoft_present, hreflex_present are not really accesible when going
%through the UI flow of using AdaptationGUI, it's only setible via code and
%setting params to be global.

%% Set up parameters to communication with NIRS and Arduino (for H-reflex)
%These parameters should ONLY BE CHANGED IF YOU KNOW WHAT YOU ARE DOING.
if nargin < 6 %isCalib not provided, default false.
    isCalibration = false;
end

if nargin < 7
    oxysoft_present = true; %default always true, unless debugging without the NIRS instrument.
end

if nargin < 8
    hreflex_present = true; %default true, unless debugging without Hreflex stimulator.
end

restDuration = 20; %default 20s rest, could change for debugging

%% Open the port to talk to Arduino
if hreflex_present
    try
        % configure and open serial port communication with Arduino
        fprintf('Opening the Arduino serial communication port.\n');
        portArduino = serialport('COM4',115200);
        % configureTerminator(portArduino,'LF');  % set serial COM terminator
        fprintf('Done opening the Arduino serial communication port.\n');
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
        % stimInterval = 5;         % stimulate every 5 strides
        % initStep2SkipForCalib = 5;% skip first strides for settling in
        totalCalibStims = 22; %default [8:2:28] stim current levels x 2 stim at each level

        % load calibration audio for left and right stimulation events
        % TODO: remove audio commands if no longer using for H-reflex
        [audio_data,audio_fs]=audioread('L.mp3');
        CalibAudioL = audioplayer(audio_data,audio_fs);
        [audio_data,audio_fs]=audioread('R.mp3');
        CalibAudioR = audioplayer(audio_data,audio_fs);
    end
    if exist('stimL','var') && exist('stimR','var')
        % if there is a second column in velL and velR indicating whether
        % to stimulate at that stride, ...
        stimInterval = nan; % set the interval to NaN
    else
        stimInterval = 10;  % stimulate every 10 strides
    end
    canStim = false; %initialize so that later the code won't complain even if there is no stimulator.
    % durSSL = zeros(2,1);    % two left single stance durations
    % durSSR = zeros(2,1);    % two right single stance durations
    percentSS2Stim = 0.50;  % percentage of single stance phase
    alpha = 0.9;            % smoothing factor (0 < alpha <= 1)
    estSSL = 396.6;             % estimated single stance duration left
    estSSR = 396.6;             % estimated single stance duration right
    stimDelayL = now; %in units of now
    stimDelayR = now;

    %     %Hreflex Alt Sol. find time from HS to midstance based on interpolation function from Omar
    %     %in young healthy participant. If it's older adutls or clinical
    %     %populations, this need to be changed.
    %     stimDelayL = ((-73.8 * velL/1000) + 384.4)/1000;%output should be in in sec, velL/R is in mm/s, fcn needs m/s
    %     stimDelayR = ((-73.8 * velR/1000) + 384.4)/1000;%in sec
end

%% load GUI handle and audio mp3 files for trial countdown
global PAUSE    % pause button value
global STOP
STOP = false;

if ~ismember(-1,numAudioCountDown)  % if '-1' not included, throw an error
    error('Incorrect input given. -1 must be included.\n');
end

if numAudioCountDown    % copied from open loop audiocountdown controller
    [audio_data,audio_fs]=audioread('TMStartIn3.mp3');
    AudioTMStart3 = audioplayer(audio_data,audio_fs);
    [audio_data,audio_fs]=audioread('TMStopIn3.mp3');
    AudioTMStop3 = audioplayer(audio_data,audio_fs);
    [audio_data,audio_fs]=audioread('2.mp3');
    AudioCount2 = audioplayer(audio_data,audio_fs);
    [audio_data,audio_fs]=audioread('1.mp3');
    AudioCount1 = audioplayer(audio_data,audio_fs);
    [audio_data,audio_fs]=audioread('now.mp3');
    AudioNow = audioplayer(audio_data,audio_fs);
    [audio_data,audio_fs]=audioread('TMChangeIn3.mp3');
    AudioTMChange3 = audioplayer(audio_data,audio_fs);
end

% get handle to the GUI so displayed data can be updated
ghandle = guidata(AdaptationGUI);

%% Set up nirs communication.
% Pop up window to confirm parameter setup, which is helpful in case
% debugging happened between experiment session to avoid mistakenly
% forgetting to log fNIRS data.
button = questdlg(['Confirm that NIRS is recording, oxysoft_present ' ...
    'is 1, and rest duration is 20.']);
if ~strcmp(button,'Yes')
    return;     % abort starting the trial
end

Oxysoft = NaN;  % initialize to 'NaN' unless present
if oxysoft_present
    Oxysoft = actxserver('OxySoft.OxyApplication');
end

% connect to Oxysoft software
disp('Initial Setup')
%Event code hardcoded: I-connected, O-Relax, T-TMStopCountDown, R-Rest
%Event code from initial letter in nirsEventNames: A-AccRamp (to start),
%S-Split, M-Mid, P-PostTied, D-DccRamp2Split
%set up audio players
audioids = {'relax','rest','stopAndRest','TMStartNow'};
instructions = containers.Map();
for i = 1 : length(audioids)
    % disp(strcat(audioids{i},'.mp3'))
    [audio_data,audio_fs]=audioread(strcat(audioids{i},'.mp3'));
    instructions(audioids{i}) = audioplayer(audio_data,audio_fs);
end

%this should be changed if the protocol is changing to no ramp, straight to
%start, then the event would be 'Mid'
tmStartEventName = 'AccRamp';
%save TM will start now also into key Mid. When log event Mid will also
%play audio.
instructions(tmStartEventName) = instructions('TMStartNow');

%% Parse the speed profiles to identify steps where NIRS should be logged
[nirsEventSteps,nirsEventNames] = ...
    parseEventsFromSpeeds(velL(:,1),velR(:,1));
restIdx = strcmp(nirsEventNames,'Rest');
%this is safe to call even if there is no rest in the protocol.
restSteps = nirsEventSteps(restIdx);

%% Ask user what trainIdx iteration they would like to start with
if length(restSteps) > 1 %at least 2 rest exist, then ask which one to start from.
    trainIdx = inputdlg('Which split trainIdx would you like to start from (Valid entries: 1-4. Enter 1 if starting from the beginning)? ');
    disp(['Starting the Split trainIdx from ' trainIdx{1}]);
    trainIdx = str2num(trainIdx{1});
    if trainIdx > 1 %skipping some beginning trains
        restSteps = restSteps(trainIdx:end);
        velL = velL(restSteps(1):end,:); %only keep portions of profile that's after the starting rest.
        velR = velR(restSteps(1):end,:);
        if exist('stimL','var') && exist('stimR','var')
            stimL = stimL(restSteps(1):end,:); %only keep portions of profile that's after the starting rest.
            stimR = stimR(restSteps(1):end,:);
        end
        %now parse the new velL and velR again to get correct event steps and
        %index.
        [nirsEventSteps, nirsEventNames] = parseEventsFromSpeeds(velL(:,1), velR(:,1));
        restIdx = strcmp(nirsEventNames, 'Rest');
        restSteps = nirsEventSteps(restIdx); %this is safe to call even if there is no rest in the protocol.
        manualLoadProfile([],[],ghandle,[],velL(:,1)/1000, velR(:,1)/1000);
    end
    trainIdx = trainIdx - 1; %will be used later for audioCue event suffix (typically starts with Rest1, if entered start from TrainIdx3, should log Rest 3 (nextRest=1 + train3-1)
else
    trainIdx = 0; %will be used later for audioCue event suffix (typically Rest1+0, this is initialized to avoid calling a non-exist variable later)
end

nirsEventSteps([restIdx]) =[]; %remove rest from this array
nirsEventNames([restIdx])=[];
need2LogEvent = false; %initialize to false;
if ~isempty(restSteps)
    need2LogEvent = true;
end
nextRestIdx = 1;
restDurations = [23, 21, 22, 25, 20 ,20 ,24 , 24 , 20, 23, 25,21,21,20, 21 , 25 , 24,21, 24 ,21,22, 25,24 ,22,21];
%this is generated by rng(100); randi([20 25], 1, 25 )

if ~isempty(nirsEventSteps)
    need2LogEvent = true;
end
nextNirsEventIdx = 1;

%% initialize a data structure that saves information about the trial
datlog = struct();
datlog.buildtime = now;%timestamp
temp = datestr(datlog.buildtime);
a = regexp(temp,'-');
temp(a) = '_';
b = regexp(temp,':');
temp(b) = '_';
c = regexp(temp,' ');
temp(c) = '_';
[d,n,e]=fileparts(which(mfilename));...
    savename = [[d '\..\datlogs\'] temp '_' profilename];
set(ghandle.sessionnametxt,'String',[temp '_' n]);
datlog.session_name = savename;
datlog.errormsgs = {};
datlog.messages = cell(1,2);
datlog.framenumbers.header = {'frame #','U Time','Relative Time'};
datlog.framenumbers.data = zeros(300*length(velR)+7200,2);
datlog.forces.header = {'frame #','U time','Rfz','Lfz','Relative Time'};
datlog.forces.data = zeros(300*length(velR)+7200,4);
datlog.stepdata.header = {'Step#','U Time','frame #','Relative Time'};
datlog.stepdata.RHSdata = zeros(length(velR)+50,3);%empty cell theoretically big enough to house all the steps taken
datlog.stepdata.RTOdata = zeros(length(velR)+50,3);
datlog.stepdata.LHSdata = zeros(length(velL)+50,3);
datlog.stepdata.LTOdata = zeros(length(velL)+50,3);
datlog.inclineang = [];
datlog.speedprofile.velL = velL(:,1);
datlog.speedprofile.velR = velR(:,1);
datlog.TreadmillCommands.header = {'RBS','LBS','angle','U Time','Relative Time'};
datlog.TreadmillCommands.read = nan(300*length(velR)+7200,4);
datlog.TreadmillCommands.sent = nan(300*length(velR)+7200,4);%nan(length(velR)+50,4);
datlog.audioCues.start = []; %initialize audioCue log fields.
datlog.audioCues.audio_instruction_message = {};
datlog.stim.header = {'Step#','StimDelayTarget(SerialDate#)','TimeSinceContraTOSerialDate#)'};
datlog.stim.L = [];
datlog.stim.R = [];
% Loop-timing diagnostics (additive; NOT consumed by labTools/SyncDatalog).
% loopSegMs columns: [iterTotal, drawnow/GUI, Vicon read+interop, control+
% stim], all in ms. gateLeadMs* record (send time - single-stance onset),
% i.e., how early MATLAB flagged the stride to the Arduino, in ms.
datlog.diagnostics.header = {'iterTotalMs','guiMs','viconMs','ctrlMs'};
datlog.diagnostics.loopSegMs = zeros(300*length(velR)+7200,4);
datlog.diagnostics.gateLeadMsL = [];
datlog.diagnostics.gateLeadMsR = [];

%do initial save
try
    save(savename,'datlog');
catch ME
    disp(ME);
end

%Default threshold
if nargin<3
    % TODO: Left force plate is getting very noisy. 30N is not enough to be robust.
    FzThreshold = 100; %Newtons (30 is minimum for noise not to be an issue)
elseif FzThreshold < 30
    % warning = ['Warning: Fz threshold too low to be robust to noise, using 30N instead'];
    datlog.messages{end+1,1} = 'Warning: Fz threshold too low to be robust to noise, using 30N instead';
    disp('Warning: Fz threshold too low to be robust to noise, using 30N instead');
end

FzThreshold = 100; %impose 100 threshold because the force plates noise is +-60N sometimes.
datlog.messages{end+1,1} = 'Fz threshold is always set to 100N to be robust to noise even at low speed.';
disp("Fz threshold is always set to 100N to be robust to noise even at low speed.")

% check that velL and velR are of equal length
N = length(velL) + 1;
if length(velL) ~= length(velR)
    disp('WARNING, velocity vectors of different length!');
    datlog.messages{end+1,1} = 'Velocity vectors of different length selected';
end

% initialize nexus & treadmill communications
try
    %New code DMMO
    HostName = 'localhost:801';
    addpath('..\dotNET');
    dssdkAssembly = which('ViconDataStreamSDK_DotNET.dll');
    if dssdkAssembly == ""
        [file,path] = uigetfile('*.dll');
        dssdkAssembly = fullfile(path,file);
    end

    NET.addAssembly(dssdkAssembly);
    MyClient = ViconDataStreamSDK.DotNET.Client();
    MyClient.Connect(HostName);
    % enable some different data types
    out = MyClient.EnableSegmentData();
    out = MyClient.EnableMarkerData();
    out = MyClient.EnableUnlabeledMarkerData();
    out = MyClient.EnableDeviceData();

    MyClient.SetStreamMode(ViconDataStreamSDK.DotNET.StreamMode.ClientPull);
catch ME
    disp('Error in creating Nexus Client Object/communications see datlog for details');
    datlog.errormsgs{end+1} = 'Error in creating Nexus Client Object/communications';
    datlog.errormsgs{end+1} = ME;   % store specific error
    disp(ME);
end

try
    fprintf(['Open TM Comm. Date Time: ',datestr(now,'yyyy-mm-dd HH:MM:SS:FFF') '\n'])
    t = openTreadmillComm();
    fprintf(['Done Opening. Date Time: ',datestr(now,'yyyy-mm-dd HH:MM:SS:FFF') '\n'])
catch ME
    disp('Error in creating TCP connection to Treadmill, see datlog for details...');
    datlog.errormsgs{end+1} = 'Error in creating TCP connection to Treadmill';
    datlog.errormsgs{end+1} = ME;
    disp(ME);
end

try     % so that if something fails, communications are closed properly
    MyClient.GetFrame();
    % listbox{end+1} = ['Nexus and Bertec Interfaces initialized: ' num2str(clock)];
    datlog.messages(end+1,:) = {'Nexus and Bertec Interfaces initialized: ', now};
    % set(ghandle.listbox1,'String',listbox);

    % initiate variables
    new_stanceL = false;
    new_stanceR = false;
    phase=0;% 0= Double Support, 1 = single L support, 2 = single R support
    LstepCount=1;
    RstepCount=1;
    RTOTime(N) = now;
    LTOTime(N) = now;
    RHSTime(N) = now;
    LHSTime(N) = now;
    commSendTime = zeros(2*N-1,6);
    commSendFrame = zeros(2*N-1,1);

    [RBS,LBS,cur_incl] = readTreadmillPacket(t); % read treadmill incline angle
    lastRead = now;
    datlog.inclineang = cur_incl;
    read_theta = cur_incl;

    %Added 5/10/2016 for Nimbus start sync, create file on hard drive, then
    %delete later after the task is done.
    time1 = now;
    syncname = fullfile(tempdir,'SYNCH.dat');
    [f,~]=fopen(syncname,'wb');
    fclose(f);
    time2 = now;
    disp(etime(datevec(time2),datevec(time1)));

    disp('File creation time');

    %if no rest (regular adapt block) or 1st stride speed is non 0, start with audio count down.
    if (isempty(restSteps) || velL(1,1) ~=0) && numAudioCountDown %No rest, will start right away. Add a 3-2-1 count down.
        fprintf(['Ready to count down. Date Time: ',datestr(now,'yyyy-mm-dd HH:MM:SS:FFF') '\n'])
        play(AudioTMStart3);
        pause(2.5);
        play(AudioCount2);
        pause(1);
        play(AudioCount1);
        pause(1);
        play(AudioNow)
        %log it without saying "TM will start now" again.
        datlog = nirsEvent('Mid_noaudio','M',['Mid' num2str(nextRestIdx-1)],instructions,datlog,Oxysoft,oxysoft_present);
    end

    %Send first speed command & store
    acc = 1500; %used to be 3500, made it smaller for start to be more smooth, 1500 would achieve 1.5m/s in 1second, which is beyond the expected max speed we will ever use in this protocol.
    % acc = 400; %Changed by Dulce to test patients with stroke in the cerebellum w balance problems
    payload = getPayload(velR(1,1),velL(1,1),acc,acc,cur_incl);
    sendTreadmillPacket(payload,t);
    datlog.TreadmillCommands.firstSent = [velR(RstepCount,1),velL(LstepCount,1),acc,acc,cur_incl,now];%record the command
    commSendTime(1,:) = clock;
    datlog.TreadmillCommands.sent(1,:) = [velR(RstepCount,1),velL(LstepCount,1),cur_incl,now];%record the command
    datlog.messages(end+1,:) = {'First speed command sent', now};
    datlog.messages{end+1,1} = ['Lspeed = ' num2str(velL(LstepCount,1)) ', Rspeed = ' num2str(velR(RstepCount,1))];
    %% Main loop

    old_velR = libpointer('doublePtr',velR(1,1));
    old_velL = libpointer('doublePtr',velL(1,1));
    frameind = libpointer('doublePtr',1);
    framenum = libpointer('doublePtr',0);

    if numAudioCountDown %Adapted from open loop audio countdown
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
    tic;

    while ~STOP     % only runs if stop button is not pressed
        while PAUSE % only runs if pause button is pressed
            pause(.2);
            datlog.messages(end+1,:) = {'Loop paused at ', now};
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
        drawnow;
        old_stanceL = new_stanceL;
        old_stanceR = new_stanceR;

        % read frame, update necessary structures
        MyClient.GetFrame();
        framenum.Value = MyClient.GetFrameNumber().FrameNumber;
        datlog.framenumbers.data(frameind.Value,:) = [framenum.Value now];

        % read treadmill, if enough time has elapsed since last read
        aux = datevec(now) - datevec(lastRead);
        if aux(6) > 0.1 || any(aux(1:5) > 0)    % only read if enough time has elapsed
            [RBS,LBS,read_theta] = readTreadmillPacket(t);  % also read what the treadmill is doing
            lastRead = now;
        end

        datlog.TreadmillCommands.read(frameind.Value,:) = [RBS,LBS,read_theta,now];%record the read
        set(ghandle.RBeltSpeed_textbox,'String',num2str(RBS/1000));
        set(ghandle.LBeltSpeed_textbox,'String',num2str(LBS/1000));
        frameind.Value = frameind.Value + 1;

        % assuming there is only 1 subject, and that I care about a marker called MarkerA (e.g. Subject=Wand)
        Fz_R = MyClient.GetDeviceOutputValue('Right Treadmill','Fz');
        Fz_L = MyClient.GetDeviceOutputValue('Left Treadmill','Fz');
        datlog.forces.data(frameind.Value,:) = [framenum.Value now Fz_R.Value Fz_L.Value];
        Hx = MyClient.GetDeviceOutputValue('Handrail','Fx');
        Hy = MyClient.GetDeviceOutputValue('Handrail','Fy');
        Hz = MyClient.GetDeviceOutputValue('Handrail','Fz');
        Hm = sqrt(Hx.Value^2+Hy.Value^2+Hz.Value^2);
        %if handrail force is too high, notify the experimentor
        if (Hm > 25)
            set(ghandle.figure1,'Color',[238 5 5]./255);
        else
            set(ghandle.figure1,'Color',[1 1 1]);
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
        % read from treadmill
        % [RBS,LBS,theta] = getCurrentData(t);
        % set(ghandle.LBeltSpeed_textbox,'String',num2str(LBS/1000));
        % set(ghandle.RBeltSpeed_textbox,'String',num2str(RBS/1000));

        new_stanceL = Fz_L.Value < -FzThreshold;
        new_stanceR = Fz_R.Value < -FzThreshold;
        LHS = new_stanceL && ~old_stanceL;
        RHS = new_stanceR && ~old_stanceR;
        LTO = ~new_stanceL && old_stanceL;
        RTO = ~new_stanceR && old_stanceR;

        %Maquina de estados: 0 = initial, 1 = single L, 2 = single R,
        %3 = DS from single L, 4 = DS from single R
        switch phase
            case 0          % DS, only initial phase
                if RTO      % go to single L
                    phase = 1;
                    RstepCount = RstepCount + 1;
                    % RTOTime(RstepCount) = TimeStamp;
                    RTOTime(RstepCount) = now;
                    datlog.stepdata.RTOdata(RstepCount-1,:) = [RstepCount-1,now,framenum.Value];
                    % set(ghandle.RBeltSpeed_textbox,'String',num2str(velR(RstepCount,1)/1000));
                elseif LTO  % go to single R
                    phase = 2;
                    LstepCount=LstepCount+1;
                    % LTOTime(LstepCount) = TimeStamp;
                    LTOTime(LstepCount) = now;
                    datlog.stepdata.LTOdata(LstepCount-1,:) = [LstepCount-1,now,framenum.Value];
                    % set(ghandle.LBeltSpeed_textbox,'String',num2str(velL(LstepCount,1)/1000));
                end
            case 1          % single L
                if RHS
                    phase = 3;
                    datlog.stepdata.RHSdata(RstepCount-1,:) = [RstepCount-1,now,framenum.Value];
                    % RHSTime(RstepCount) = TimeStamp;
                    RHSTime(RstepCount) = now;
                    % RHS marks the end of single stance L
                    % durSSL(1) = durSSL(2);  % overwrite previous SSL duration
                    durSSL = RHSTime(RstepCount) - RTOTime(RstepCount); % compute duration of left leg single stance phase
                    % delay of left leg stimulation from RTO is mean of single
                    % stance duration divided by two (since targeting mid-point
                    % of single stance for stimulus pulse)

                    % weighting most recent SSL duration more
                    % heavily (e.g., 67% since likely more predictive)
                    % stimDelayL = (0.33*durSSL(1) + 0.67*durSSL(2)) / 2;
                    % estimate single stance duration using exponential updating factor
                    estSSL = alpha * durSSL + (1.0 - alpha) * estSSL;
                    stimDelayL = estSSL * percentSS2Stim;
                    set(ghandle.Right_step_textbox,'String',num2str(RstepCount-1));
                    % plot cursor
                    plot(ghandle.profileaxes,RstepCount-1,velR(RstepCount,1)/1000,'o','MarkerFaceColor',[1 0.6 0.78],'MarkerEdgeColor','r');
                    % drawnow;
                    canStim = true; % allow stim after HS and start timer
                    tic;

                    if LTO %In case DS is too short and a full cycle misses the phase switch
                        phase = 2;
                        LstepCount=LstepCount+1;
                        % LTOTime(LstepCount) = TimeStamp;
                        LTOTime(LstepCount) = now;
                        datlog.stepdata.LTOdata(LstepCount-1,:) = [LstepCount-1,now,framenum.Value];
                        % set(ghandle.LBeltSpeed_textbox,'String',num2str(velL(LstepCount,1)/1000));
                    end
                end
            case 2          % single R
                if LHS
                    phase = 4;
                    datlog.stepdata.LHSdata(LstepCount-1,:) = [LstepCount-1,now,framenum.Value];
                    % LHSTime(LstepCount) = TimeStamp;
                    LHSTime(LstepCount) = now;
                    % LHS marks the end of single stance R
                    % durSSR(1) = durSSR(2);  % overwrite previous SSR duration
                    durSSR = LHSTime(LstepCount) - LTOTime(LstepCount);  % compute duration of right leg single stance phase
                    % delay of right leg stimulation from LTO is mean of single
                    % stance duration divided by two (since targeting mid-point
                    % of single stance for stimulus pulse)
                    % stimDelayR = (0.33*durSSR(1) + 0.67*durSSR(2)) / 2;
                    % estimate single stance duration using exponential updating factor
                    estSSR = alpha * durSSR + (1.0 - alpha) * estSSR;
                    stimDelayR = estSSR * percentSS2Stim;
                    set(ghandle.Left_step_textbox,'String',num2str(LstepCount-1));
                    % plot cursor
                    plot(ghandle.profileaxes,LstepCount-1,velL(LstepCount,1)/1000,'o','MarkerFaceColor',[0.68 .92 1],'MarkerEdgeColor','b');
                    % drawnow;
                    canStim = true; % allow stim after HS and start timer
                    tic;

                    if RTO %In case DS is too short and a full cycle misses the phase switch
                        phase = 1;
                        RstepCount=RstepCount+1;
                        % RTOTime(RstepCount) = TimeStamp;
                        RTOTime(RstepCount) = now;
                        datlog.stepdata.RTOdata(RstepCount-1,:) = [RstepCount-1,now,framenum.Value];
                        % set(ghandle.RBeltSpeed_textbox,'String',num2str(velR(RstepCount,1)/1000));
                    end
                end
            case 3 %DS, coming from single L
                if LTO
                    phase = 2; %To single R
                    LstepCount=LstepCount+1;
                    % LTOTime(LstepCount) = TimeStamp;
                    LTOTime(LstepCount) = now;
                    datlog.stepdata.LTOdata(LstepCount-1,:) = [LstepCount-1,now,framenum.Value];
                    % set(ghandle.LBeltSpeed_textbox,'String',num2str(velL(LstepCount)/1000));
                end
            case 4 %DS, coming from single R
                if RTO
                    phase = 1; %To single L
                    RstepCount=RstepCount+1;
                    % RTOTime(RstepCount) = TimeStamp;
                    RTOTime(RstepCount) = now;
                    datlog.stepdata.RTOdata(RstepCount-1,:) = [RstepCount-1,now,framenum.Value];
                    % set(ghandle.RBeltSpeed_textbox,'String',num2str(velR(RstepCount)/1000));
                end
        end

        if hreflex_present      % only do this if has the stimulator
            % use contralateral leg (i.e., LHS - LTO) to determine R mid-single stance
            timeSinceLTO = now - LTOTime(LstepCount);
            % timeSinceHS = toc; % Hreflex Alt Sol.
            if isnan(stimInterval)
                shouldStimR = logical(stimR(RstepCount));
                shouldStimL = logical(stimL(LstepCount));
            else
                shouldStimR = mod(RstepCount,stimInterval) == 4;
                shouldStimL = mod(LstepCount,stimInterval) == 4;
            end

            if (shouldStimR && phase == 2 && canStim && (timeSinceLTO >= 0.80*stimDelayR))
                % if (~mod(RstepCount,stimInterval) && phase == 2 && canStim &&
                % timeSinceHS >= 0.8*stimDelayR(RstepCount)) % single stance R detected & estimated in mid stance already (from stimDelay).%Hreflex Alt Sol.
                if isCalibration && RstepCount <= initStep2SkipForCalib %don't stimulate the first 5 strides, give participants time to settle in.
                    continue;
                end

                if isCalibration    % play sound
                    play(CalibAudioR);
                end

                try         % send command to Arduino to stimulate right
                    write(portArduino,2,'int16'); % hard-coded here and in Arduino. Don't change this.
                catch ME
                    % handle any potential communication errors
                    warning(ME.identifier,['Failed to send right leg ' ...
                        'stimulation command to Arduino: %s'],ME.message);
                end
                canStim = false;
                datlog.stim.R(end+1,:) = [RstepCount, stimDelayR, timeSinceLTO];
                datlog.diagnostics.gateLeadMsR(end+1) = ...
                    timeSinceLTO*86400000;  % gate lead from LTO (ms)
            end

            % use contralateral leg (i.e., RHS - RTO) to determine L mid-single stance
            timeSinceRTO = now - RTOTime(RstepCount);
            % Changed to using ONLY RstepCount to force stimulation order
            % of left and right within one stride
            if (shouldStimL && phase == 1 && canStim && (timeSinceRTO >= 0.80*stimDelayL))
                % if (~mod(LstepCount,stimInterval) && phase == 1 && canStim && timeSinceHS >= 0.8*stimDelayL(LstepCount)) % single L detected & estimated in mid stance already (from stimDelay)%Hreflex Alt Sol.
                if isCalibration && RstepCount <= initStep2SkipForCalib %don't stimulate the first 5 strides, give participants time to settle in.
                    continue;
                end

                if isCalibration    % play sound
                    play(CalibAudioL);
                end

                try         % send command to Arduino to stimulate left
                    write(portArduino,1,'int16');
                catch ME
                    % handle any potential communication errors
                    warning(ME.identifier,['Failed to send left leg ' ...
                        'stimulation command to Arduino: %s'],ME.message);
                end

                canStim = false;    % prevent immediate stimulation
                datlog.stim.L(end+1,:) = [RstepCount, stimDelayL, timeSinceRTO];
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
                    fprintf(['Change at ', num2str(speedChangeStride),'-3 Stride . Date Time: ',datestr(now,'yyyy-mm-dd HH:MM:SS:FFF') '\n'])
                    fprintf('Current step count L: %d, R:%d, countDownIdx: %d, idx offset: %d\n',LstepCount,RstepCount,countDownIdx, countDownIdxOffset)

                    %log in NIRS that audio count down is happening. FIXME
                    datlog = nirsEvent('TMStopAudioCountDown', 'D', ['TMStopAudioCountDown_Train' num2str(nextRestIdx-1+trainIdx)], instructions, datlog, Oxysoft, oxysoft_present);

                    play(AudioTMChange3);
                    countDownPlayed(countDownIdx) = true; %This should only be run once
                    countDownIdx = countDownIdx + 1;
                elseif (LstepCount == speedChangeStride-1 || RstepCount == speedChangeStride-1) && ~countDownPlayed(2+countDownIdxOffset)
                    fprintf(['Change-2 Stride . Date Time: ',datestr(now,'yyyy-mm-dd HH:MM:SS:FFF') '\n'])
                    fprintf('Current step count L: %d, R:%d, countDownIdx: %d, idx offset: %d\n',LstepCount,RstepCount,countDownIdx, countDownIdxOffset)
                    play(AudioCount2);
                    countDownPlayed(countDownIdx) = true; %This should only be run once
                    countDownIdx = countDownIdx + 1;
                elseif (LstepCount == speedChangeStride || RstepCount == speedChangeStride) && ~countDownPlayed(3+countDownIdxOffset)
                    fprintf(['Change at ', num2str(speedChangeStride),' Last Stride . Date Time: ',datestr(now,'yyyy-mm-dd HH:MM:SS:FFF') '\n'])
                    fprintf('Current step count L: %d, R:%d, countDownIdx: %d, idx offset: %d\n',LstepCount,RstepCount,countDownIdx, countDownIdxOffset)
                    disp(countDownPlayed)
                    play(AudioCount1)
                    countDownPlayed(countDownIdx) = true; %This should only be run once
                    countDownIdx = countDownIdx + 1;
                elseif (LstepCount == speedChangeStride+1 || RstepCount == speedChangeStride+1) && ~countDownPlayed(4+countDownIdxOffset)
                    fprintf(['Change Stride +1. Date Time: ',datestr(now,'yyyy-mm-dd HH:MM:SS:FFF') '\n'])
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
                fprintf(['-3 Stride . Date Time: ',datestr(now,'yyyy-mm-dd HH:MM:SS:FFF') '\n'])
                %log in NIRS that audio count down is happening.
                datlog = nirsEvent('TMStopAudioCountDown', 'D', ['TMStopAudioCountDown_Train' num2str(nextRestIdx-1+trainIdx)], instructions, datlog, Oxysoft, oxysoft_present);
                play(AudioTMStop3); %takes 2 seconds to say "treadmill will stop in"
                countDownPlayed(end-3) = true; %This should only be run once
            elseif ~countDownPlayed(end-2) && (...
                    (nextRestIdx <= length(restSteps) && (LstepCount == restSteps(nextRestIdx)-2 || RstepCount == restSteps(nextRestIdx)-2)))
                fprintf(['-2 Stride . Date Time: ',datestr(now,'yyyy-mm-dd HH:MM:SS:FFF') '\n'])
                play(AudioCount2);
                countDownPlayed(end-2) = true; %This should only be run once
            elseif ~countDownPlayed(end-1) && (...
                    (nextRestIdx <= length(restSteps) && (LstepCount == restSteps(nextRestIdx)-1 || RstepCount == restSteps(nextRestIdx)-1)))
                fprintf(['-1 Stride . Date Time: ',datestr(now,'yyyy-mm-dd HH:MM:SS:FFF') '\n'])
                play(AudioCount1);
                countDownPlayed(end-1) = true; %This should only be run once
            end

            %Trial will end soon.
            if (LstepCount == N-3 || RstepCount == N-3) && ~countDownPlayed(end-3)
                fprintf(['-3 Stride . Date Time: ',datestr(now,'yyyy-mm-dd HH:MM:SS:FFF') '\n'])
                %log in NIRS that audio count down is happening.
                datlog = nirsEvent('TMStopAudioCountDown', 'D', ['TMStopAudioCountDown_Train' num2str(nextRestIdx-1+trainIdx)], instructions, datlog, Oxysoft, oxysoft_present);
                play(AudioTMStop3);
                countDownPlayed(end-3) = true; %This should only be run once
            elseif (LstepCount == N-1 || RstepCount == N-1) && ~countDownPlayed(end-2)
                fprintf(['-2 Stride . Date Time: ',datestr(now,'yyyy-mm-dd HH:MM:SS:FFF') '\n'])
                play(AudioCount2);
                countDownPlayed(end-2) = true; %This should only be run once
            end
        end

        if LstepCount >= N || RstepCount >= N%if taken enough steps, stop
            if numAudioCountDown %adapted from open loop audiocoudntdown
                fprintf(['Last Stride . Date Time: ',datestr(now,'yyyy-mm-dd HH:MM:SS:FFF') '\n'])
                play(AudioCount1);
            end
            break
            %only send a command if it is different from the previous one. Don't
            %overload the treadmill controller with commands
        elseif (velR(RstepCount,1) ~= old_velR.Value) || (velL(LstepCount,1) ~= old_velL.Value)% && LstepCount<N && RstepCount<N
            payload = getPayload(velR(RstepCount,1),velL(LstepCount,1),acc,acc,cur_incl);
            sendTreadmillPacket(payload,t);
            datlog.TreadmillCommands.sent(frameind.Value,:) = [velR(RstepCount,1),velL(LstepCount,1),cur_incl,now]; %record the command
            disp(['Packet sent, Lspeed = ' num2str(velL(LstepCount,1)) ', Rspeed = ' num2str(velR(RstepCount,1))])
            % if (velR(RstepCount,1) ~= old_velR.Value)
            %  set(ghandle.RBeltSpeed_textbox,'String',num2str(velR(RstepCount,1)/1000));
            % else %(velL(LstepCount) ~= old_velL.Value)
            %  set(ghandle.LBeltSpeed_textbox,'String',num2str(velL(LstepCount,1)/1000));
            % end
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
            if countDownPlayed(end-1) %just counted down from 3-2-1, probably should say TM now.
                play(AudioNow);
                countDownPlayed(end-3:end) = false; %reset countdown flag
            end

            %make sure TM is at zero and hold it there.
            [payload] = getPayload(0,0,acc,acc,cur_incl);
            sendTreadmillPacket(payload,t);
            pause(1.5); %give some time for the previous instruction to finish.
            %this function plays the audio, sends event to NIRS, and logs it in datlog
            datlog = nirsEvent('rest', 'R', ['Rest' num2str(nextRestIdx+trainIdx)], instructions, datlog, Oxysoft, oxysoft_present);
            %hold the code here untill break is over.
            %         pause(restDuration);
            %instead of a full 20s pause, run a WHILE loop here so that the program wouldn't hang and would
            % respond to STOP in the rest break.
            restStarted = clock;
            restDone = false;
            restDuration = restDurations(nextRestIdx);
            while ~restDone && ~STOP
                t_diff=clock-restStarted; %aux 1x6 array in year, month, day, hour, min, sec
                t_diff = abs((t_diff(4)*3600)+(t_diff(5)*60)+t_diff(6)); %compute difference in seconds
                %             t_diff = etime(clock, lastRead); %this sometimes would error
                %             out.
                if t_diff >= restDuration-0.5%aux(6)>=restDuration || any(aux(1:5)>0) %enough time to rest has passed. moving on, should never be in the second or loop situation
                    restDone = true;
                    t_diff
                else
                    pause(0.8); %pause for a bit so we are not doing the while loop nonstop.
                    [~,~,~] = readTreadmillPacket(t); %this is to maintain communication with the treamdill to avoid lag after the break.
                end
            end
            if STOP %anytime if STOP is pressed, quit the while loop
                break; %break the while loop
            end
            %done, advance step count to the next walking event.(notice that
            %assumes there is always an event immediately after the rest,
            %(e.g., rest is at step 200, there will be an event at step 250,
            %and rest duration is coded as 50 steps).
            if nextNirsEventIdx <= length(nirsEventSteps) %assign stepCont to next event, only if there is still more event coming.
                LstepCount = nirsEventSteps(nextNirsEventIdx);
                RstepCount = nirsEventSteps(nextNirsEventIdx); %it appears that we always take coded stride - 1 steps (but that's how it is in open loop controller too bc stepcount started at 1 intead of 0)
            else %otherwise assume rest is the last thing the script will do.
                STOP = true; %manually set stop to the experiments. Otherwise
            end
            need2LogEvent = true;
            nextRestIdx = nextRestIdx + 1;
        end

        % record per-iteration loop-timing diagnostics (additive)
        loopCount = loopCount + 1;
        datlog.diagnostics.loopSegMs(loopCount,:) = ...
            [toc(tIter)*1000, segGuiMs, segViconMs, toc(tSeg)*1000];
    end %While, when STOP button is pressed

    % trim unused preallocated diagnostic rows
    datlog.diagnostics.loopSegMs(loopCount+1:end,:) = [];

    if STOP
        % datlog.messages{end+1} = ['Stop button pressed at: ' num2str(now) ' ,stopping... '];
        % log = ['Stop button pressed, stopping... ' num2str(clock)];
        % listbox{end+1} = log;
        % Shuqi: 02/07/2024, adjusted to log time with precision
        datlog.messages(end+1,:) = {'Stop button pressed at: [see next cell] ,stopping... ', now};
        disp(['Stop button pressed, stopping... ' num2str(clock)]);
        set(ghandle.Status_textbox,'String','Stopping...');
        set(ghandle.Status_textbox,'BackgroundColor','red');
    end

    % log the final event marking trial end, without audio telling participant
    % to relax. This log could happen 1-2 seconds before TM fully stops which
    % is ok bc stopping usually could be perturbing and this probably marks a
    % better steady state ending.
    % audio cue here would be too early, so just log the event without saying anything yet (see Alt Option below).
    datlog = nirsEvent('relax_noaudio','O','Trial_End', instructions, datlog, Oxysoft, oxysoft_present);

catch ME
    datlog.errormsgs{end+1} = 'Error ocurred during the control loop';
    datlog.errormsgs{end+1} = ME;
    % log = ['Error ocurred during the control loop'];%End try
    % listbox{end+1} = log;
    disp('Error ocurred during the control loop, see datlog for details...');
end
%% Closing routine
%End communications
try
    save(savename,'datlog');
    delete(syncname);%added 5/10/2016 delete sync file in prep for next trial
catch ME
    disp(ME);
end

if hreflex_present      % if hreflex, close communication with arduino
    datlog.messages(end+1,:) = {'Start to close Arduino Port ', now};
    fprintf('Closing serial port communication with the Arduino...\n');
    try
        flush(portArduino);     % flush remaining data in the buffer
        delete(portArduino);    % close and clear the serial port object
        fprintf('Successfully closed the Arduino serial port.\n');
    catch ME
        % handle errors and log the exception message
        warning(ME.identifier, ...
            'Failed to properly close Arduino serial port: %s',ME.message);
    end
end

try %stopping the treadmill
    %see if the treadmill is supposed to stop at the end of the profile
    if get(ghandle.StoptreadmillEND_checkbox,'Value')==1 && STOP ~=1
        set(ghandle.Status_textbox,'String','Stopping...');
        set(ghandle.Status_textbox,'BackgroundColor','red');
        set(ghandle.figure1,'Color',[1,1,1]);
        pause(.5) %Do we need this? what for? -- Pablo 26/2/2018
        fprintf(['Trying to close TM1. Date Time: ',datestr(now,'yyyy-mm-dd HH:MM:SS:FFF') '\n'])
        smoothStop(t);
        if numAudioCountDown %no need to say now again, changed the logic to say it earlier at stepN
            play(AudioNow)
        end
        %see if the treadmill should be stopped when the STOP button is pressed
    elseif get(ghandle.StoptreadmillSTOP_checkbox,'Value')==1 && STOP == 1
        set(ghandle.Status_textbox,'String','Stopping');
        set(ghandle.Status_textbox,'BackgroundColor','red');
        pause(.3)
        fprintf(['Trying to close TM2. Date Time: ',datestr(now,'yyyy-mm-dd HH:MM:SS:FFF') '\n'])
        smoothStop(t);
    end

    %Say  "Relax" without sending another event to NIRS (last arg always false).
    %Alt Option: this could be a good time to say "Relax" and the time
    %point would be exactly when TM stopped, but logging timing is better right after the last stride without audio and before the closing routine above.
    %the activity during the closing routine shouldn't really be analyzed.
    %     datlog = nirsEvent('relax','O','Trial_End_TMStop', instructions, datlog, Oxysoft, false);

    %Check if treadmill stopped, if not, try again:
    pause(1)
    fprintf(['Trying to close TM3. Date Time: ',datestr(now,'yyyy-mm-dd HH:MM:SS:FFF') '\n'])
    [cur_speedR,cur_speedL,cur_incl] = readTreadmillPacket(t);
    stopped = cur_speedR==0 && cur_speedL==0;
    counter=0;
    while ~stopped && counter<5 %Try 5 times to stop the treadmill smoothly
        disp('Treadmill did not stop when requested. Trying again.')
        % smoothStop(t)
        fprintf(['Trying to close TM4. Date Time: ',num2str(counter),datestr(now,'yyyy-mm-dd HH:MM:SS:FFF') '\n'])
        pause(1) %Give time to smoothStop to execute everything
        [cur_speedR,cur_speedL,cur_incl] = readTreadmillPacket(t)
        stopped = cur_speedR==0 && cur_speedL==0;
        counter=counter+1;
    end
    if counter>=5
        disp('Could not stop treadmill after 5 attempts')
    end
catch ME
    datlog.errormsgs{end+1} = 'Error stopping the treadmill';
    datlog.errormsgs{end+1} = ME;
end

disp('closing comms');
try
    closeNexusIface(MyClient); %This was on before
    closeTreadmillComm(t);
catch ME
    datlog.errormsgs{end+1} = ['Error ocurred when closing communications with Nexus & Treadmill at ' num2str(clock)];
    datlog.errormsgs{end+1} = ME;
    % log = ['Error ocurred when closing communications with Nexus & Treadmill (maybe they were not open?) ' num2str(clock)];
    % listbox{end+1} = log;
    disp(['Error ocurred when closing communications with Nexus & Treadmill, see datlog for details ' num2str(clock)]);
    disp(ME);
end

disp('converting time in datlog...');
%convert time data into clock format then re-save
datlog.buildtime = datestr(datlog.buildtime);

%convert frame times
temp = find(datlog.framenumbers.data(:,1)==0,1,'first');
datlog.framenumbers.data(temp:end,:) = [];
for z = 1:temp-1
    datlog.framenumbers.data(z,3) = etime(datevec(datlog.framenumbers.data(z,2)),datevec(datlog.framenumbers.data(1,2)));
end
%convert force times
datlog.forces.data(1,:) = [];
temp = find(datlog.forces.data(:,1)==0,1,'first');
datlog.forces.data(temp:end,:) = [];
for z = 1:temp-1
    datlog.forces.data(z,5) = etime(datevec(datlog.forces.data(z,2)),datevec(datlog.forces.data(1,2)));
end
%convert RHS times
% temp = leng
% temp = find(datlog.stepdata.RHSdata(:,1) == 0,1,'first');
% remove the clean up routine, bc 0 now means break.
datlog.stepdata.RHSdata(temp:end,:) = [];
temp = size(datlog.stepdata.RHSdata,1)+1;
for z = 1:temp-1
    datlog.stepdata.RHSdata(z,4) = etime(datevec(datlog.stepdata.RHSdata(z,2)),datevec(datlog.framenumbers.data(1,2)));
end
%convert LHS times
% temp = find(datlog.stepdata.LHSdata(:,1) == 0,1,'first');% remove the clean up routine, bc 0 now means break.
% datlog.stepdata.LHSdata(temp:end,:) = [];
for z = 1:temp-1
    datlog.stepdata.LHSdata(z,4) = etime(datevec(datlog.stepdata.LHSdata(z,2)),datevec(datlog.framenumbers.data(1,2)));
end
%convert RTO times
% temp = find(datlog.stepdata.RTOdata(:,1) == 0,1,'first');% remove the clean up routine, bc 0 now means break.
% datlog.stepdata.RTOdata(temp:end,:) = [];
for z = 1:temp-1
    datlog.stepdata.RTOdata(z,4) = etime(datevec(datlog.stepdata.RTOdata(z,2)),datevec(datlog.framenumbers.data(1,2)));
end
%convert LTO times
% temp = find(datlog.stepdata.LTOdata(:,1) == 0,1,'first');% remove the clean up routine, bc 0 now means break.
% datlog.stepdata.LTOdata(temp:end,:) = [];
for z = 1:temp-1
    datlog.stepdata.LTOdata(z,4) = etime(datevec(datlog.stepdata.LTOdata(z,2)),datevec(datlog.framenumbers.data(1,2)));
end

%convert command times
temp = all(isnan(datlog.TreadmillCommands.read(:,1:4)),2);
datlog.TreadmillCommands.read=datlog.TreadmillCommands.read(~temp,:);
for z = 1:size(datlog.TreadmillCommands.read,1) %compute relative time and fill in the last column
    datlog.TreadmillCommands.read(z,5) = etime(datevec(datlog.TreadmillCommands.read(z,4)),datevec(datlog.framenumbers.data(1,2)));
end

%Added by Shuqi 1/18/2022
try
    firstTMTime = datlog.TreadmillCommands.read(1,4);
    lastTMTime = datlog.TreadmillCommands.read(end,4);
    fprintf(['\n\nTreadmill First Packet Read Time. Universal Time: ', num2str(firstTMTime), '. Date Time: ',datestr(firstTMTime,'yyyy-mm-dd HH:MM:SS:FFF') '\n'])
    fprintf(['Treadmill Last Packet Read Time. Universal Time: ', num2str(lastTMTime), '. Date Time: ',datestr(lastTMTime,'yyyy-mm-dd HH:MM:SS:FFF') '\n\n'])
catch
    fprintf('Unable to get TM packets start and end time')
end

%convert audio times
datlog.audioCues.start = datlog.audioCues.start';
datlog.audioCues.audio_instruction_message = datlog.audioCues.audio_instruction_message';
temp = isnan(datlog.audioCues.start);
disp('\nConverting datalog, current starts \n');
disp(datlog.audioCues.start);
datlog.audioCues.start=datlog.audioCues.start(~temp);
datlog.audioCues.startInRelativeTime = (datlog.audioCues.start- datlog.framenumbers.data(1,2))*86400;
datlog.audioCues.startInDateTime = datetime(datlog.audioCues.start, 'ConvertFrom','datenum');

temp = all(isnan(datlog.TreadmillCommands.sent(:,1:4)),2);
datlog.TreadmillCommands.sent=datlog.TreadmillCommands.sent(~temp,:);
for z = 1:size(datlog.TreadmillCommands.sent,1)
    datlog.TreadmillCommands.sent(z,5) = etime(datevec(datlog.TreadmillCommands.sent(z,4)),datevec(datlog.framenumbers.data(1,2)));
end

disp('saving datlog...');
try
    save(savename,'datlog');
catch ME
    disp(ME);
end

