function profileDir = generateProfiles_SpinalAdaptBouts( ...
    slowSpeed, fastSpeed, baseOnly, profileDir, fastLeg)
%GENERATEPROFILES_SPINALADAPTBOUTS Generate speed and stim profiles for
% the SpinalAdapt protocol and save them to disk.
%
%   Generates speed (velL, velR) and H-reflex stimulus (stimL, stimR)
%   profiles for each condition in the SpinalAdapt bout-based protocol.
%   Call twice per session: once with baseOnly = true to produce baseline
%   and calibration profiles before fast-leg assignment, then again with
%   baseOnly = false to produce training and post-adaptation profiles.
%
%   TEMPLATE — Updated with new SpinalAdapt protocol bout structure
%   (10-stride ramp + 10-stride SS per bout, 10 bouts per trial,
%   8 split trials). Verify all parameters against the final approved
%   protocol specification before data collection begins.
%   See History-PilotStudy2/ for the Pilot Study 2 original.
%
% Inputs:
%   slowSpeed  - double; slow belt speed (m/s)
%   fastSpeed  - double; fast belt speed (m/s)
%   baseOnly   - logical; if true, generate only baseline/calibration
%                profiles (fastLeg not required)
%   profileDir - char; path to directory where profiles are saved
%   fastLeg    - char; 'R' or 'L' — which leg uses the fast belt speed.
%                Required when baseOnly = false.
%
% Outputs:
%   profileDir - char; path where profiles were saved (same as input)
%
% Toolbox Dependencies:
%   None
%
% See also RUNPROTOCOL_SPINALADAPTBOUTS, RUNWALKINGCALIBRATIONS.

if ~exist(profileDir, 'dir')
    mkdir(profileDir);
end

if baseOnly

    %% Define Baseline and Calibration Constants
    baseTMStrides      = 100;   % strides; TM tied baseline trial length
    baseOGStrides      = 100;   % strides; OG baseline trial length
    calibStrides       = 400;   % strides; H-reflex calib trial length
    stimCycleLen       = 10;    % strides; H-reflex stim cycle length
    stimCycleOffset    = 4;     % strides; pulse position within cycle
    calibSettleStrides = 5;     % strides; no-stim period at calib start

    %% Generate TM Tied Baseline Profiles
    stimCycle = [zeros(stimCycleOffset - 1, 1); 1; ...
        zeros(stimCycleLen - stimCycleOffset, 1)];

    % fast
    velL  = ones(baseTMStrides, 1) * fastSpeed;
    velR  = velL;
    stimL = repmat(stimCycle, baseTMStrides / stimCycleLen, 1);
    stimR = stimL;
    save(fullfile(profileDir, 'TMBaselineFast.mat'), ...
        'velL', 'velR', 'stimL', 'stimR');

    % slow
    velL  = ones(baseTMStrides, 1) * slowSpeed;
    velR  = velL;
    stimL = repmat(stimCycle, baseTMStrides / stimCycleLen, 1);
    stimR = stimL;
    save(fullfile(profileDir, 'TMBaselineSlow.mat'), ...
        'velL', 'velR', 'stimL', 'stimR');

    %% Generate OG Baseline Profiles
    % slow
    velL = ones(baseOGStrides, 1) * slowSpeed;
    velR = velL;
    save(fullfile(profileDir, 'OGBaselineSlow.mat'), 'velL', 'velR');

    % fast
    velL = ones(baseOGStrides, 1) * fastSpeed;
    velR = velL;
    save(fullfile(profileDir, 'OGBaselineFast.mat'), 'velL', 'velR');

    %% Generate H-Reflex Walking Calibration Profiles
    % Build stim schedule: calibSettleStrides no-stim settle period, then
    % stims at 2-stride intervals within each intensity level; 7-stride
    % gap (6 rest strides + 1 stim) between intensity changes gives the
    % experimenter time to adjust the stimulator knob.
    stimSteps = [0 repmat(2, 1, 5), repmat([7 2 2 2 2 2], 1, 11)];
    stimSteps = calibSettleStrides + cumsum(stimSteps);

    % fast
    velL = ones(calibStrides, 1) * fastSpeed;
    velR = velL;
    stimL = zeros(calibStrides, 1);
    stimL(stimSteps) = 1;
    stimR = stimL;
    save(fullfile(profileDir, 'CalibrationFast.mat'), ...
        'velL', 'velR', 'stimL', 'stimR');

    % slow
    velL = ones(calibStrides, 1) * slowSpeed;
    velR = velL;
    save(fullfile(profileDir, 'CalibrationSlow.mat'), ...
        'velL', 'velR', 'stimL', 'stimR');

