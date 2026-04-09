function TapWeights = adaptFFE(waveIn,SamplesPerSymbol,SampleInterval,cmx,cpx,bmax)
%ADAPTFFE Adapt FFE taps based on an input impulse response
% Adapt FFE taps such that the convolution of FFE taps and pulse response 
% results in minimum ISI in the root-mean squared sense.
% Determines the required FFE tap weights needed to cancel out ISI at the
% the UI sample points.  Function is DFE aware, where it will NOT zero force
% 1st post-cursor ISI if a DFE is present. The resulting FFE will have
% cmx + 1 + cpx taps.
%   Inputs:
%       waveIn - Input impulse response to be equalized by the Rx FFE
%       SamplesPerSymbol - the number of samples per each symbol UI used for waveIn
%       SampleInterval - the simulation time step size
%       cmx - number of pre-cursor FFE taps
%       cpx - number of post-cursor FFE taps
%       bmax - the maximum value of 1-tap DFE that follows FFE, if DFE isn't present
%              then this should be set to zero
%   Output:
%       TapWeights       - Adapted tap weights
%
% The required FFE taps are calculated as follows
% 1. To make the adaptation somewhat CDR implementation independent, the peak
%    input pulse amplitude is assumed to be the UI center sampling point.
% 2. The input pulse response is sampled, once per UI, relative to the
%    determined sampling point.
% 3. A circularly shifted matrix (VV) is constructed based on the sampled input
%    pulse response.  It is then trimmed such that the top first row starts at
%    the cursor.  This implmentation follows COM script implementation.
% 4. The target pulse response vector (FV) is constructed.  This vector is an
%    all zero matrix, other than at the cursor position (cmx+1), where the
%    current cursor value is used.
% 5. If bmax is non-zero, then the target for the 1st post-cursor is set to the
%    minimum of the current post-cursor value or bmax scaled by the cursor
%    amplitude.
% 6. The tap weights are calcuated as the pseudo inverse of the VV matrix
%    multiplied by the desired pulse target (FV).

%   Copyright 2020 The MathWorks, Inc.

%Validate inputs
validateattributes(waveIn,{'numeric'},{'vector','finite'},'adaptFFE','waveIn',1);
validateattributes(SamplesPerSymbol,{'numeric'},...
    {'scalar','finite','integer','positive'},...
    'adaptFFE','SamplesPerSymbol',2);
validateattributes(SampleInterval,{'numeric'},...
    {'scalar','finite','positive','real'},...
    'adaptFFE','SampleInterval',3);
validateattributes(cmx,{'numeric'},...
    {'scalar','finite','integer','nonnegative'},...
    'adaptFFE','cmx',4);
validateattributes(cpx,{'numeric'},...
    {'scalar','finite','integer','nonnegative'},...
    'adaptFFE','cpx',5);


% Calculate pulse response
pulseIn = impulse2pulse(waveIn(:), SamplesPerSymbol, SampleInterval);

% Peak amplitude phase detection
[~, pulseMaxPt] = max(pulseIn);

% Sampling phase
samplePhase = mod(pulseMaxPt - 1, SamplesPerSymbol) + 1;

% Re-sample the pulse at UI centers
sampledPulseIn = pulseIn(samplePhase:SamplesPerSymbol:end);

% Construct the adaptation matrix: shifted versions of the sampled waveform
VV = convmtx(sampledPulseIn, cmx+cpx+1)';

% Find cursor in the sampled waveform
[sampledPulseMax, sampledPulseMaxPt] = max(sampledPulseIn);

% Trim the adaptation matrix to include pre- to post-cursor range
VV = VV(:, sampledPulseMaxPt : sampledPulseMaxPt + cmx + cpx);

% Construct adaptation target pulse, FV
FV = zeros(1, cmx + 1 + cpx);
FV(cmx + 1) = sampledPulseMax;

% Adjust adaptation target pulse: DFE takes precedence for 1st post-cursor
if (bmax > 0) && (cpx > 0) 
    FV(cmx+2) = min(bmax * sampledPulseMax, sampledPulseIn(sampledPulseMaxPt + 1));
end

% Calculate FFE tap weights: pseudo inverse of the adaptation matrix
[i_m, i_n] = size(VV);
I_VV = eye(i_m, i_n);
lambda = 0;
C = ((VV' * VV + lambda*I_VV)^-1 * VV')' * FV';

% Assign output
TapWeights = C';
  
end