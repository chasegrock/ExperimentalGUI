%RUNPROTOCOL_SPINALADAPTBOUTS Automate the SpinalAdapt experimental session.
%
%   Guides the experimenter through profile generation, pre- and post-
%   session H-reflex calibration trials, all conditions in sequence, and
%   post-session data transfer to the server. Edit the EXPERIMENTER
%   section below before each session run.
%
% Toolbox Dependencies:
%   None (external: AdaptationGUI, Vicon Nexus, labTools dataMotion)
%
% See also GENERATEPROFILES_SPINALADAPTBOUTS, RUNWALKINGCALIBRATIONS,
%   TRANSFERDATA_SPINALADAPTBOUTS.

%% EXPERIMENTER: Enter Subject-Specific Parameters Before Each Session
ramp2Split = false; % SAH1-16 ramp2Split = true; also there was a coding
% error such that 1st train 1st tied-split only had 10 strides tied before
% split instead of 20 tied as planned. Starting 7/8/2024 use the non-ramp
% version with the mistake corrected (1st train has 20 tied before split).
speedRatio = 0.7;   % slow/fast; SAH1-16 used speedRatio = 0.5

% for stroke participants use SAS01V01 (Sub##V## format)
subjectID = 'SABH08';   % SAH01 for young, SAS01V01 for stroke
% To use the GUI to automatically compute the 6MWT speed, call
%   utils.extractSpeedsNMWT();
% and update the 'fast' speed below with the output value
fast = 1.1216;          % speed m/s
% if 2:1 ratio, slow = 0.5*fast; if 70%, slow = 0.7*fast
slow = fast * speedRatio;

fastLeg = 'R'; % Allowed entries: R or L; if unknown, leave and generate
% baseline only. For healthy controls, fast = dominant leg. For stroke
% participants, fast = non-paretic for session 1 and paretic for session 2.

% date threshold for copying recent files in datlogs
threshTime = datetime('now', 'InputFormat', 'dd-MMM-yyyy HH:mm:ss');

%% Generate Speed Profiles From Experimenter Input
dirProfile = fullfile( ...
    'C:\Users\Public\Documents\MATLAB\ExperimentalGUI', ...
    'profiles', 'SpinalAdaptNirsStudy', subjectID);
answer = 'Yes';                     % default to 'yes', don't check it
if contains(subjectID, 'V01')       % 2 visits detected, this is visit 1
    answer = questdlg(['Stroke Session 1: Fast leg should be ' ...
        'NON-paretic leg, which is ' fastLeg ' Is that correct?']);
elseif contains(subjectID, 'V02')   % 2 visits detected, this is visit 2
    answer = questdlg(['Stroke Session 2: Fast leg should be paretic ' ...
        'leg, which is ' fastLeg ' Is that correct?']);
end
if ~strcmp(answer, 'Yes')
    return;         % abort: fix the fast leg assignment first
end

opts.Interpreter = 'tex';
opts.Default     = 'No, I generated them already';
profileToGen = questdlg(['Regenerate profile? Confirm speed and ' ...
    'subject ID are correct in RunProtocol_SpinalAdaptBouts.m '], ...
    'RegenProfile', 'Yes', 'No, I generated them already', opts);
switch profileToGen
    case 'Yes'
        answer = questdlg(['Just to double check: now create profile ' ...
            'where the fast leg is ' fastLeg ' Is that correct?']);
        if ~strcmp(answer, 'Yes')
            return;     % abort: fix fast leg assignment
        end
        % generate baseline profiles first (fast/slow leg not decided)
        generateProfiles_SpinalAdaptBouts(slow, fast, true, dirProfile);
        % generate remaining profiles after fast leg and ramp are set
        generateProfiles_SpinalAdaptBouts(slow, fast, false, dirProfile, ...
            fastLeg, ramp2Split);
    case 'No, I generated them already'
        disp('Profile generated already. Continue with the experiments');
    otherwise
        disp('No response given, quit the script now.');
        return;
end

%% Set Up the GUI and Define Session Constants
% load audio file for announcing the end of a rest break
[audio_data, audio_fs] = audioread('TimeToWalk.mp3');
AudioTimeUp = audioplayer(audio_data, audio_fs);

% load AdaptationGUI and get the GUI figure handle
handles = guidata(AdaptationGUI);

% NOTE: these variables are needed as controller function input arguments
global profilename
global numAudioCountDown
global isCalibration

maxCon              = 13;   % maximum number of conditions
pauseTime1min       = 40;   % s; accounts for Vicon stop/start delay
pauseTime2min30     = 115;  % s; accounts for Vicon stop/start delay
ctrlSlotNirsHreflex = 14;   % GUI slot: NirsHreflexArduinoOpenLoopWithAudio
ctrlSlotOGHreflex   = 16;   % GUI slot: HreflexOGWithAudio
pauseTransferSec    = 60;   % s; allows Vicon to stop and save last trial

%% Complete Pre-Session H-Reflex Walking Calibration Trials
isCalibration = true;   % run at least once (slow & fast speeds)
while isCalibration     % repeat until experimenter selects 'No'
    isCalibration = runWalkingCalibrations(handles, dirProfile);
end

%% Run the Main SpinalAdapt Protocol Conditions
% NOTE: audio cues for "TM will start now / stop now" are approximate
% and may be difficult to improve given the GUI callback latency.
isFirstCon = true;      % is this the first condition in the session?
currCon    = 0;         % current condition index; loop runs while < maxCon
while currCon < maxCon
    if ~isFirstCon      % after first condition, ask whether to auto-advance
        nextConButton = questdlg(['Would you like to automatically ' ...
            'continue with the next condition?']);
        if strcmp(nextConButton, 'Yes')
            currCon = currCon + 1;
            if contains(subjectID, 'SABH') && ismember(currCon, [3 4])
                currCon = 5;    % skip OG trials for young adults
            end
        elseif strcmp(nextConButton, 'No')
            currCon = inputdlg(['Which condition do you want to start' ...
                ' from (1 = baseline, 5 = control train, 7 = 1st split' ...
                ' train, enter the number from the first column on the' ...
                ' data sheet)?']);
            disp(['Starting from condition #' currCon{1}]);
            currCon = str2double(currCon{1});
        else
            return;     % cancel: end the experiment
        end
    else
        isFirstCon = false;
        currCon = inputdlg(['Which condition do you want to start ' ...
            'from (1 = baseline, 5 = control train, 7 = 1st split ' ...
            'train, enter the number from the 1st col on the data ' ...
            'sheet)?']);
        disp(['Starting from condition #' currCon{1}]);
        currCon = str2double(currCon{1});
    end

    switch currCon
        case 1          % TM Baseline Fast (Tied)
            handles.popupmenu2.set('Value', ctrlSlotNirsHreflex);
            profilename = fullfile(dirProfile, 'TMBaseFast.mat');
            manualLoadProfile([], [], handles, profilename);
            answer = questdlg(['Confirm controller is Nirs, Hreflex, ' ...
                'Open loop controller with audio countdown and profile' ...
                ' is TMBaseFast']);
            if ~strcmp(answer, 'Yes')
                return;
            end
            numAudioCountDown = -1;     % include final audio countdown
            AdaptationGUI('Execute_button_Callback', ...
                handles.Execute_button, [], handles);
            % no fixed break here — proceed immediately in GUI
        case 2          % TM Baseline Slow (Tied)
            handles.popupmenu2.set('Value', ctrlSlotNirsHreflex);
            profilename = fullfile(dirProfile, 'TMBaseSlow.mat');
            manualLoadProfile([], [], handles, profilename);
            answer = questdlg(['Confirm controller is Nirs, Hreflex, ' ...
                'Open loop controller with audio countdown and profile' ...
                ' is TMBaseSlow']);
            if ~strcmp(answer, 'Yes')
                return;
            end
            numAudioCountDown = -1;
            AdaptationGUI('Execute_button_Callback', ...
                handles.Execute_button, [], handles);
            % no fixed break here — proceed immediately in GUI
        case 3          % OG Baseline Fast
            handles.popupmenu2.set('Value', ctrlSlotOGHreflex);
            profilename = fullfile(dirProfile, 'OGBaseFast.mat');
            manualLoadProfile([], [], handles, profilename);
            answer = questdlg(['Confirm controller is ' ...
                'HreflexOGWithAudio and speed profile is fast']);
            if ~strcmp(answer, 'Yes')
                return;
            end
            AdaptationGUI('Execute_button_Callback', ...
                handles.Execute_button, [], handles);
            % no fixed break here — proceed immediately in GUI
        case 4          % OG Baseline Slow
            handles.popupmenu2.set('Value', ctrlSlotOGHreflex);
            profilename = fullfile(dirProfile, 'OGBaseSlow.mat');
            manualLoadProfile([], [], handles, profilename);
            answer = questdlg(['Confirm controller is ' ...
                'HreflexOGWithAudio and speed profile is slow']);
            if ~strcmp(answer, 'Yes')
                return;
            end
            AdaptationGUI('Execute_button_Callback', ...
                handles.Execute_button, [], handles);
            % no fixed break here — proceed immediately in GUI
        case {5, 6}     % Control Train Bouts (Tied)
            handles.popupmenu2.set('Value', ctrlSlotNirsHreflex);
            if currCon == 5
                profilename = fullfile(dirProfile, 'CtrlTrain_1.mat');
            elseif currCon == 6
                profilename = fullfile(dirProfile, 'CtrlTrain_2.mat');
            end
            manualLoadProfile([], [], handles, profilename);
            answer = questdlg(['Confirm the trial information: Nirs ' ...
                'Train Control?']);
            if ~strcmp(answer, 'Yes')
                return;
            end
            % numAudioCountDown = []; % If errors out, comment this out
            AdaptationGUI('Execute_button_Callback', ...
                handles.Execute_button, [], handles);
            pause(pauseTime2min30);     % break for at least 2.5 minutes
            play(AudioTimeUp);
        case {7, 8, 9, 10, 11}  % Split Train Bouts
            handles.popupmenu2.set('Value', ctrlSlotNirsHreflex);
            profilename = fullfile(dirProfile, ...
                ['PreSplitTrain_' num2str(currCon - 6) '.mat']);
            manualLoadProfile([], [], handles, profilename);
            answer = questdlg(['Confirm the trial information: Nirs ' ...
                'Split Train?']);
            if ~strcmp(answer, 'Yes')
                return;
            end
            AdaptationGUI('Execute_button_Callback', ...
                handles.Execute_button, [], handles);
            pause(pauseTime2min30);     % break for at least 2.5 minutes
            play(AudioTimeUp);
        case 12         % Post-Train with Negative Short Split
            handles.popupmenu2.set('Value', ctrlSlotNirsHreflex);
            profilename = fullfile(dirProfile, 'Post1WtNegShort.mat');
            manualLoadProfile([], [], handles, profilename);
            answer = questdlg(['Confirm the trial information: post 1 ' ...
                '(50 tied fast, 30 negshort, 100 tied fast)?']);
            if ~strcmp(answer, 'Yes')
                return;
            end
            numAudioCountDown = -1;     % [50 80 -1]
            AdaptationGUI('Execute_button_Callback', ...
                handles.Execute_button, [], handles);
            pause(pauseTime2min30);     % break for at least 2.5 minutes
            play(AudioTimeUp);
        case 13         % Final Post-Train (Tied)
            handles.popupmenu2.set('Value', ctrlSlotNirsHreflex);
            profilename = fullfile(dirProfile, 'Post2.mat');
            manualLoadProfile([], [], handles, profilename);
            answer = questdlg(['Confirm trial and profile is Post 2 ' ...
                '(tied for 200)']);
            if ~strcmp(answer, 'Yes')
                return;
            end
            numAudioCountDown = -1;
            AdaptationGUI('Execute_button_Callback', ...
                handles.Execute_button, [], handles);
    end
end

%% Complete End-of-Session H-Reflex Walking Calibration Trials
isCalibration = runWalkingCalibrations(handles, dirProfile);

%% Transfer Session Data to Server
% pauseTransferSec allows Vicon Nexus to stop and save the last C3D file
pause(pauseTransferSec);
tic;
transferData_SpinalAdaptBouts(subjectID, threshTime);
toc;

%% Run Reconstruct and Label Pipeline and Fill Marker Gaps
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% NOTE %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% ONLY RUN THIS BLOCK ON THE LAB PC1 IF THERE IS SUFFICIENT TIME BEFORE
% THE NEXT EXPERIMENTER NEEDS THE LAB SPACE
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% TODO: update path below for participants with stroke (two visits)
tic;
dirSrvrData = fullfile('W:\SpinalAdaptStudy\Data', subjectID, 'Vicon');
dataMotion.processAndFillMarkerGapsSession(dirSrvrData);
toc;
