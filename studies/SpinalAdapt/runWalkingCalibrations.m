function isCalibration = runWalkingCalibrations(handles,profileDir)
% isDoneCalib = false;
% while ~isDoneCalib
    global profilename

isCalibBtn = questdlg(['Do you want to run a Hreflex walking ' ...
    'calibration trial?']);
if strcmp(isCalibBtn,'Yes') % run dynamic (i.e., walking) calibration
    isCalibration = true;
    handles.popupmenu2.set('Value',14)  % NirsHreflexArduinoOpenLoopWithAudio
    opts.Interpreter = 'tex';
    opts.Default = 'Slow';
    profileToGen = questdlg(['What TM speed to calibrate on? (Default is slow)'],...
        '','Fast','Slow',opts); % default choose slow
    switch profileToGen
        case 'Fast'
            profilename = [profileDir 'CalibrationFast.mat'];
            disp('Run Hreflex calibration with fast TM walking speed.');
        case 'Slow'
            profilename = [profileDir 'CalibrationSlow.mat'];
            disp('Run Hreflex calibration with slow TM walking speed.');
        otherwise
            disp('No response given, quit the script now.');
            return
    end
    manualLoadProfile([],[],handles,profilename);
    AdaptationGUI( ...
        'Execute_button_Callback',handles.Execute_button,[],handles);
else
           isCalibration = false; %
end
end