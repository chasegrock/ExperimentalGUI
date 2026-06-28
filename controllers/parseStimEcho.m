function [bufOut,recs] = parseStimEcho(buf)
%PARSESTIMECHO Parse Arduino H-reflex stim-echo records from a byte buffer.
%
%   Extracts every complete, newline-terminated stim-echo record of the
%   form "S,<leg>,<step>,<stimMs>,<toRefMs>,<estSS>" from buf, returning
%   the parsed records and any trailing partial line. This is the pure
%   (I/O-free) core shared by the controller's non-blocking serial drain
%   and its self-test: callers append freshly read serial bytes to the
%   leftover buffer and pass the result here. Malformed or foreign lines
%   (e.g., the disabled force-CSV logger) are silently ignored, and a
%   record split across two reads is reassembled via the returned bufOut.
%
% Inputs:
%   buf - char row vector: previous partial line plus newly read bytes
%
% Outputs:
%   bufOut - trailing partial line (no terminating newline yet) to carry
%            into the next call; '' when buf ended on a newline
%   recs - Px5 numeric array, one row per parsed pulse:
%          [leg(1=L,2=R), ardStep, stimMs, toRefMs, estSSms]
%
% Toolbox Dependencies: None
%
% See also NIRSHREFLEXARDUINOOPENLOOPWITHAUDIO.

arguments
    buf (1,:) char
end

recs = zeros(0,5);
bufOut = buf;

% split off complete (newline-terminated) lines; keep any partial remainder
idxNL = find(buf == newline);
if isempty(idxNL)
    return;
end
lastNL = idxNL(end);
lines = strsplit(buf(1:lastNL),newline);
bufOut = buf(lastNL+1:end);  % partial line for next call (may be empty)

for k = 1:numel(lines)
    ln = strtrim(lines{k});     % also strips the trailing CR from println
    if isempty(ln)
        continue;
    end
    parts = strsplit(ln,',');
    if numel(parts) ~= 6 || ~strcmp(parts{1},'S')
        continue;               % not a stim-echo record
    end
    if strcmpi(parts{2},'L')
        legNum = 1;
    elseif strcmpi(parts{2},'R')
        legNum = 2;
    else
        continue;
    end
    vals = str2double(parts(3:6));  % ardStep, stimMs, toRefMs, estSS
    if any(isnan(vals))
        continue;               % unparseable numeric field; skip record
    end
    recs(end+1,:) = [legNum vals];  %#ok<AGROW>
end

end
