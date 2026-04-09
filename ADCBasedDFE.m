classdef (StrictDefaults) ADCBasedDFE < serdes.SerdesAbstractSystemObject & TriggeredComponent
    % ADCBasedDFE   ADC-based Decision Feedback Equalizer
    %   obj = ADCBasedDFE returns a System Object, obj, that applies a
    %   single-tap decision-feedback equalization to the input samples as
    %   well as makes data decisions and calculates the signal-to-noise
    %   ratio.
    %
    % ADCBasedDFE methods:
    %   step - Equalizes the demuxed input samples accordingly to a
    %          single-tap DFE. Data symbol decisions are made,
    %          signal-to-noise ratio calculated and PAM thresholds
    %          determined. The following is an example of the inputs and
    %          outputs of the method:
    %          [SampleOut,DecisionOut,SNR,TapOut,PAMThresholdn1,...
    %          PAMThreshold0,PAMThreshold1] = stepImpl(obj,SampleIn,ClockIn)
    %
    % ADCBasedDFE properties
    %   Mode           - DFE Mode, 0=off, 1=fixed, 2=adapt in Init
    %   DemuxWidth     - Width of the input samples
    %   TapWeight     -
    %   TapWeightPort -
    %   SymbolTime     - Symbol time of system
    %   Modulation     - Modulation scheme: 2=NRZ, 4=PAM4
    %   SampleInterval - Uniform time step of the system

    %   Copyright 2021-2024 The MathWorks, Inc.

    %#codegen

    properties (Nontunable)

        %Mode Mode (0: Pass through, 1:Fixed, 2:Adapt)
        %   When set to 2, adaptation occurs in impulse-based analysis only
        Mode       =  2;

        %Demux word size
        DemuxWidth = 32;
    end
    properties (Hidden, SetAccess=private)

        %ADCBasedDFE properties
        DataInternal        % Internal slicing decisions, Data internal
        DataOut             % Output decisions
        SampleOut           % Output samples
        SignalLevels        % Expected signal levels
        DecisionSymbols     % Decision symbol levels
        AbsoluteSample      % Absolute value of current sample
        AbsoluteEyeHeight   % Absolute average eye height
        AveragingWindow     % threshold recovery average window
        SignalNoiseRatio    % SNR
        SignalBuffer        % signal buffer for SNR calculations
        SignalEstimate      % Signal energy used for SNR calculations
        NoiseEstimate       % Noise energy used for SNR calculations
        PAMThresholds;      % PAM Thresholds

        buf_size = 512;     % Signal buffer size for SNR calculation
    end
    properties(Hidden,Nontunable)
        NumberOfClocks = 1;
    end
    properties

        %Tap Weight
        TapWeight = 0;
    end

    properties(Nontunable) %port/property duality
        %TapWeightPort TapWeightPort
        %   Specify TapWeight from input port in Simulink
        TapWeightPort (1, 1) logical = true;
    end

    properties (Constant, Hidden) %port/property duality
        TapWeightSet = matlab.system.SourceSet(...
            {'PropertyOrInput', 'SystemBlock', 'TapWeightPort', 1, 'TapWeight'}, ...
            {'Property', 'MATLAB', 'TapWeightPort'});
    end

    properties (SetAccess = immutable, Nontunable, Hidden)
        IsLinear = true;
        IsTimeInvariant = true;
    end
    properties (Nontunable,Hidden)
        %Input Waveform Type
        %   Set the input wave type as one of 'Sample' | 'Impulse' |
        %   'Waveform'.  The default is 'Sample'.
        WaveType = 'Sample';
    end
    properties(Hidden, Constant)
        WaveTypeSet = matlab.system.StringSet({'Sample','Impulse','Waveform'});
    end
    methods
        % Constructor
        function obj = ADCBasedDFE(varargin)
            % Support name-value pair arguments when constructing object
            obj.BlockName = 'ADCBasedDFE';
            setProperties(obj,nargin,varargin{:})
        end
    end
    methods (Hidden)
        % The below methods, getAMIParameters, getAMIInputNames and
        % getAMIOutputNames are for use only within the serdesDesigner App
        % and will not influence the AMI parameters in Simulink whatsoever.
        function amiParameters = getAMIParameters(~)
            amiParameters = {};
        end
        function names = getAMIInputNames(~)
            names = {};
        end
        function names = getAMIOutputNames(~)
            names = {};
        end
    end
    methods (Access = protected, Hidden)
        function val = isSample(obj)
            val = strcmpi(obj.WaveType,'Sample');
        end
        function val = isImpulse(obj)
            val = strcmpi(obj.WaveType,'Impulse');
        end
        function val = ModeIsOff(obj)
            val = obj.Mode==double(0);
        end
        function val = ModeIsFixed(obj)
            val = obj.Mode==double(1);
        end
        function val = ModeIsAdapt(obj)
            val = obj.Mode==double(2);
        end
    end
    methods(Access = protected)
        %% Common functions
        function setupImpl(obj)

            setupClock(obj)

            % Initialize signal and decision levels and SNR buffers
            % Slicer thereshold will be between expected signal levels
            obj.SignalNoiseRatio = NaN;
            obj.SignalEstimate = 0;
            obj.NoiseEstimate = inf;
            if obj.Modulation ==4 % PAM4
                obj.SignalLevels = [-0.5, -0.5/3, 0.5/3, 0.5];
                obj.DecisionSymbols = [-0.5, -0.5/3, 0.5/3, 0.5];
                obj.AbsoluteEyeHeight = 0.5*2/3;
                obj.SignalBuffer = nan(obj.buf_size, 2);
                obj.PAMThresholds = [-1/3 0 1/3];
            else %if obj.Modulation == 2 % NRZ
                obj.SignalLevels   = [-0.5, 0.5 0 0];    % NRZ signal levels
                obj.DecisionSymbols   = [-0.5, 0.5 0 0]; % NRZ decision output levels
                obj.AbsoluteEyeHeight = 0.5;
                obj.SignalBuffer = nan(obj.buf_size, 1);
                obj.PAMThresholds = [0 0 0];
            end

            obj.AveragingWindow = 1024; % Average window for signal detection
            obj.AbsoluteSample = 0.0;

            % Initialize output decisions and samples
            obj.DataInternal = zeros(obj.DemuxWidth+1, 1);  %data internal
            obj.DataOut = zeros(obj.DemuxWidth, 1);
            obj.SampleOut = zeros(obj.DemuxWidth, 1);

        end

        function validateInputsImpl(~,waveIn)
            validateattributes(waveIn,{'numeric'},{'finite'},'','waveIn');
        end

        function [SampleOut,DecisionOut,SNR,TapOut,PAMThresholdn1,...
                PAMThreshold0,PAMThreshold1] = stepImpl(obj,SampleIn,DLEVs,ClockIn)

            if isImpulse(obj)
                %1) convert to pulse
                %2) mueller-muller CDR
                %3) determine DFE tap
                %4) apply DFE
                %5) prep outputs, output tap

                %Convert to pulse
                SamplesPerSymbol = round(obj.SymbolTime/obj.SampleInterval);
                pulse = impulse2pulse(SampleIn(:,1), SamplesPerSymbol, obj.SampleInterval);
                pulseLength = length(pulse);

                %Determine sampling time with hula hoop algorithm
                nclock = round(pulseRecoverClock( pulse, SamplesPerSymbol*2 ))-1;


                %Estimate tap from pulse response
                if ModeIsAdapt(obj)
                    for kk = 1: length(obj.TapWeight)
                        %Determine Tap values
                        obj.TapWeight(kk) = pulse(mod(nclock+kk*SamplesPerSymbol-1,pulseLength)+1);
                    end
                end

                %Apply tap to impulse (not to crosstalk)
                if ~ModeIsOff(obj)
                    for kk = 1: length(obj.TapWeight)
                        ndx = mod(nclock+kk*SamplesPerSymbol - SamplesPerSymbol/2 -1,pulseLength)+1;
                        SampleIn(ndx,1) = SampleIn(ndx,1) + obj.TapWeight(kk)/obj.SampleInterval;
                    end
                end

                % Assign outputs
                SampleOut = SampleIn;
                DecisionOut = NaN;
                SNR = -Inf;

                obj.PAMThresholds = (-(obj.Modulation-2)/2:(obj.Modulation-2)/2) * pulse(nclock)/(obj.Modulation-1);
            else %if isSample(obj)
                ClockStep(obj,ClockIn)

                % On falling clock edge, process frame of samples
                if obj.PhaseFallingIndex > 0

                    obj.SignalLevels = DLEVs;

                    % move last decision to be first decision for next iteration
                    obj.DataInternal(1) = obj.DataInternal(end);

                    % Apply DFE contribution, feedback based on tap-weight, if Mode=1
                    for ii = 1 : obj.DemuxWidth
                        if obj.Mode ~= 0
                            % Apply DFE contribution
                            obj.SampleOut(ii) = SampleIn(ii) - obj.TapWeight(1) * obj.DataInternal(ii);
                        else % Samples are unchanged
                            obj.SampleOut(ii) = SampleIn(ii);
                        end

                        % Slice the signal, by picking the signal level that has
                        % smallest euclidian distance to current signal levels
                        [~, didx] = min(abs(obj.SampleOut(ii) - obj.SignalLevels));
                        % output decision is corresponding output signal level
                        obj.DataInternal(ii+1) = obj.DecisionSymbols(didx);

                        % Sample-by-sample threshoddld recovery, assume symmetry between +/-
                        obj.AbsoluteSample = abs(obj.SampleOut(ii));

                        % Running Average for eye height
                        obj.AbsoluteEyeHeight = obj.AbsoluteEyeHeight + (abs(obj.SampleOut(ii)) - obj.AbsoluteEyeHeight)/obj.AveragingWindow/2;

                        if obj.Modulation == 4
                            if obj.AbsoluteSample > obj.AbsoluteEyeHeight
                                % Add signal to SNR buffer
                                obj.SignalBuffer(:, 2) = circshift(obj.SignalBuffer(:, 2), 1);
                                obj.SignalBuffer(1, 2) = obj.AbsoluteSample;
                            elseif obj.AbsoluteSample < obj.AbsoluteEyeHeight
                                % Add signal to SNR buffer
                                obj.SignalBuffer(:, 1) = circshift(obj.SignalBuffer(:, 1), 1);
                                obj.SignalBuffer(1, 1) = obj.AbsoluteSample;
                            end
                            %Calculate PAM4 thresholds
                            obj.PAMThresholds = (obj.SignalLevels(1:end-1)+obj.SignalLevels(2:end))/2;

                        elseif obj.Modulation ==2
                            % Add signal to SNR buffer
                            obj.SignalBuffer    = circshift(obj.SignalBuffer, 1);
                            obj.SignalBuffer(1) = obj.AbsoluteSample;

                            %Calculate PAM Threshold
                            obj.PAMThresholds(2) = (obj.SignalLevels(1)+obj.SignalLevels(2))/2;
                        else
                            error('nope')
                        end

                    end % for ii = 1 : obj.DemuxWidth + 1

                end % obj.PhaseFallingIndex > 0

                % Calculate SNR value
                if obj.Modulation == 4

                    %Mean of signal levels
                    u1 = mean(obj.SignalBuffer(:,1));
                    u2 = mean(obj.SignalBuffer(:,2));

                    obj.SignalEstimate   = (u1^2 + u2^2)/2;
                    obj.NoiseEstimate = mean([ obj.SignalBuffer(:,2) - u2;...
                        obj.SignalBuffer(:,1) - u1].^2);
                else
                    %Signal mean
                    u = mean(obj.SignalBuffer);

                    obj.SignalEstimate =   u^2;
                    obj.NoiseEstimate = mean( (obj.SignalBuffer(:,1) - u).^2 );
                end
                obj.SignalNoiseRatio = 10*log10(obj.SignalEstimate/obj.NoiseEstimate);

                % Assign outputs
                obj.DataOut = obj.DataInternal(2:obj.DemuxWidth + 1);
                SampleOut = obj.SampleOut(1:obj.DemuxWidth);
                DecisionOut = obj.DataOut(1:obj.DemuxWidth);

                if isnan(obj.SignalNoiseRatio(1))
                    SNR = -1;
                else
                    SNR = obj.SignalNoiseRatio(1);
                end
            end
            TapOut = obj.TapWeight(1);
            PAMThresholdn1 = obj.PAMThresholds(1);
            PAMThreshold0 = obj.PAMThresholds(2);
            PAMThreshold1 = obj.PAMThresholds(3);
        end
        function [sz_1,sz_2,sz_3,sz_4,sz_5,sz_6,sz_7] = getOutputSizeImpl(obj)
            % Return size for each output port
            sz_1 = [obj.DemuxWidth 1];
            sz_2 = [obj.DemuxWidth 1];
            sz_3 = [1 1];
            sz_4 = [1 1];
            sz_5 = [1 1];
            sz_6 = [1 1];
            sz_7 = [1 1];
        end
        function [c1,c2,c3,c4,c5,c6,c7] = isOutputFixedSizeImpl(~)
            c1 = true;
            c2 = true;
            c3 = true;
            c4 = true;
            c5 = true;
            c6 = true;
            c7 = true;
        end
        function [dt1,dt2,dt3,dt4,dt5,dt6,dt7] = getOutputDataTypeImpl(obj)
            dt1 = propagatedInputDataType(obj,1);
            dt2 = dt1;
            dt3 = dt1;
            dt4 = dt1;
            dt5 = dt1;
            dt6 = dt1;
            dt7 = dt1;
        end
        function [c1,c2,c3,c4,c5,c6,c7] = isOutputComplexImpl(~)
            c1 = false;
            c2 = false;
            c3 = false;
            c4 = false;
            c5 = false;
            c6 = false;
            c7 = false;
        end

        function resetImpl(~)
            % Initialize / reset discrete-state properties
        end

        %% Simulink functions
        function icon = getIconImpl(~)
            % Define icon for System block
            icon = sprintf('ADC\nBased\nDFE');
        end
        function [name1,name2,name3,name4] = getInputNamesImpl(~)
            name1 = 'Sample';
            name2 = 'DLEVs';
            name3 = sprintf('Demux\nClock');
            name4 = 'Tap';
        end
        function [name1,name2,name3,name4,name5,name6,name7] = getOutputNamesImpl(~)
            name1 = 'Sample';
            name2 = 'Decision';
            name3 = 'SNR';
            name4 = 'Tap';
            name5 = 'ThresholdLower';
            name6 = 'ThresholdCenter';
            name7 = 'ThresholdUpper';
        end
        function num = getNumInputsImpl(obj)
            if isSample(obj)
                num = 3;
            else
                num = 1;
            end
        end
    end

end