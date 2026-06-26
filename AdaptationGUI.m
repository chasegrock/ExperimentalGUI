function varargout = AdaptationGUI(varargin)
%ADAPTATIONGUI Launch the treadmill experiment control GUI.
%
%   Initializes global experiment state, audio players, and keyboard
%   polling, then lets the experimenter pick a speed profile and a
%   controller and run a trial. The companion layout is defined in
%   AdaptationGUI.fig.
%
% Inputs:
%   varargin - GUIDE callback-dispatch arguments; either a property/
%              value list for the figure or a callback name followed by
%              its arguments (see GUIDATA, GUIHANDLES)
%
% Outputs:
%   varargout - figure handle when called with an output argument, or
%               the selected callback's return values
%
% Toolbox Dependencies:
%   None
%
% See also GUIDE, GUIDATA, GUIHANDLES.

% Last Modified by GUIDE v2.5 12-Mar-2020 10:14:25

% Begin initialization code - DO NOT EDIT
gui_Singleton = 1;
gui_State = struct('gui_Name',       mfilename(), ...
    'gui_Singleton',  gui_Singleton, ...
    'gui_OpeningFcn', @AdaptationGUI_OpeningFcn, ...
    'gui_OutputFcn',  @AdaptationGUI_OutputFcn, ...
    'gui_LayoutFcn',  [] , ...
    'gui_Callback',   []);
if nargin && ischar(varargin{1})
    %     gui_State.gui_Callback = str2funedc(varargin{1});
    gui_State.gui_Callback = str2func(varargin{1});
end

if nargout
    [varargout{1:nargout}] = gui_mainfcn(gui_State, varargin{:});
else
    gui_mainfcn(gui_State, varargin{:});
end
% End initialization code - DO NOT EDIT

% ============================================================
% ================ Initialization & Output ===================
% ============================================================

% --- Executes just before AdaptationGUI is made visible.
function AdaptationGUI_OpeningFcn(hObject, eventdata, handles, varargin)
%ADAPTATIONGUI_OPENINGFCN Initialize GUI state before display.
%
%   Sets the global control flags, loads audio assets, and initializes
%   the counters used by the perception-task keyboard logger.
%
% Inputs:
%   hObject - handle to the figure
%   eventdata - reserved for a future MATLAB version
%   handles - structure with handles and user data (see GUIDATA)
%   varargin - command-line arguments to AdaptationGUI (see VARARGIN)
%
% Toolbox Dependencies:
%   None

% Choose default command line output for AdaptationGUI
handles.output = hObject;
movegui(hObject, 'northwest'); % tell the GUI where to position on open

% Needed variables
global STOP
STOP = false;
global PAUSE
PAUSE = false;
global Functionname
Functionname = 1;
global InclineAngle
InclineAngle = 0; % default value, use treadmill with no incline
global memory
memory = 0;
global addLog
addLog.keypress = cell(1e4, 2);
global counter;
counter = 0;
global enableMemory
enableMemory = false;
global firstPress
firstPress = false;
global feedbackFlag
feedbackFlag = 0;
global tone
load(fullfile('assets', 'click.mat'))
tone = y;
global lastKeyPress
lastKeyPress = now;
global keyWasReleased
keyWasReleased = true;

% Added by Marcela 10/04/2019
global rclicksound
global lclicksound
global rFrequency
global lFrequency
[rclicksound, rFrequency] = ...
    audioread(fullfile('assets', 'RightClick.mp3'));
[lclicksound, lFrequency] = ...
    audioread(fullfile('assets', 'LeftClick.mp3'));
global fastbeep
[fastbeeps, fastbeepf] = audioread(fullfile('assets', 'FastBeep.mp3'));
fastbeep = audioplayer(fastbeeps, fastbeepf);

% Added by Shuqi 01/19/2022
global numAudioCountDown
numAudioCountDown = -1;
global isCalibration
isCalibration = false; % default false (not a calibration trial)

% Update handles structure
guidata(hObject, handles);

% UIWAIT makes AdaptationGUI wait for user response (see UIRESUME)
% uiwait(handles.figure1);

% function flashbutton(handles)
% %flash the profile browse button
% % disp('flashing...');
% set(handles.profilebrowse,'BackgroundColor',[0,0,1]);
% pause(0.1)
% set(handles.profilebrowse,'BackgroundColor',[1,1,1]);
% % guidata(hObject, handles);

% --- Outputs from this function are returned to the command line.
function varargout = AdaptationGUI_OutputFcn(hObject, eventdata, handles)
%ADAPTATIONGUI_OUTPUTFCN Return GUI outputs and set self-paced defaults.
%
%   Initializes the self-selected pace variables before any controller
%   can query them, then returns the default command-line output.
%
% Inputs:
%   hObject - handle to the figure
%   eventdata - reserved for a future MATLAB version
%   handles - structure with handles and user data (see GUIDATA)
%
% Outputs:
%   varargout - cell array whose first element is the figure handle
%
% Toolbox Dependencies:
%   None

% startup function
% clc
% global TrialNum
%
% TrialNum = 0;
global SSspeed
global SSstdev

% set up variables for self selected pace before they are called
% anywhere else
SSspeed = 1:20:800;
SSstdev = 0;

% global flasher
% flasher = timer;
% flasher.TimerFcn = @(myTimerObj, thisEvent)flashbutton(handles);
% flasher.Period = 0.2;
% flasher.TasksToExecute = 500;
% flasher.ExecutionMode = 'fixedRate';
% start(flasher);
% Get default command line output from handles structure
varargout{1} = handles.output;
guidata(hObject, handles);

% ============================================================
% =================== Profile Selection ======================
% ============================================================

function SaveAs_textbox_Callback(hObject, ~, handles)
% Hints: get(hObject,'String') returns contents of SaveAs_textbox as text
%        str2double(get(hObject,'String')) returns contents as a double

% --- Executes during object creation, after setting all properties.
function SaveAs_textbox_CreateFcn(hObject, eventdata, handles)
% Hint: edit controls usually have a white background on Windows.
%       See ISPC and COMPUTER.
if ispc && isequal(get(hObject, 'BackgroundColor'), ...
        get(0, 'defaultUicontrolBackgroundColor'))
    set(hObject, 'BackgroundColor', 'White');
