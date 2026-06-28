%RUNPROTOCOL_SPINALADAPTBOUTS Automate the SpinalAdapt experimental session.
%
%   TEMPLATE — Updated with new SpinalAdapt protocol structure:
%   16 conditions (2 TM + 2 OG baselines, 1 control bouts, 8 split
%   bouts trials, 1 control bouts repeat, 2 post-adapt). Verify all
%   conditions and the subjectID skip logic before data collection.
%   See History-PilotStudy2/ for the Pilot Study 2 original.
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
speedProportion = 0.7;  % slow / fast speed ratio; 0.7 since July 2024

% for stroke participants use SAS01V01 (Sub##V## format)
subjectID = 'SABH08';   % SABH## for young, SAS##V## for stroke

fastLeg = 'R'; % 'R' or 'L'; for healthy: dominant leg; for stroke:
% non-paretic (session 1) or paretic (session 2).

% Compute fastSpeed from the N-Minute Walk Test (NMWT): opens a dialog
% to collect raw walk test measurements and returns the participant's
% comfortable overground walking speed (m/s), used as the fast belt speed.
fastSpeed = utils.extractSpeedsNMWT();
slowSpeed = fastSpeed * speedProportion;

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
        % generate baseline profiles first (fast leg not yet confirmed)
        generateProfiles_SpinalAdaptBouts(slowSpeed, fastSpeed, ...
            true, dirProfile);
        % generate training profiles after fast leg is confirmed
        generateProfiles_SpinalAdaptBouts(slowSpeed, fastSpeed, ...
            false, dirProfile, fastLeg);
    case 'No, I generated them already'
        disp('Profile generated already. Continue with the experiments');
    otherwise
        disp('No response given, quit the script now.');
        return;
end

%% Set Up the GUI and Define Session Constants
[audio_data, audio_fs] = audioread('TimeToWalk.mp3');
AudioTimeUp = audioplayer(audio_data, audio_fs);

handles = guidata(AdaptationGUI);

% NOTE: these variables are needed as controller function input arguments
global profilename
global numAudioCountDown
global isCalibration

maxCon              = 16;   % maximum number of conditions
pauseTime1min       = 40;   % s; accounts for Vicon stop/start delay
pauseTime2min30     = 115;  % s; accounts for Vicon stop/start delay
ctrlSlotNirsHreflex = 14;   % GUI slot: NirsHreflexArduinoOpenLoopWithAudio
ctrlSlotOGHreflex   = 16;   % GUI slot: HreflexOGWithAudio
pauseTransferSec    = 60;   % s; allows Vicon to stop and save last trial

numAudioCountDown = -1;     % default: include final audio countdown

%% Complete Pre-Session H-Reflex Walking Calibration Trials
isCalibration = true;   % run at least once (slow & fast speeds)
while isCalibration     % repeat until experimenter selects 'No'
    isCalibration = runWalkingCalibrations(handles, dirProfile);
end

%% Run the Main SpinalAdapt Protocol Conditions
% NOTE: audio cues for "TM will start / stop now" are approximate and
% may be difficult to improve given the GUI callback latency.
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
                ' from (1 = TM baseline fast, 5 = control bouts,' ...
                ' 6 = 1st split trial, enter the number from the' ...
                ' 1st col on the data sheet)?']);
            disp(['Starting from condition #' currCon{1}]);
            currCon = str2double(currCon{1});
        else
            return;     % cancel: end the experiment
        end
    else
        isFirstCon = false;
        currCon = inputdlg(['Which condition do you want to start ' ...
            'from (1 = TM baseline fast, 5 = control bouts, ' ...
            '6 = 1st split trial, enter the number from the ' ...
            '1st col on the data sheet)?']);
        disp(['Starting from condition #' currCon{1}]);
        currCon = str2double(currCon{1});
    end

    switch currCon
        case 1          % TM Baseline Fast (Tied)
            handles.popupmenu2.set('Value', ctrlSlotNirsHreflex);
            profilename = fullfile(dirProfile, 'TMBaselineFast.mat');
            manualLoadProfile([], [], handles, profilename);
            answer = questdlg(['Confirm controller is Nirs, Hreflex, ' ...
                'Open loop with audio countdown and profile is ' ...
                'TMBaselineFast']);
            if ~strcmp(answer, 'Yes')
                return;
            end
            numAudioCountDown = -1;
            AdaptationGUI('Execute_button_Callback', ...
                handles.Execute_button, [], handles);
            % no fixed break here — proceed immediately in GUI
        case 2          % TM Baseline Slow (Tied)
            handles.popupmenu2.set('Value', ctrlSlotNirsHreflex);
            profilename = fullfile(dirProfile, 'TMBaselineSlow.mat');
            manualLoadProfile([], [], handles, profilename);
            answer = questdlg(['Confirm controller is Nirs, Hreflex, ' ...
                'Open loop with audio countdown and profile is ' ...
                'TMBaselineSlow']);
            if ~strcmp(answer, 'Yes')
                return;
            end
            numAudioCountDown = -1;
            AdaptationGUI('Execute_button_Callback', ...
                handles.Execute_button, [], handles);
            % no fixed break here — proceed immediately in GUI
        case 3          % OG Baseline Fast (optional; skipped for SABH)
            handles.popupmenu2.set('Value', ctrlSlotOGHreflex);
            profilename = fullfile(dirProfile, 'OGBaselineFast.mat');
            manualLoadProfile([], [], handles, profilename);
            answer = questdlg(['Confirm controller is ' ...
                'HreflexOGWithAudio and speed profile is fast']);
            if ~strcmp(answer, 'Yes')
                return;
            end
            AdaptationGUI('Execute_button_Callback', ...
                handles.Execute_button, [], handles);
            % no fixed break here — proceed immediately in GUI
        case 4          % OG Baseline Slow (optional; skipped for SABH)
            handles.popupmenu2.set('Value', ctrlSlotOGHreflex);
            profilename = fullfile(dirProfile, 'OGBaselineSlow.mat');
            manualLoadProfile([], [], handles, profilename);
            answer = questdlg(['Confirm controller is ' ...
                'HreflexOGWithAudio and speed profile is slow']);
            if ~strcmp(answer, 'Yes')
                return;
            end
            AdaptationGUI('Execute_button_Callback', ...
                handles.Execute_button, [], handles);
            % no fixed break here — proceed immediately in GUI
        case {5, 14}    % Control Bouts (Tied; before and after split)
            handles.popupmenu2.set('Value', ctrlSlotNirsHreflex);
            profilename = fullfile(dirProfile, 'CtrlBouts.mat');
            manualLoadProfile([], [], handles, profilename);
            answer = questdlg(['Confirm controller is Nirs, Hreflex, ' ...
                'Open loop with audio and profile is CtrlBouts']);
            if ~strcmp(answer, 'Yes')
                return;
            end
            AdaptationGUI('Execute_button_Callback', ...
                handles.Execute_button, [], handles);
            pause(pauseTime2min30);     % break for at least 2.5 minutes
            play(AudioTimeUp);
        case {6, 7, 8, 9, 10, 11, 12, 13}  % Split Bouts Trials 1-8
            handles.popupmenu2.set('Value', ctrlSlotNirsHreflex);
            profilename = fullfile(dirProfile, 'SplitBouts.mat');
            manualLoadProfile([], [], handles, profilename);
            answer = questdlg(['Confirm controller is Nirs, Hreflex, ' ...
                'Open loop with audio and profile is SplitBouts']);
            if ~strcmp(answer, 'Yes')
                return;
            end
            AdaptationGUI('Execute_button_Callback', ...
                handles.Execute_button, [], handles);
            pause(pauseTime2min30);     % break for at least 2.5 minutes
            play(AudioTimeUp);
        case {15, 16}   % Post-Adaptation Trials 1 and 2 (Tied Fast)
            handles.popupmenu2.set('Value', ctrlSlotNirsHreflex);
            profilename = fullfile(dirProfile, 'PostAdapt.mat');
            manualLoadProfile([], [], handles, profilename);
            answer = questdlg(['Confirm controller is Nirs, Hreflex, ' ...
                'Open loop with audio and profile is PostAdapt']);
            if ~strcmp(answer, 'Yes')
                return;
            end
            numAudioCountDown = -1;
            AdaptationGUI('Execute_button_Callback', ...
                handles.Execute_button, [], handles);
            if currCon < maxCon     % brief break unless final condition
                pause(pauseTime1min);
                play(AudioTimeUp);
            end
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
