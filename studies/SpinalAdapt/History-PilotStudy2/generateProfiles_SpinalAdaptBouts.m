function profileDir = generateProfiles_SpinalAdaptBouts( ...
    slow, fast, baseOnly, profileDir, fastLeg, ramp2Split)
%GENERATEPROFILES_SPINALADAPTBOUTS Generate speed and stim profiles for
% the SpinalAdapt protocol and save them to disk.
%
%   Generates speed (velL, velR) and H-reflex stimulus (stimL, stimR)
%   profiles for each condition in the SpinalAdapt bout-based protocol.
%   Call twice per session: once with baseOnly = true to produce baseline
%   and calibration profiles before fast-leg assignment, then again with
%   baseOnly = false to produce training and post-adaptation profiles.
%
% Inputs:
%   slow       - double; slow belt speed (m/s)
%   fast       - double; fast belt speed (m/s)
%   baseOnly   - logical; if true, generates only baseline/calibration
%                profiles (fastLeg and ramp2Split not required)
%   profileDir - char; path to directory where profiles are saved
%   fastLeg    - char; 'R' or 'L' — which leg uses the fast belt speed.
%                Required when baseOnly = false.
%   ramp2Split - logical; if true, use a gradual ramp from tied to split
%                speed; if false, use an abrupt transition. Required when
%                baseOnly = false; default false.
%
% Outputs:
%   profileDir - char; path where profiles were saved (same as input)
%
% Toolbox Dependencies:
%   None
%
% See also RUNPROTOCOL_SPINALADAPTBOUTS, RUNWALKINGCALIBRATIONS.

if nargin == 5          % fastLeg provided but not ramp2Split
    ramp2Split = false;
end
if ~exist(profileDir, 'dir')
    mkdir(profileDir);
end

if baseOnly

    %% Define Baseline and Calibration Constants
    baseTiedStrides    = 150;   % strides; TM tied baseline trial length
    baseOGStrides      = 100;   % strides; OG baseline trial length
    calibStrides       = 400;   % strides; H-reflex calibration trial length
    stimCycleLen       = 10;    % strides; H-reflex stim cycle length
    stimCycleOffset    = 4;     % strides; pulse position within cycle
    calibSettleStrides = 5;     % strides; no-stim period at calib start

    %% Generate TM Tied Baseline Profiles
    stimCycle = [zeros(stimCycleOffset - 1, 1); 1; ...
        zeros(stimCycleLen - stimCycleOffset, 1)];

    % fast
    velL  = ones(baseTiedStrides, 1) * fast;
    velR  = velL;
    stimL = repmat(stimCycle, baseTiedStrides / stimCycleLen, 1);
    stimR = stimL;
    save(fullfile(profileDir, 'TMBaseFast.mat'), ...
        'velL', 'velR', 'stimL', 'stimR');

    % slow
    velL  = ones(baseTiedStrides, 1) * slow;
    velR  = velL;
    stimL = repmat(stimCycle, baseTiedStrides / stimCycleLen, 1);
    stimR = stimL;
    save(fullfile(profileDir, 'TMBaseSlow.mat'), ...
        'velL', 'velR', 'stimL', 'stimR');

    %% Generate OG Baseline Profiles (no stim columns)
    % slow
    velL = ones(baseOGStrides, 1) * slow;
    velR = velL;