else

    %% Define Training Protocol Constants
    boutsPerTrial    = 10;   % bouts per training trial
    rampStrides      = 10;   % strides; speed ramp from rest at bout start
    ssStrides        = 10;   % strides; steady-state walking per bout
    boutRestStrides  = 30;   % strides; max rest-pad between bouts
    boutStimPeriod   = 5;    % strides; H-reflex stim cycle during SS
    totalSplitTrials = 8;    % number of split-belt training trials
    postStrides      = 100;  % strides; per post-adaptation trial

    %% Build Per-Bout Speed and Stim Vectors
    % Ramp: linear increase from rest to target speed over rampStrides.
    rampFastBelt = (1:rampStrides)' / rampStrides * fastSpeed;
    rampSlowBelt = (1:rampStrides)' / rampStrides * slowSpeed;

    % Stim during SS: one pulse at the start of each boutStimPeriod.
    boutStimCycle = [1; zeros(boutStimPeriod - 1, 1)];
    ssStim = repmat(boutStimCycle, ssStrides / boutStimPeriod, 1);
    restPad = zeros(boutRestStrides, 1);

    %% Build Control Bouts Profile (Tied Walking)
    % Structure per bout: rest pad | ramp to fastSpeed | SS at fastSpeed.
    boutVelCtrl  = [rampFastBelt; ones(ssStrides, 1) * fastSpeed];
    boutStimCtrl = [zeros(rampStrides, 1); ssStim];

    velL = [];  stimL = [];
    for ii = 1:boutsPerTrial
        velL  = [velL;  restPad; boutVelCtrl];
        stimL = [stimL; restPad; boutStimCtrl];
    end
    velL  = [velL;  restPad];
    stimL = [stimL; restPad];
    velR  = velL;
    stimR = stimL;
    save(fullfile(profileDir, 'CtrlBouts.mat'), ...
        'velL', 'velR', 'stimL', 'stimR');

    %% Build Split Bouts Profile
    % Structure per bout: rest pad | split ramp | SS at fast/slow speeds.
    % Default: right belt fast, left belt slow; swap if fastLeg = 'L'.
    boutVelFast  = [rampFastBelt; ones(ssStrides, 1) * fastSpeed];
    boutVelSlow  = [rampSlowBelt; ones(ssStrides, 1) * slowSpeed];
    boutStimSplit = [zeros(rampStrides, 1); ssStim];

    velL = [];  velR = [];  stimL = [];
    for ii = 1:boutsPerTrial
        velL  = [velL;  restPad; boutVelSlow];
        velR  = [velR;  restPad; boutVelFast];
        stimL = [stimL; restPad; boutStimSplit];
    end
    velL  = [velL;  restPad];
    velR  = [velR;  restPad];
    stimL = [stimL; restPad];
    stimR = stimL;

    if strcmp(fastLeg, 'L')     % swap leg profiles if left is fast
        temp = velR;
        velR = velL;
        velL = temp;
    end
    save(fullfile(profileDir, 'SplitBouts.mat'), ...
        'velL', 'velR', 'stimL', 'stimR');

    %% Build Post-Adaptation Profile (Tied Fast Walking)
    stimPost = repmat(boutStimCycle, postStrides / boutStimPeriod, 1);
    velL  = ones(postStrides, 1) * fastSpeed;
    velR  = velL;
    stimL = stimPost;
    stimR = stimL;
    save(fullfile(profileDir, 'PostAdapt.mat'), ...
        'velL', 'velR', 'stimL', 'stimR');

end
end
