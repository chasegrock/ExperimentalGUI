function transferData_SpinalAdaptBouts(participantID, threshTime)
%TRANSFERDATA_SPINALADAPTBOUTS Transfer PC1 data for the SpinalAdapt study.
%
%   Recursively copies Vicon, NIRS, speed profile, and data-log files to
%   the server (W:\SpinalAdaptStudy\), creating non-existent destination
%   folders as needed, then creates analysis-ready subdirectories for
%   future processing.
%
% Inputs:
%   participantID - char or string; participant ID (e.g., 'SABH08',
%                   'SAS01V01')
%   threshTime    - datetime; only files newer than this timestamp are
%                   transferred (typically set at session start)
%
% Outputs:
%   None
%
% Toolbox Dependencies:
%   None (calls utils.transferDataSess from labTools)
%
% See also RUNPROTOCOL_SPINALADAPTBOUTS, UTILS.TRANSFERDATASESS.

% TODO: update function to open a GUI for user input if no inputs provided
narginchk(2, 2);        % verify correct number of input arguments

% TODO: add error checks and set default value for 'threshTime'

%% Define Data Paths
dirExpGUI = 'C:\Users\Public\Documents\MATLAB\ExperimentalGUI';
dirProfiles = fullfile(dirExpGUI, 'profiles', 'SpinalAdaptNirsStudy', ...
    participantID);
dirNIRS = 'C:\Users\cntctsml\Documents\Oxysoft Data\SpinalAdaptStudy';
dirData = fullfile(['C:\Users\Public\Documents\Vicon Training\' ...
    'SpinalAdaptStudy'], participantID, 'New Session');
dirSrvrSpinalAdapt = 'W:\SpinalAdaptStudy';
dirSrvrData        = fullfile(dirSrvrSpinalAdapt, 'Data', participantID);
dirSrvrRaw         = fullfile(dirSrvrSpinalAdapt, 'RawBackupData', ...
    participantID);

%% Transfer Files to Server
% Sources and destinations are paired in order; data is transferred to
% both the primary Data/ and the raw backup RawBackupData/ locations.
srcs  = {dirData ...
    dirProfiles fullfile(dirNIRS, participantID) ...
    dirData fullfile(dirNIRS, participantID) ...
    fullfile(dirExpGUI, 'datlogs') fullfile(dirExpGUI, 'datlogs')};
dests = {fullfile(dirSrvrData, 'Vicon') ...
    fullfile(dirSrvrData, 'SpeedProfiles') fullfile(dirSrvrData, 'NIRS') ...
    fullfile(dirSrvrRaw, 'Vicon') fullfile(dirSrvrRaw, 'NIRS') ...
    fullfile(dirSrvrData, 'DataLogs') fullfile(dirSrvrRaw, 'DataLogs')};

if ~isfolder(dirData)
    error('PC1 data directory does not exist: %s\n', dirData);
end

try
    utils.transferDataSess(srcs, dests, threshTime);
catch ME
    warning(ME.identifier, 'Data transfer failed: %s\n', ME.message);
    return;
end

if ~isfolder(fullfile(dirSrvrData, 'Vicon'))
    error('Data transfer unsuccessful; destination folder not found.');
end

% TODO: update to automatically rename data logs by trial name for C3D2MAT

%% Create Analysis Directories
pathsCreate = {
    fullfile(dirSrvrData, 'Results')
    fullfile(dirSrvrData, 'SyncFiles')
    fullfile(dirSrvrData, 'NASATLX')
    };

for ii = 1:length(pathsCreate)
    if ~isfolder(pathsCreate{ii})
        mkdir(pathsCreate{ii});
    end
end

end