%     stimL = repmat([0 0 0 1 0 0 0 0 1 0]',10,1);
%     stimR = stimL;
    save(fullfile(profileDir, 'OGBaseSlow.mat'), 'velL', 'velR');

    % fast
    velL = ones(baseOGStrides, 1) * fast;
    velR = velL;
%     stimL = repmat([0 0 0 1 0 0 0 0 1 0]',10,1);
%     stimR = stimL;
    save(fullfile(profileDir, 'OGBaseFast.mat'), 'velL', 'velR');

    %% Generate H-Reflex Walking Calibration Profiles
    % Build stim schedule: calibSettleStrides no-stim settle period, then
    % stims at 2-stride intervals within each intensity level; 7-stride
    % gap (6 rest strides + 1 stim) between intensity changes gives the
    % experimenter time to adjust the stimulator knob.
    stimSteps = [0 repmat(2, 1, 5), repmat([7 2 2 2 2 2], 1, 11)];
    stimSteps = calibSettleStrides + cumsum(stimSteps);

    % fast
    velL = ones(calibStrides, 1) * fast;
    velR = velL;
    stimL = zeros(calibStrides, 1);
    stimL(stimSteps) = 1;
    stimR = stimL;
    save(fullfile(profileDir, 'CalibrationFast.mat'), ...
        'velL', 'velR', 'stimL', 'stimR');

    % slow
    velL = ones(calibStrides, 1) * slow;
    velR = velL;
    save(fullfile(profileDir, 'CalibrationSlow.mat'), ...
        'velL', 'velR', 'stimL', 'stimR');

else

    %% Define Training Protocol Constants
    slowStridesPerBout   = 20;  % strides; slow-belt segment per bout rep
    tiedStepsMin         = 50;  % strides; min randomized tied segment
    tiedStepsMax         = 60;  % strides; max randomized tied segment
    post1TiedStrides     = 50;  % strides; tied-fast segment in Post1
    post1NegShortStrides = 30;  % strides; neg-short-split in Post1
    post1PostNegStrides  = 100; % strides; tied-fast post-neg-short
    post2Strides         = 200; % strides; final post-adaptation trial
    postAdaptStimPeriod  = 5;   % strides; stim cycle in post-adapt sections
    baseTiedStrides      = 150; % strides; post-adapt append to last split

    rng(100);               % fixed seed for reproducible bout randomization
    repPerTrain      = 4;   % bout repetitions per training condition
    totalSplitTrains = 5;   % number of split-belt training conditions
    totalCtrTrains   = 2;   % number of tied (control) training conditions

    randTiedStepsSplit = randi([tiedStepsMin, tiedStepsMax], ...
        totalSplitTrains, repPerTrain);
    randTiedStepsSplit(1, 1) = slowStridesPerBout;  % 1st train, 1st bout
    randTiedStepsCtr = randi([tiedStepsMin, tiedStepsMax], ...
        totalCtrTrains, repPerTrain);

    restPadSteps = zeros(50, 1);    % 50-stride zero-speed rest between bouts

    % 10-stride ramp from 10% to 100% of fast speed at bout start;
    % endpoint excluded so stride 10 approaches (but does not reach) fast.
    ramp2Tied = linspace(0.1 * fast, fast, 11);
    ramp2Tied = ramp2Tied(1:end-1)';
    ramp2TiedStim = zeros(size(ramp2Tied));

    %% Build Ramp-to-Split Profile
    if ramp2Split   % 20-stride gradual ramp from tied to split speed
        rampToSplitStrides = 20;    % strides; gradual fast-to-slow ramp
        ramp2SplitSteps = linspace(fast, slow, rampToSplitStrides)';
        ramp2SplitStims = zeros(rampToSplitStrides, 1);
    else            % abrupt transition; empty arrays omitted below
        ramp2SplitSteps = [];
        ramp2SplitStims = [];
    end

    %% Build Control Train Profiles (Tied Walking)
    for ctTrain = 1:totalCtrTrains
        velL  = [];  stimL = [];
        for ii = 1:repPerTrain
            velL = [velL; restPadSteps; ramp2Tied; ...
                ones(randTiedStepsCtr(ctTrain, ii), 1) * fast; ...
                ramp2SplitSteps; ones(slowStridesPerBout, 1) * slow];
            stimL = [stimL; restPadSteps; ramp2TiedStim; ...
                ones(randTiedStepsCtr(ctTrain, ii), 1); ...
                ramp2SplitStims; ones(slowStridesPerBout, 1)];
        end
        velL  = [velL; restPadSteps];
        stimL = [stimL; restPadSteps];
        velR  = velL;
        stimR = stimL;
        save(fullfile(profileDir, ['CtrlTrain_' mat2str(ctTrain) '.mat']), ...
            'velL', 'velR', 'stimL', 'stimR');
    end

    %% Build Split Train Profiles
    for splitTrain = 1:totalSplitTrains
        velL  = [];  velR = [];  stimL = [];
        for ii = 1:repPerTrain
            velL = [velL; restPadSteps; ramp2Tied; ...
                ones(randTiedStepsSplit(splitTrain, ii), 1) * fast; ...
                ramp2SplitSteps; ones(slowStridesPerBout, 1) * slow];
            velR = [velR; restPadSteps; ramp2Tied; ...
                ones(randTiedStepsSplit(splitTrain, ii), 1) * fast; ...
                ramp2SplitSteps; ones(slowStridesPerBout, 1) * fast];
            stimL = [stimL; restPadSteps; ramp2TiedStim; ...
                ones(randTiedStepsSplit(splitTrain, ii), 1); ...
                ramp2SplitStims; ones(slowStridesPerBout, 1)];
        end
        velL  = [velL; restPadSteps];
        velR  = [velR; restPadSteps];
        stimL = [stimL; restPadSteps];

        if splitTrain == totalSplitTrains   % last split: append post-adapt
            velL  = [velL; ones(baseTiedStrides, 1) * fast];
            velR  = [velR; ones(baseTiedStrides, 1) * fast];
            postAdaptStimCycle = [1; zeros(postAdaptStimPeriod - 1, 1)];
            stimL = [stimL; repmat(postAdaptStimCycle, ...
                baseTiedStrides / postAdaptStimPeriod, 1)];
        end

        stimR = stimL;

        if strcmp(fastLeg, 'L')     % swap leg profiles if left is fast
            temp  = velR;
            velR  = velL;
            velL  = temp;
        end
        save(fullfile(profileDir, ...
            ['PreSplitTrain_' num2str(splitTrain) '.mat']), ...
            'velL', 'velR', 'stimL', 'stimR');
    end

    %% Build Post-Train Profiles
    % Post1: 50 tied-fast + 30 neg-short split + 100 tied-fast.
    % Default: right belt fast (neg-short = left fast); swap if fastLeg='L'.
    post1StimCycle = [zeros(postAdaptStimPeriod - 1, 1); 1]; % pulse at end
    velR  = [repmat(fast, post1TiedStrides, 1); ...
             ones(post1NegShortStrides, 1) * slow; ...
             ones(post1PostNegStrides, 1) * fast];
    velL  = [repmat(fast, post1TiedStrides, 1); ...
             ones(post1NegShortStrides, 1) * fast; ...
             ones(post1PostNegStrides, 1) * fast];
    stimL = [repmat(post1StimCycle, ...
                 post1TiedStrides / postAdaptStimPeriod, 1); ...
             zeros(post1NegShortStrides, 1); ...
             repmat(post1StimCycle, ...
                 post1PostNegStrides / postAdaptStimPeriod, 1)];
    stimR = stimL;
    if strcmp(fastLeg, 'L')     % swap leg velocity profiles; stim unchanged
        temp  = velR;
        velR  = velL;
        velL  = temp;
    end
    save(fullfile(profileDir, 'Post1WtNegShort.mat'), ...
        'velL', 'velR', 'stimL', 'stimR');

    % Post2: 200 strides tied-fast. Pulse at start of each stim cycle.
    postAdaptStimCycle = [1; zeros(postAdaptStimPeriod - 1, 1)];
    velL  = repmat(fast, post2Strides, 1);
    velR  = repmat(fast, post2Strides, 1);
    stimR = repmat(postAdaptStimCycle, ...
        post2Strides / postAdaptStimPeriod, 1);
    stimL = stimR;
    save(fullfile(profileDir, 'Post2.mat'), ...
        'velL', 'velR', 'stimL', 'stimR');

end
end
