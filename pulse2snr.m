function SNRdB = pulse2snr(P,N,M,ISILimit,NoiseRMS)
%SNR    signal to noise ratio of pulse response and RMS noise
%   Calculate SNR in dB from pulse response, considering UI centers
%   only. Assume bang-bang phase detection. Ignore ISI below limit.
%
%   The signal-to-noise ratio is calculated as follows
%   1. The sampling instants are determined by finding the bang-bang CDR lock
%      point for the input pulse response using the Hula-Hoop algorithm.
%   2. The cursor is the point equidistant to the two points identified in step
%      1; the cursor's amplitude is the signal power.
%   3. All of the other samples an integer of samples per symbol away from the cursor
%      that are greater than ISILimit in power are considered ISI noise.
%   4. ISI noise power is calculated as the root mean square (norm) of all ISI
%      points.
%   5. Cross talk noise is determined based on peak amplitude position in each
%      cross talk vector, if provided.
%   6. Total noise is the square-root of the squared sum of ISI noise power,
%      random noise power (NoiseRMS), and cross-talk power.
%   7. Signal and total noise are weighted depending on the modulation scheme,
%      used.  See formulas in code.
%
%   Inputs:
%     P - Pulse response
%     N - Samples per symbol
%     M - Modulation, number of levels
%     ISILimit - ISI limit, fraction of cursor. ISI values below this
%                threshold are considered not to contribute to total noise.
%     NoiseRMS - Noise RMS, V. Additional random noise power to be considered
%                towards SNR calculation.
%
%   Outputs:
%     SNRdB - Signal to Noise ratio (dB)

%   Copyright 2020 The MathWorks, Inc.

%Validate inputs
validateattributes(P,{'numeric'},{'2d','finite'},'SNR','P',1);
validateattributes(N,{'numeric'},...
    {'scalar','finite','integer','positive'},...
    'SNR','N',2);
validateattributes(M,{'numeric'},...
    {'scalar','finite','integer','positive'},...
    'SNR','M',3);
validateattributes(ISILimit,{'numeric'},...
    {'scalar','finite','positive','real'},...
    'SNR','ISILimit',4);
validateattributes(NoiseRMS,{'numeric'},...
    {'scalar','finite','positive','real'},...
    'SNR','NoiseRMS',5);

% Initialize ISI limit
if nargin < 4
    ISILimit = 0.0;
end

% Initialize noise RMS
if nargin < 5
    NoiseRMS = 0.0;
end

% Get number of points and number of aggressors
num_pts  = size(P, 1)    ;
num_aggr = size(P, 2) - 1;

% Look for Mueller-Muller lock point
i_curs = round(pulseRecoverClock(P(:,1), 2*N));
v_curs = P(i_curs, 1);

% Pre-/post-cursor positions, including cursor
i_isi_pre  = i_curs:-N:1      ;
i_isi_post = i_curs:+N:num_pts;

% ISI position & amplitude, excluding cursor
i_isi = [i_isi_pre(end:-1:2) i_isi_post(2:1:end)];
v_isi = P(i_isi, 1);

% Ignore ISI below threshold
i_isi = i_isi(abs(v_isi) >= v_curs * ISILimit);
v_isi = P(i_isi, 1);

% ISI RMS
isi_rms = norm(v_isi);

% Account for Xtalk if it's available
if num_aggr > 0
    
    % Find peak amplitude for all Xtalk pulses
    [~, i_peak] = max(abs(P(:, 2:end)), [], 1);
    
    % Shift Xtalk PRs to put peak to 1st position
    for i_aggr = 1:1:num_aggr
        P(:, i_aggr+1) = circshift(P(:, i_aggr+1), -(i_peak(i_aggr)-1));
    end % i_aggr
    
    % Sample Xtalk pulses, and calculate Xtalk RMS
    xt_rms = norm(P(1:N:end, 2:end));
else
    % Otherwise set Xtalk RMS to zero
    xt_rms = 0.0;
end

% Scale SNR components
if M == 4
    v_curs  = (   1     / 6) * v_curs ;
    isi_rms = ( sqrt(5) / 6) * isi_rms;
    xt_rms  = ( sqrt(5) / 6) * xt_rms ;
else
    v_curs  = (   1     / 2) * v_curs ;
    isi_rms = (   1     / 2) * isi_rms;
    xt_rms  = (   1     / 2) * xt_rms ;
end

% Combine all noise sources
n_total = norm([isi_rms xt_rms NoiseRMS]);

% SNR calculation
SNRdB = 10*log10((v_curs^2) / (n_total^2));
end