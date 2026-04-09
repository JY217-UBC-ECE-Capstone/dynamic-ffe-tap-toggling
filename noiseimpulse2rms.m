function [RMS] = noiseimpulse2rms(IR,PSD,BW,DT)
%NOISEIMPULSE2RMS Noise Impulse response to output-referred RMS value
%   Convert impulse response of noise path filters to output-referred RMS value.
%
% The equivalent RMS output noise power is calculated by
% 1. Converting the time-domain noise impulse response into a frequency-domain
%    noise transfer function
% 2. Integrating the squared noise transfer function up to the noise
%    integration bandwidth.
% 3. Scaling the input noise by the input noise PSD
% 4. Returning the square-root of the result.
%
%   Inputs:
%       IR  - Noise impulse response
%       PSD - Noise power spectral density (PSD) in units of V^2/GHz
%       BW  - Noise integration bandwidth in Hz
%       DT  - Sampling interval in seconds
%
%   Outputs:
%       rms - Noise RMS value in V

%   Copyright 2020 The MathWorks, Inc.

%Validate inputs
validateattributes(IR,{'numeric'},{'vector','finite'},'NoiseIR2RMS','ir',1);
validateattributes(PSD,{'numeric'},{'scalar','nonnegative'},'NoiseIR2RMS','psd',2);
validateattributes(BW,{'numeric'},{'scalar','positive'},'NoiseIR2RMS','bw',3);
validateattributes(DT,{'numeric'},{'scalar','positive'},'NoiseIR2RMS','dt',4);

% Convert noise impulse response (IR) to transfer function (TF)
tf = fft(IR);

% Number of points in IR and TF
num_pts = length(IR);

% Frequency step
df = (1 / DT) / num_pts;

% Noise integration index, keep it below half of FFT frequency range
i_bw = min(round(BW / df), num_pts/2 );

% To calculate noise RMS
% 1. Take magnitude of noise TF
% 2. Square noise TF magnitude
% 3. Integrate over noise BW (convert frequency step, df, to GHz)
% 4. Scale by input noise PSD in V^2/GHz
% 5. Take square root 
RMS = sqrt(PSD * sum((df/1e9) * abs(tf(1:i_bw)).^2));
end