end

%{
% --- Executes on selection change in SelectProfile_menu.
function SelectProfile_menu_Callback(hObject, eventdata, handles)
% hObject    handle to SelectProfile_menu (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    structure with handles and user data (see GUIDATA)

%this callback opens the speed profile selected, makes a plot so the user
%can see what they will be telling the various devices to do
% global profilename
%
% set(handles.Status_textbox,'String','Plotting');
% set(handles.Status_textbox,'BackgroundColor','Yellow');
% pause(0.25);
%
% value = get(hObject,'Value');
% profilename = get(hObject,'String');
% profilename = profilename{value};
%
% load(profilename);
%
% t = [0:length(velL)-1];
%
% set(handles.profileaxes,'NextPlot','replace')
% plot(handles.profileaxes,t,velL,'b',t,velR,'r','LineWidth',2);
% ylim([min([velL velR])-1,max([velL velR])+1]);
% ylabel('Speed (m/s)');
% xlabel('Stride Count');
% legend('Left Foot','Right Foot');
% set(handles.profileaxes,'NextPlot','add')
%
% set(handles.Status_textbox,'String','Ready');
% set(handles.Status_textbox,'BackgroundColor','Green');
%
% guidata(hObject, handles);
% Hints: contents = cellstr(get(hObject,'String')) returns SelectProfile_menu contents as cell array
%        contents{get(hObject,'Value')} returns selected item from SelectProfile_menu
%}

% --- Executes during object creation, after setting all properties.
function SelectProfile_menu_CreateFcn(hObject, eventdata, handles)
% Hint: popupmenu controls usually have a white background on Windows.
%       See ISPC and COMPUTER.
if ispc && isequal(get(hObject, 'BackgroundColor'), ...
        get(0, 'defaultUicontrolBackgroundColor'))
    set(hObject, 'BackgroundColor', 'White');
end

% ============================================================
% ================= Execute / Run Control ====================
% ============================================================

% --- Executes on button press in Execute_button.
function Execute_button_Callback(hObject, eventdata, handles)
%EXECUTE_BUTTON_CALLBACK Load the selected profile and run a controller.
%
%   Reads the controller choice and profile, optionally starts Nexus and
%   EMGWorks capture, dispatches to the chosen controller, then stops
%   capture and restores the Ready status.
%
% Inputs:
%   hObject - handle to Execute_button (see GCBO)
%   eventdata - reserved for a future MATLAB version
%   handles - structure with handles and user data (see GUIDATA)
%
% Toolbox Dependencies:
%   Instrument Control Toolbox (serial)

% This callback runs when the Execute button is pressed
global profilename
global STOP
global PAUSE
global Functionname
global allowedKeys
% CARLY MARCELA
global RFBClicker
global LFBClicker
% Shuqi
global playClickerSound

% default true (for perception studies). If running N-Back where click
% should not follow sound, set to false.
playClickerSound = true;

% check which function to call when Execute is pressed.
fnames = get(handles.popupmenu2, 'String');
selection = get(handles.popupmenu2, 'Value');
Functionname = fnames{selection};
% whos
STOP = false;
PAUSE = false;
global feedbackFlag
feedbackFlag = handles.feedbackBox.Value;

set(handles.Status_textbox, 'String', 'Loading...');
set(handles.Status_textbox, 'BackgroundColor', 'Yellow');

load(profilename)
forceThreshold = 30;
set(handles.Status_textbox, 'String', 'Busy...');
set(handles.Status_textbox, 'BackgroundColor', 'Yellow');

%Start capture Nexus & EMGWorks?
% XServer=actxserver('WScript.Shell');
% import java.awt.Robot;
% import java.awt.event.*;
% robot = Robot;
startedEMG_flag = false; % turned on by Dulce 3/12/2020
if get(handles.EMGWorks_checkbox, 'Value') == 1
    startedEMG_flag = true;

    if get(handles.EMGWorks_checkbox, 'Value') == 1
        % added by DMMO 3/13/2020
        button = questdlg( ...
            'Please confirm that EMGworks is in trigger mode');
        if ~strcmp(button, 'Yes')
            return; % Abort starting of treadmill
        end
    else
        %           pause(3);
    end

    disp(['Opening EMGWorks Port ' datestr(datetime('now'))])
    ss = serial('COM14');
    fopen(ss);
    pause(0.1);
    fclose(ss);
    disp(['Done Opening EMGWorks Port ' datestr(datetime('now'))])

    %     %Do something
    %     startedEMG_flag=true;
    %     XServer.AppActivate('EMGworks 4.0.13 - Workflow Environment Pro'); %Get EMG in front
    %     pause(.3)
    %     XServer.SendKeys('^a'); %Start acquisition (it should already be in the acquisition phase of the workflow
    %     XServer.AppActivate('AdaptationGUI'); %This window
end
startedNexus_flag = false;
if get(handles.Nexus_checkbox, 'Value') == 1

    startedNexus_flag = true;

    %**************wait for keyboard press before starting nexus and
    %everything else
    %     pause;
    %
    %     Solution 1: get a click on start button. Only works if Nexus is maximized
    %     XServer.AppActivate('Vicon Nexus 1.8.5');
    %     pause(.3)
    %      robot.mouseMove(1700, 685); %Coordinates in screen when all tabs are minimized on Nexus capture panel
    %      robot.mousePress(InputEvent.BUTTON1_MASK);%Left-button, right= 3
    %      pause(.1)
    %      robot.mouseRelease(InputEvent.BUTTON1_MASK);
    %      XServer.AppActivate('AdaptationGUI');

    % %**************New method triggering Nexus with UDP Packet
    %     if pathflag == 1
    %     [dontcare,sessionpath] = uigetfile('*.*','Please select a trial in the database being used:');
    %     else
    %     end
    %     keyboard
    %%
    % %         nexuspath = 'C:\Users\Public\Documents\Vicon\Nexus Sample Data\WDA8_22\Will\Session 7\';
    %         startmsg = ['<?xml version="1.0" encoding="UTF-8" standalone="no" ?><CaptureStart><Name VALUE="Trial0' num2str(TrialNum,2) '"/><Notes VALUE=""/><Description VALUE=""/><DatabasePath VALUE="' sessionpath '\"/><Delay VALUE="0"/><PacketID VALUE="' num2str(TrialNum) '"/></CaptureStart>'];
    %         startmsg = native2unicode(startmsg,'UTF-8');
    %         myudp = dsp.UDPSender('RemoteIPAddress','255.255.255.255','RemoteIPPort',30,'LocalIPPortSource','Property','LocalIPPort',31);
    %         %send udp start packet
    %         step(myudp,int8(startmsg));
    %         pathflag = 0;
    %%
    %
    %
    %      %current method of triggering, matlab sends command via serial port.
    %      %MOnitor in Nexus watched for pulse to toggle start/stop.
    %      %use orange wire out of serial port to pin 64 on AD board

    disp(['Opening Vicon Port ' datestr(datetime('now'))])
    s = serial('COM1'); % vicon
    fopen(s);
    pause(0.1);
    fclose(s); % pulses the voltage high then low, toggling capture in Nexus
    disp(['Done Opening Vicon Port ' datestr(datetime('now'))])
    %
    if get(handles.waitForNexusChkBox, 'Value') == 1 && ...
            get(handles.EMGWorks_checkbox, 'Value') == 0
        %            if get(handles.waitForNexusChkBox,'Value')==1
        button = questdlg( ...
            'Please confirm that Nexus has started capture', ...
            'Nexus confirm dialog');
        if ~strcmp(button, 'Yes')
            return; % Abort starting of treadmill
        end
    elseif get(handles.waitForNexusChkBox, 'Value') == 1 && ...
            get(handles.EMGWorks_checkbox, 'Value') == 1
        % added by DMMO 3/13/2020
        button = questdlg( ...
            'Please confirm that Nexus & EMGworks has started capture', ...
            'Nexus confirm dialog');
        if ~strcmp(button, 'Yes') % added by DMMO 3/13/2020
            return; % Abort starting of treadmill
        end
    else
        %           pause(3);
    end

    % Deleting old plots:
    ll = findobj(handles.profileaxes, 'Type', 'Line');
    delete(ll(1:end-2));
    ll = findobj(handles.profileaxes, 'Type', 'AnimatedLine');
    delete(ll);

    % Give some time between Nexus start and treadmill start
    pause(0.1)

end

% switch between the available functions to call
aux = regexp(profilename, '\');
shortName = profilename(aux(end)+1:end-4);
switch(selection)

    case 1 % control speed with steps
        [RTOTime, LTOTime, RHSTime, LHSTime, commSendTime, ...
            commSendFrame] = controlSpeedWithSteps_edit1( ...
            round(velL*1000), round(velR*1000), forceThreshold, ...
            shortName);

    case 2
        mode = 1; % Signed
        allowedKeys = {'numpad4', 'numpad6', 'leftarrow', ...
            'rightarrow', 'pagedown', 'pageup'};
        [RTOTime, LTOTime, RHSTime, LHSTime, commSendTime, ...
            commSendFrame] = controlSpeedWithSteps_selfSelect( ...
            round(velL*1000), round(velR*1000), forceThreshold, ...
            shortName, mode);

    case 3
        mode = 0; % Unsigned
        allowedKeys = {'numpad8', 'numpad2', 'uparrow', 'downarrow'};
        if ~exist('signList', 'var')
            signList = [];
            %disp('bad')
        end
        %signList
        [RTOTime, LTOTime, RHSTime, LHSTime, commSendTime, ...
            commSendFrame] = controlSpeedWithSteps_selfSelect( ...
            round(velL*1000), round(velR*1000), forceThreshold, ...
            shortName, mode, signList);

    case 4
        mode = 4; % Closed-loop control
        % Requires two global function handles to be defined:
        [calibFilename, ~, ~] = uigetfile('*.*');
        load(calibFilename)
        if ~exist('paramComputeFunc', 'var') || ...
                ~exist('paramCalibFunc', 'var') || ...
                ~isa(paramComputeFunc, 'function_handle') || ...
                ~isa(paramCalibFunc, 'function_handle')
            error('paramComputeFunc or paramCalibFunc are not defined.')
        end
        [RTOTime, LTOTime, RHSTime, LHSTime, commSendTime, ...
            commSendFrame] = controlSpeedWithSteps_selfSelect( ...
            round(velL*1000), round(velR*1000), forceThreshold, ...
            shortName, mode, [], paramComputeFunc, paramCalibFunc);

    case 5 % self selected speed
        disp('running self selected speed');
        % be sure to have selected the right profile!!!!!
        [RTOTime, LTOTime, RHSTime, LHSTime, commSendTime, ...
            commSendFrame, ssrecord] = SelfSelectedSpeed( ...
            round(velL*1000), round(velR*1000), forceThreshold);
        ssrecord(1) = []; % delete useless zero at beginning
        disp(['The mean self selected seed is: ' ...
            num2str(mean(ssrecord, 'omitnan'))]);
        disp(['The stdev of speeds is: ' ...
            num2str(std(ssrecord, 'omitnan'))]);

    case 6
        newline = sprintf('\n');
        set(handles.Status_textbox, 'FontSize', 10);
        set(handles.Status_textbox, 'String', ['Busy...', newline, ...
            'Press 8 to +', newline, 'Press 2 to -', newline, ...
            'Press "f" to perturb fast', newline, ...
            'Press "s" to perturb slow', newline, ...
            'Press "b" to return to profile']);
        ssout = SelfSelectedSpeed_NumPad(velL*1000, velR*1000, 30);
        set(handles.Status_textbox, 'FontSize', 20);
        listofss = ssout;
        listofss(listofss == 0) = [];
        listofss(listofss == 500) = [];
        listofss(listofss == 1500) = [];
        listofss(listofss == 1250) = [];
        disp('Selected Speeds: ');
        listofss = unique(listofss)
        disp('mean selected speed: ');
        mean(listofss)./1000

    case 7 % Perceptual trial: ends on click; length set by strides
        mode = 1;
        allowedKeys = {'numpad4', 'numpad6', 'leftarrow', ...
            'rightarrow', 'pagedown', 'pageup'};
        [RTOTime, LTOTime, RHSTime, LHSTime, commSendTime, ...
            commSendFrame] = ...
            controlSpeedWithSteps_selfSelect_OneClick( ...
            round(velL*1000), round(velR*1000), forceThreshold, ...
            shortName, mode);

    case 8 % audio feedback to participants during overground walking
        disp('Overground audio speed feedback');
        mode = 1;
        % added by DMMO 3/13/2020
        audioFbBtn = questdlg( ...
            'Should audio feedback on speed be provided?');
        % Replace overground audio controller with the new one developed
        % by Nate to have better stride counting using the state machine
        [RTOTime, LTOTime, RHSTime, LHSTime, commSendTime, ...
            commSendFrame] = HreflexOGWithAudio(round(velL*1000), ...
            round(velR*1000), forceThreshold, shortName, mode, ...
            [], [], [], strcmp(audioFbBtn, 'Yes'), false);
        % last arg = hreflex present = false (Hreflex OG has its own
        % controller)
        %Previous controller code below (obsolte)
        %be sure to have selected the right profile!!!!!
        %         [RTOTime, LTOTime, RHSTime, LHSTime, commSendTime, commSendFrame] = Speed_audioFeedback(round(velL*1000), round(velR*1000), forceThreshold, shortName,mode,[],[],[],strcmp(audioFbBtn,'Yes'));
        %         ssrecord = [];%delete useless zero at beginning
        %         disp(['The mean self selected seed is: ' num2str(nanmean(ssrecord))]);
        %         disp(['The stdev of speeds is: ' num2str(nanstd(ssrecord))]);
        % % %         ssrecord

    case 9
        mode = 1;
        allowedKeys = {'numpad4', 'numpad6', 'leftarrow', ...
            'rightarrow', 'pagedown', 'pageup'};
        %         [RTOTime, LTOTime, RHSTime, LHSTime, commSendTime, commSendFrame] = controlSpeedWithSteps_selfSelect_OneClick_Adap(round(velL*1000), round(velR*1000), forceThreshold, shortName,mode); %
        % Now the perceptual trial is controlled by time, a response to the
        % perceptual task ends the task, we do not ramp down after the
        % task, save forces in datlog
        % 06/20/24
        [RTOTime, LTOTime, RHSTime, LHSTime, commSendTime, ...
            commSendFrame] = controlSpeedWithSteps_PercAdap( ...
            round(velL*1000), round(velR*1000), forceThreshold, ...
            shortName, mode);

    case 10
        disp('AutomaticityAssessmentProtocol');
        mode = 1;
        currTrial = inputdlg( ...
            'What is the current_iteration (o=familiarization): ');
        [RTOTime, LTOTime, RHSTime, LHSTime, commSendTime, ...
            commSendFrame] = NirsAutomaticityAssessment( ...
            round(velL*1000), round(velR*1000), shortName, mode, ...
            [], [], [], str2num(currTrial{1}));

    case 11
        % Added by Shuqi 1/19/2022, default [-1], only count down at
        % TM start and end
        global numAudioCountDown
        [RTOTime, LTOTime, RHSTime, LHSTime, commSendTime, ...
            commSendFrame] = ...
            controlSpeedWithSteps_edit1_AudioCountDown( ...
            round(velL*1000), round(velR*1000), forceThreshold, ...
            shortName, numAudioCountDown);

    case 12
        [RatioR, RatioL, RatiomeanR, RatiomeanL, Rstd, Lstd, ...
            alphaR, alphaL, alphaRmean, alphaLmean, alphaRstd, ...
            alphaLstd, betameanR, betameanL, Rsci, Lsci, XmeanR, ...
            XmeanL, RatioXmeanR, RatioXmeanL, RsciX, LsciX] = ...
            Dulce_grad_betarev2(round(velL*1000), ...
            round(velR*1000), forceThreshold);

        disp('the mean ratio for the R leg is:');
        disp(RatiomeanR);
        disp('the mean ratio  for the L leg is:');
        disp(RatiomeanL);
        disp('the stdev ratio for the R leg is:');
        disp(Rstd);
        disp('the stdev ratio for the L leg is:');
        disp(Lstd);
        disp('the mean of RHS');
        disp(alphaRmean);
        disp('the mean of LHS');
        disp(alphaLmean);
        disp('the stdev  R leg is:');
        disp(alphaRstd);
        disp('the stdev e L leg is:');
        disp(alphaLstd);
        disp('X mean R leg')
        disp(XmeanR)
        disp('X mean L leg')
        disp(XmeanL)
        disp('Ratio R leg with X@LHS')
        disp(RatioXmeanR')
        disp('Ratio L leg with X@RHS')
        disp(RatioXmeanL)
        disp('R scale with X')
        disp(RsciX)
        disp('L scale with X')
        disp(LsciX)

    case 13
        disp('NBackOG Protocol');
        mode = 1;
        allowedKeys = {'numpad4', 'numpad6', 'leftarrow', ...
            'rightarrow', 'pagedown', 'pageup'};
        playClickerSound = false;
        %         trialOptions = {'Standing Familarization 0back (up to 3 times)','Standing Familarization 1back (up to 3 times)',...
        %             'Standing Familarization 2back (up to 3 times)','Full Familarization 0back (only 1 repeat)',...
        %             'Full Familarization 1back (only 1 repeat)','Full Familarization 2back (only 1 repeat)',...
        %             'Trial 1','Trial 2','Trial 3','Trial 4','Trial 5','Trial 6'};
        trialOptions = {'Full Familarization 0back (up to 3 repeats)', ...
            'Full Familarization 1back (up to 3 repeats)', ...
            'Full Familarization 2back (up to 3 repeats)', ...
            'Trial 1', 'Trial 2', 'Trial 3', 'Trial 4', 'Trial 5', ...
            'Trial 6'};
        [currTrial, ~] = listdlg('PromptString', 'What trial is this:', ...
            'ListString', trialOptions, 'SelectionMode', 'single', ...
            'ListSize', [300, 150]);
        if isempty(currTrial)
            error('Invalid selection. Try again.')
        else
            confirmTrial = questdlg(sprintf( ...
                'You selected: %s.\n Is this correct?', ...
                trialOptions{currTrial}));
            if ~strcmp(confirmTrial, 'Yes')
                error('Invalid selection. Try again.') % Abort the trial
            end
        end
        % offset the input by 2 so the familiarization is -1 and 0
        [RTOTime, LTOTime, RHSTime, LHSTime, commSendTime, ...
            commSendFrame] = OGNBackTask(round(velL*1000), ...
            round(velR*1000), forceThreshold, shortName, mode, ...
            [], [], [], trialOptions{currTrial});

    case 14 % open-loop NIRS logging; Arduino stim every 10 strides
        % (stim cadence set inside the controller); optionally has timed
        % rest breaks; event timing auto-generated from velL and velR.
        disp('Short Split Train Nirs Protocol')
        global numAudioCountDown % default [-1] (Shuqi 1/19/2022)
        global isCalibration % default false, not calibration (SL 5/7/2024)
        if exist('stimL', 'var') && exist('stimR', 'var')
            [RTOTime, LTOTime, RHSTime, LHSTime, commSendTime, ...
                commSendFrame] = ...
                NirsHreflexArduinoOpenLoopWithAudio( ...
                round(velL*1000), round(velR*1000), forceThreshold, ...
                shortName, numAudioCountDown, isCalibration, true, ...
                true, stimL, stimR);
        else
            [RTOTime, LTOTime, RHSTime, LHSTime, commSendTime, ...
                commSendFrame] = ...
                NirsHreflexArduinoOpenLoopWithAudio( ...
                round(velL*1000), round(velR*1000), forceThreshold, ...
                shortName, numAudioCountDown, isCalibration, true, true);
        end

    case 15 % Perceptual trial: ends on click; length set by time
        mode = 1;
        allowedKeys = {'numpad4', 'numpad6', 'leftarrow', ...
            'rightarrow', 'pagedown', 'pageup'};
        [RTOTime, LTOTime, RHSTime, LHSTime, commSendTime, ...
            commSendFrame] = ...
            controlSpeedWithSteps_WeberPerceptionFaster( ...
            round(velL*1000), round(velR*1000), forceThreshold, ...
            shortName, mode);

    case 16 % OG Hreflex with audio feedback (fast, slow, good job)
        mode = 1;
        % added by DMMO 3/13/2020
        audioFbBtn = questdlg( ...
            'Should audio feedback on speed be provided?');
        [RTOTime, LTOTime, RHSTime, LHSTime, commSendTime, ...
            commSendFrame] = HreflexOGWithAudio(round(velL*1000), ...
            round(velR*1000), forceThreshold, shortName, mode, ...
            [], [], [], strcmp(audioFbBtn, 'Yes'));
end

pause(1.5); % Wait three seconds before stopping software collection
% Stop capture Nexus & EMGWorks
if startedEMG_flag
    %     XServer.AppActivate('EMGworks 4.0.13 - Workflow Environment Pro'); %Get EMG in front
    %     XServer.SendKeys('^s'); %Stop acquisition
    %     XServer.AppActivate('AdaptationGUI'); %This window
    disp(['Stopping EMG Port ' datestr(datetime('now'))])
    fopen(ss);
    pause(0.1);
    fclose(ss);
    disp(['Done Stopping EMG Port ' datestr(datetime('now'))])
end
if startedNexus_flag
    %     XServer.AppActivate('Vicon Nexus 1.8.5');
    %     pause(.3)
    %      robot.mouseMove(1700, 685); %Coordinates in screen
    %      robot.mousePress(InputEvent.BUTTON1_MASK);%Left-button, right= 3
    %      pause(.1)
    %      robot.mouseRelease(InputEvent.BUTTON1_MASK);
    %      XServer.AppActivate('AdaptationGUI');

    %***************New method, use UDP packet to stop Nexus collection
    %       stopmsg=['<?xml version="1.0" encoding="UTF-8" standalone="no" ?><CaptureStop RESULT="SUCCESS"><Name VALUE="Trial' num2str(TrialNum) '"/><DatabasePath VALUE="' nexuspath '\"/><Delay VALUE="0"/><PacketID VALUE="' num2str(TrialNum*10) '"/></CaptureStop>']; %311
    %       step(myudp,int8(stopmsg));
    %
    disp(['Closing Vicon Port ' datestr(datetime('now'))])
    fopen(s);
    pause(0.1);
    fclose(s);
    disp(['Done Closing Vicon Port ' datestr(datetime('now'))])
end

set(handles.Status_textbox, 'String', 'Ready');
set(handles.Status_textbox, 'BackgroundColor', 'Green');

% increment Trial # upon completion of Callback
% TrialNum = TrialNum+1;

guidata(hObject, handles);

% --- Executes on button press in Stop_button.
function Stop_button_Callback(hObject, eventdata, handles)
%STOP_BUTTON_CALLBACK Signal all controllers to stop via the STOP flag.
%
% Inputs:
%   hObject - handle to Stop_button (see GCBO)
%   eventdata - reserved for a future MATLAB version
%   handles - structure with handles and user data (see GUIDATA)
%
% Toolbox Dependencies:
%   None

global STOP;
STOP = true;

% if STOP
%     set(handles.Status_textbox,'String','Stopped');
%     set(handles.Status_textbox,'BackgroundColor','red');
%     pause(0.25);
%     set(handles.Status_textbox,'String','Ready');
%     set(handles.Status_textbox,'BackgroundColor','green');
% end



guidata(hObject, handles);

% ============================================================
% ================ Logging, Exit & Save ======================
% ============================================================

% --- Executes on selection change in listbox1.
function listbox1_Callback(hObject, eventdata, handles)
% Hints: contents = cellstr(get(hObject,'String')) returns listbox1
%        contents{get(hObject,'Value')} returns selected item

% --- Executes during object creation, after setting all properties.
function listbox1_CreateFcn(hObject, eventdata, handles)
% Hint: listbox controls usually have a white background on Windows.
%       See ISPC and COMPUTER.
if ispc && isequal(get(hObject, 'BackgroundColor'), ...
        get(0, 'defaultUicontrolBackgroundColor'))
    set(hObject, 'BackgroundColor', 'White');
end

% --- Executes on button press in Exit_button.
function Exit_button_Callback(hObject, eventdata, handles)
%EXIT_BUTTON_CALLBACK Close all figures and clear the workspace.
%
% Inputs:
%   hObject - handle to Exit_button (see GCBO)
%   eventdata - reserved for a future MATLAB version
%   handles - structure with handles and user data (see GUIDATA)
%
% Toolbox Dependencies:
%   None

close all;
clear all;

% --- Executes on button press in SaveAs_button.
function SaveAs_button_Callback(hObject, eventdata, handles)
%SAVEAS_BUTTON_CALLBACK Save the current log to the named MAT-file.
%
% Inputs:
%   hObject - handle to SaveAs_button (see GCBO)
%   eventdata - reserved for a future MATLAB version
%   handles - structure with handles and user data (see GUIDATA)
%
% Toolbox Dependencies:
%   None

% global profilename
% global RTOTime
% global LTOTime
% global RHSTime
% global LHSTime
% global commSendTime
% global commSendFrame
global listbox

savename = get(handles.SaveAs_textbox, 'String');

set(handles.Status_textbox, 'String', 'Saving...');
set(handles.Status_textbox, 'BackgroundColor', 'Yellow');

if isempty(savename) == 1
    savename = 'HEY_YOU_FORGOT_TO_NAME_THIS_FIX_IT';
else
end
% keyboard
save(savename, 'listbox');
% save savename;

guidata(hObject, handles);


% --- Executes on button press in Pause_togglebutton.
function Pause_togglebutton_Callback(hObject, eventdata, handles)
% hObject    handle to Pause_togglebutton (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    structure with handles and user data (see GUIDATA)

% Hint: get(hObject,'Value') returns toggle state of Pause_togglebutton
global PAUSE
global currentstring
global currentcolor

PAUSE = get(hObject,'Value');

if PAUSE == 0
    set(handles.Pause_togglebutton,'String','Pause');
    set(handles.Status_textbox,'String',currentstring);%refreshes the status to what it was before pause
    set(handles.Status_textbox,'BackgroundColor',currentcolor);
    set(handles.Execute_button,'Enable','on');
else
    currentstring = get(handles.Status_textbox,'String');
    currentcolor = get(handles.Status_textbox,'BackgroundColor');
    set(handles.Pause_togglebutton,'String','Resume');
    set(handles.Status_textbox,'String','Paused');
    set(handles.Status_textbox,'BackgroundColor','Yellow');

    %disable execute button so it can't be pressed again, causing a crash
    set(handles.Execute_button,'Enable','off');
end


set(handles.Status_textbox, 'String', 'Ready');
set(handles.Status_textbox, 'BackgroundColor', 'Green');
guidata(hObject, handles);

% --- Executes on button press in HideLog_checkbox.
function HideLog_checkbox_Callback(hObject, eventdata, handles)
%HIDELOG_CHECKBOX_CALLBACK Show or hide the event-log listbox.
%
% Inputs:
%   hObject - handle to HideLog_checkbox (see GCBO)
%   eventdata - reserved for a future MATLAB version
%   handles - structure with handles and user data (see GUIDATA)
%
% Toolbox Dependencies:
%   None

LogView = get(hObject, 'Value');

if LogView == 0
    set(handles.listbox1, 'Visible', 'On');
elseif LogView == 1
    set(handles.listbox1, 'Visible', 'Off');
end



guidata(hObject, handles);

% ============================================================
% =============== Device & Option Checkboxes =================
% ============================================================

% --- Executes on button press in Nexus_checkbox.
function Nexus_checkbox_Callback(hObject, eventdata, handles)
% Hint: get(hObject,'Value') returns toggle state of Nexus_checkbox

% --- Executes on button press in EMGWorks_checkbox.
function EMGWorks_checkbox_Callback(hObject, eventdata, handles)
% Hint: get(hObject,'Value') returns toggle state of EMGWorks_checkbox

% --- Executes when selecting the audio_feedback controller.
function AudioFeedback_checkbox_Callback(hObject, eventdata, handles)
% Hint: get(hObject,'Value') returns toggle state of Audiofeedback

% --- Executes on button press in StoptreadmillSTOP_checkbox.
function StoptreadmillSTOP_checkbox_Callback(hObject, eventdata, handles)
% Hint: get(hObject,'Value') returns toggle state of the checkbox

% --- Executes on button press in StoptreadmillEND_checkbox.
function StoptreadmillEND_checkbox_Callback(hObject, eventdata, handles)
% Hint: get(hObject,'Value') returns toggle state of the checkbox



% ============================================================
% =========== Controller Menu & Profile Browse ===============
% ============================================================

% --- Executes on selection change in popupmenu2.
function popupmenu2_Callback(hObject, eventdata, handles)
% global Functionname

% check which function to call when Execute is pressed.
% Functionname = get(hObject,'Value');

guidata(hObject, handles);
% Hints: contents = cellstr(get(hObject,'String')) returns popupmenu2
%        contents{get(hObject,'Value')} returns selected item

% --- Executes during object creation, after setting all properties.
function popupmenu2_CreateFcn(hObject, eventdata, handles)
% Hint: popupmenu controls usually have a white background on Windows.
%       See ISPC and COMPUTER.
if ispc && isequal(get(hObject, 'BackgroundColor'), ...
        get(0, 'defaultUicontrolBackgroundColor'))
    set(hObject, 'BackgroundColor', 'White');
end

% --- Executes on button press in profilebrowse.
function profilebrowse_Callback(hObject, eventdata, handles)
%PROFILEBROWSE_CALLBACK Browse for a profile and plot its speed curves.
%
%   Lets the user pick a speed-profile MAT-file, plots the left/right
%   belt velocities, populates the step-count boxes, and enables
%   Execute.
%
% Inputs:
%   hObject - handle to profilebrowse (see GCBO)
%   eventdata - reserved for a future MATLAB version
%   handles - structure with handles and user data (see GUIDATA)
%
% Toolbox Dependencies:
%   None

global profilename

% global flasher
% stop(flasher);
% delete(flasher);

set(handles.Status_textbox, 'String', 'Plotting');
set(handles.Status_textbox, 'BackgroundColor', 'Yellow');
pause(0.25);

[d, n, e] = fileparts(which(mfilename()));
[ff, dd, ~] = uigetfile([d '\profiles\']);
profilename = [dd ff];
try
    load(profilename);

    t = [0:length(velL)-1];

    set(handles.profileaxes, 'NextPlot', 'replace')
    plot(handles.profileaxes, t, velL, 'b', t, velR, 'r', ...
        'LineWidth', 2);
    if isrow(velL) && isrow(velR)
        ylim([min([velL velR])-1, max([velL velR])+1]);
    else
        ylim([min([velL; velR])-1, max([velL; velR])+1]);
    end
    % ylim([0 2.0]);

    xlabel('Stride Count');
    ylabel('Speed (m/s)');
    legend('Left Foot', 'Right Foot', 'AutoUpdate', 'off');
    set(handles.profileaxes, 'NextPlot', 'add')

    set(handles.Status_textbox, 'String', 'Ready');
    set(handles.Status_textbox, 'BackgroundColor', 'Green');
    set(handles.totalLstepsBox, 'String', num2str(length(velL)));
    set(handles.totalRstepsBox, 'String', num2str(length(velL)));
    clear velL velR;

    set(handles.Execute_button, 'Enable', 'On');
catch

end

guidata(hObject, handles);

% --- Executes on button press in Incline.
function Incline_Callback(hObject, eventdata, handles)
% global InclineAngle

% uiwait(msgbox(['Warning! You are about to change the written incline angle of the treadmill!' sprintf('\n') sprintf('\n') 'This should not be done unless the treadmill has already been moved to the new angle and locked.' sprintf('\n') 'Failure to comply will result in serious damage!'],'Wait!','warn'));
% InclineAngle = str2double(inputdlg('Please enter the new angle'));
%
% set(handles.Angle,'String',num2str(InclineAngle));

% keyboard
guidata(hObject, handles);

% --- Executes on button press in clearlog.
function clearlog_Callback(hObject, eventdata, handles)
% hObject    handle to clearlog (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    structure with handles and user data (see GUIDATA)
global listbox

listbox = {''};
set(handles.listbox1,'String',listbox);
guidata(hObject, handles);
% ============================================================
% ============= Perturbation / Manual Speed ==================
% ============================================================

% --- Executes on button press in perturbspeed.
function perturbspeed_Callback(hObject, eventdata, handles)
%PERTURBSPEED_CALLBACK Arm or disarm a manual speed perturbation.
%
%   When armed, reads the manual speed from the textbox and highlights
%   the button; when disarmed, resets the manual speed to zero.
%
% Inputs:
%   hObject - handle to perturbspeed (see GCBO)
%   eventdata - reserved for a future MATLAB version
%   handles - structure with handles and user data (see GUIDATA)
%
% Toolbox Dependencies:
%   None

global manspeed

Pert = get(hObject, 'Value');

if Pert == 1
    manspeed = str2double(get(handles.manspeedbox, 'String'));
    set(hObject, 'BackgroundColor', 'Red');
else
    manspeed = 0;
    set(hObject, 'BackgroundColor', [0.94 0.94 0.94]);
end

guidata(hObject, handles);

function manspeedbox_Callback(hObject, eventdata, handles)
% Hints: get(hObject,'String') returns contents of manspeedbox as text
%        str2double(get(hObject,'String')) returns contents as a double

% --- Executes during object creation, after setting all properties.
function manspeedbox_CreateFcn(hObject, eventdata, handles)
% Hint: edit controls usually have a white background on Windows.
%       See ISPC and COMPUTER.
if ispc && isequal(get(hObject, 'BackgroundColor'), ...
        get(0, 'defaultUicontrolBackgroundColor'))
    set(hObject, 'BackgroundColor', 'White');
end

% --- Executes on button press in waitForNexusChkBox.
function waitForNexusChkBox_Callback(hObject, eventdata, handles)
% hObject    handle to waitForNexusChkBox (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    structure with handles and user data (see GUIDATA)

% Hint: get(hObject,'Value') returns toggle state of waitForNexusChkBox
% ============================================================
% ================ Keyboard & Mouse Input ====================
% ============================================================

% --- Executes on key press with focus on figure1 and none of its
% --- controls.
function figure1_KeyPressFcn(hObject, eventdata, handles)
% eventdata fields: Key, Character, Modifier (see FIGURE)

function figure1_WindowKeyPressFcn(hObject, eventdata, handles)
%FIGURE1_WINDOWKEYPRESSFCN Log perception-task keypresses and cue audio.
%
%   On an allowed key (when memory logging is enabled and the previous
%   key was released), records the choice and time, updates the running
%   memory value, and plays the corresponding left/right click sound.
%
% Inputs:
%   hObject - handle to figure1 (see GCBO)
%   eventdata - key event data; uses the Key field
%   handles - structure with handles and user data (see GUIDATA)
%
% Toolbox Dependencies:
%   None

global keyWasReleased
global enableMemory
global firstPress
global counter
global addLog
global tone
global lastKeyPress
global allowedKeys

% CARLY MARCELA
global RFBClicker
global LFBClicker

% Added by Marcela 10/04/2019
global rclicksound
global lclicksound
global rFrequency
global lFrequency
global fastbeep

% Added by Shuqi 8/16/2022, skip clicker sound if doing N-back clicking.
global playClickerSound

% Get key:
keypress = eventdata.Key;
isAllowed = any(strcmp(keypress, allowedKeys));
% disp('Detect click')
if enableMemory && isAllowed && keyWasReleased
    %     disp('Detect click and if yes')
    % Add to counter & record keypress in log
    counter = counter + 1;
    addLog.keypress{counter, 1} = keypress;
    addLog.keypress{counter, 2} = now;
    addLog.keypressHeader = {'Choice', 'Time', 'RStepCount', ...
        'LStepCount', 'AddSteps'};
    addLog.keyTime{counter, 1} = datetime(now, 'ConvertFrom', 'datenum');

    % Take action:
    if ~firstPress
        global memory
        r = floor(2*rand); % Random integer in 0-2 interval
        e = 3 + r;
        switch keypress
            case {'uparrow', 'numpad8'}
                memory = memory + 1i*e;
            case {'downarrow', 'numpad2'}
                memory = memory - 1i*e;
            case {'leftarrow', 'numpad4', 'pageup'}
                memory = memory - e;
                RFBClicker = 0;
                LFBClicker = 1;
                display('LeftClick')
            case {'rightarrow', 'numpad6', 'pagedown'}
                memory = memory + e;
                RFBClicker = 1;
                LFBClicker = 0;
                display('RightClick')
        end
    else % firstpress=true
        firstPress = false; % firstPress=false; MGR and KF 02/18/2022
    end

    %%  Update the feedback figure
    % % % % % % %
    % % % % % % %         if strcmp(keypress, 'pagedown')==1 || strcmp(keypress, 'numpad6')==1 || strcmp(keypress, 'rightarrow')==1%IF I get info that they clicked Right
    % % % % % % %         RFBClicker=1;
    % % % % % % %         LFBClicker=0;
    % % % % % % %         elseif strcmp(keypress, 'pageup')==1 || strcmp(keypress, 'numpad4')==1 || strcmp(keypress, 'leftarrow')==1%If I get info that they clicked Left
    % % % % % % %         RFBClicker=0;
    % % % % % % %         LFBClicker=1;
    % % % % % % % %         else
    % % % % % % % %             RFBClicker=0; %ITS NEVER GETTING HERE!!!
    % % % % % % % %             LFBClicker=0;
    % % % % % % %         end

    %%
    % % % % % % % % %Play tone: %Uncomment to go back to previous perception
    % study (PAblo's)
    % % % % % % % %fo=2000;
    % % % % % % % %tone=sin(2*pi*[1:32]*fo/8192); %4ms tone
    % % % % % % % %Fs=8192;

    % % % % % %     Fs=48000;
    % % % % %    beep()
    % % % % %
    % % % % % %     sound(tone,Fs)
    % % % % %     %now
    % % % % %     lastKeyPress=now;
    % % % % %     keyWasReleased=false;

    %% Play tone (Added by Marcela for the Weber Perception 10/04/2019). If you want to go
    %back to the previous perception study uncommment the previous Play tone
    %secttion and comment this one.
    %
    if playClickerSound
        if RFBClicker == 1
            sound(rclicksound, rFrequency);
        elseif LFBClicker == 1
            sound(lclicksound, lFrequency);
        end
    end
    %   play(fastbeep);

    lastKeyPress = now;
    keyWasReleased = false;
end

function figure1_WindowKeyReleaseFcn(hObject, eventdata, handles)
%FIGURE1_WINDOWKEYRELEASEFCN Clear the key-held latch on key release.
%
%   Marks the key as released so the next allowed press is logged once.
%
% Inputs:
%   hObject - handle to figure1 (see GCBO)
%   eventdata - key event data; uses the Key field
%   handles - structure with handles and user data (see GUIDATA)
%
% Toolbox Dependencies:
%   None

global keyWasReleased
global allowedKeys
keypress = eventdata.Key;
isAllowed = any(strcmp(keypress, allowedKeys));
if isAllowed
    keyWasReleased = true;
end

% --- Executes on mouse press over figure background, over a disabled or
% --- inactive control, or over an axes background.
function figure1_WindowButtonUpFcn(hObject, eventdata, handles)
% Executes when mouse button is released

% --- Executes on mouse press over figure background, over a disabled or
% --- inactive control, or over an axes background.
function figure1_WindowButtonDownFcn(hObject, eventdata, handles)
% % hObject    handle to figure1 (see GCBO)
% % eventdata  reserved - to be defined in a future version of MATLAB
% % handles    structure with handles and user data (see GUIDATA)
% %Executes when mouse buttion is pressed
% global enableMemory
% eventdata
% eventdata.Source
% get(gcbf, 'SelectionType')
% if enableMemory
% fo=2000;
% tone=sin(2*pi*[1:32]*fo/8192); %4ms tone
% soundsc(tone,8192)
% global keypress
% global addLog
% keypress = eventdata.Key;
% global counter
% counter=counter+1;
% addLog.keypress{counter,1}=keypress;
% addLog.keypress{counter,2}=now;
% global memory
%     r=round(5*rand());
%     switch keypress
%         case 'uparrow' %Increase both belts
%             %memory=memory+1i*5+1i*r;
%         case 'downarrow' %Decrease both belts
%             %memory=memory-1i*5-1i*r;
%         case {'leftarrow','numpad4'} %Increase L, decrease R
%             memory=memory-5-r;
%         case {'rightarrow','numpad6'} %Increase R, decrease L
%             memory=memory+5+r;
%     end
% end

% --- Executes on button press in feedbackBox.
function feedbackBox_Callback(hObject, eventdata, handles)
%FEEDBACKBOX_CALLBACK Mirror the feedback checkbox into feedbackFlag.
%
% Inputs:
%   hObject - handle to feedbackBox (see GCBO)
%   eventdata - reserved for a future MATLAB version
%   handles - structure with handles and user data (see GUIDATA)
%
% Toolbox Dependencies:
%   None

global feedbackFlag
% --- Executes during object creation, after setting all properties.
function EMGWorks_checkbox_CreateFcn(hObject, eventdata, handles)
% hObject    handle to EMGWorks_checkbox (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    empty - handles not created until after all CreateFcns called

% --- Executes during object deletion, before destroying properties.
function EMGWorks_checkbox_DeleteFcn(hObject, eventdata, handles)
% hObject    handle to EMGWorks_checkbox (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    structure with handles and user data (see GUIDATA)
feedbackFlag = hObject.Value;
