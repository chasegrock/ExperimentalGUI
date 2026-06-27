function isCalibration = runWalkingCalibrations(handles, profileDir)
%RUNWALKINGCALIBRATIONS Prompt the experimenter to run an H-reflex walking
% calibration trial and execute it via AdaptationGUI if confirmed.
%
%   Asks whether to run a calibration trial and at which treadmill speed.
%   Loads the corresponding profile and starts the controller via the GUI.
%   Called in a loop from RunProtocol_SpinalAdaptBouts until the
%   experimenter selects 'No'.
%
% Inputs:
%   handles    - struct; GUIDE handles structure from AdaptationGUI
%   profileDir - char; path to the directory containing calibration profiles
%
% Outputs:
%   isCalibration - logical; true if a calibration trial was started,
%                   false if the experimenter chose not to run one
%
% Toolbox Dependencies:
%   None
%
% See also RUNPROTOCOL_SPINALADAPTBOUTS, ADAPTATIONGUI.

% isDoneCalib = false;
% while ~isDoneCalib

global profilename

ctrlSlotNirsHreflex = 14;   % NirsHreflexArduinoOpenLoopWithAudio (GUI slot)

isCalibBtn = questdlg(['Do you want to run a Hreflex walking ' ...
    'calibration trial?']);
if strcmp(isCalibBtn, 'Yes')    % run dynamic (i.e., walking) calibration
    isCalibration = true;
    handles.popupmenu2.set('Value', ctrlSlotNirsHreflex);
    opts.Interpreter = 'tex';
    opts.Default     = 'Slow';
    profileToGen = questdlg( ...
        'What TM speed to calibrate on? (Default is slow)', ...
        '', 'Fast', 'Slow', opts);
    switch profileToGen
        case 'Fast'
            profilename = fullfile(profileDir, 'CalibrationFast.mat');
            disp('Run Hreflex calibration with fast TM walking speed.');
        case 'Slow'
            profilename = fullfile(profileDir, 'CalibrationSlow.mat');
            disp('Run Hreflex calibration with slow TM walking speed.');
        otherwise
            disp('No response given, quit the script now.');
            return
    end
    manualLoadProfile([], [], handles, profilename);
    AdaptationGUI( ...
        'Execute_button_Callback', handles.Execute_button, [], handles);
else
    isCalibration = false;
end
end
