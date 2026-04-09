classdef (StrictDefaults) TimeInterleavedADC < serdes.SerdesAbstractSystemObject & TriggeredComponent
    % TimeInterleavedADC     Time Interleaved Analog-to-Digital Converter
    %   obj = TimeInterleavedADC returns a System Object, obj, that samples
    %   the input waveform by a bank of ADCs so as to relax the sample
    %   capture timing requirements for faster data rates.
    %
    % TimeInterleavedADC methods:
    %   step - Samples the waveform by a set of ADCs according to the analog
    %          clock inputs. The object returns a vector of output samples
    %          and a digital version of the clock as follows:
    %          [SampleOut,ClockDigital] = step(obj,WaveIn,ClockAnalog)
    %
    % TimeInterleavedADC properties:
    %   DynamicRange   - Peak dynamic range of each ADC in volts.
    %   Resolution     - Nominal resolution of each ADC in bits.
    %   NumberOfClocks - Number of clocks or number of ADCs in the system.
    %                    This value must be coordinated with the size of
    %                    the input analog clock.
    %   SampleInterval - Uniform time step of the waveform.

    %   Copyright 2021 The MathWorks, Inc.

    %#codegen

    properties (Nontunable)

        % Dynamic range (V peak)
        DynamicRange  = inf;

        % Nominal resolution (bits)
        Resolution =   inf;

        %Number of ADCs
        NumberOfClocks = 4;
    end

    properties (Hidden, SetAccess=private)

        %ADC properties
        InputPrevious        % Previous input
        InputCurrent         % Current  input
        Buffer               % Buffered samples
        SampleOut            % Output   samples
        ClockDigitalInternal % Output   clock
        PhaseReleaseIndex;   % Clock phase to release sample from buffer to output
        LSB                  % Least Significant Bit (LSB) size, V
    end
    properties (Nontunable,Hidden)
        %Input Waveform Type
        %   Set the input wave type as one of 'Sample' | 'Impulse' |
        %   'Waveform'.  The default is 'Sample'.
        WaveType = 'Sample';
    end

    properties (SetAccess = immutable, Nontunable, Hidden)
        IsLinear = true;
        IsTimeInvariant = true;
    end

    properties(Hidden, Constant)
        WaveTypeSet = matlab.system.StringSet({'Sample','Impulse','Waveform'});
    end

    methods
        % Constructor
        function obj = TimeInterleavedADC(varargin)
            % Support name-value pair arguments when constructing object
            obj.BlockName = 'TimeInterleavedADC';
            setProperties(obj,nargin,varargin{:})
        end
    end
    methods (Hidden)
        % The below methods, getAMIParameters, getAMIInputNames and
        % getAMIOutputNames are for use only within the serdesDesigner App
        % and will not influence the AMI parameters in Simulink whatsoever.
        % They are required by the serdes.SerdesAbstractSystemObject.
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
    end
    methods(Access = protected)
        %% Common functions
        function setupImpl(obj)

            setupClock(obj)

            % Calculate LSB size
            if isinf(obj.Resolution)
                obj.LSB = 0;
            else
                obj.LSB = 2 * obj.DynamicRange / (2^obj.Resolution - 1);
            end

            % Initialize buffers and indexes
            obj.InputPrevious   = 0;
            obj.InputCurrent    = 0;
            obj.PhaseReleaseIndex = 2;

            % Initialize sample buffer to zero
            obj.Buffer = zeros(obj.NumberOfClocks, 1);

            % Initialize sample output to half LSB
            obj.SampleOut = (obj.LSB/2) * ones(obj.NumberOfClocks, 1);

            % Initialize clock output to -1
            obj.ClockDigitalInternal = -ones(obj.NumberOfClocks, 1);
        end

        function validateInputsImpl(~,waveIn)
            validateattributes(waveIn,{'numeric'},{'finite'},'','waveIn');
        end

        function [SampleOut,ClockDigital] = stepImpl(obj,WaveIn,varargin)
            %[SampleOut,ClockDigital] = stepImpl(obj,WaveIn,ClockAnalog)

            if nargin == 3
                ClockAnalog = varargin{1};
            else
                ClockAnalog = 0;
            end

            if isSample(obj)

                ClockStep(obj,ClockAnalog)

                % Update buffers
                obj.InputPrevious  = obj.InputCurrent ;
                obj.InputCurrent   = WaveIn      ;

                % On rising clock edge, trigger corresponding ADC
                if obj.PhaseRisingIndex > 0

                    % Get buffer release phase (phase after current rising edge phase)
                    obj.PhaseReleaseIndex  = mod(obj.PhaseRisingIndex, obj.NumberOfClocks) + 1;

                    % Interpolation index from clock waveform (fraction of UI)
                    mu = obj.ClockPrevious(obj.PhaseRisingIndex) / (obj.ClockPrevious(obj.PhaseRisingIndex) - obj.ClockCurrent(obj.PhaseRisingIndex));

                    % Interpolate sample at clock zero-crossing
                    VoltageAtClock = (1 - mu) * obj.InputPrevious + mu * obj.InputCurrent;

                    %Inject input offset voltage and Gain offset here.
                    %Bandwidth offset would require N filters applied to
                    %InputCurrent (and InputPrevious) and then index the
                    %correct waveform here.

                    %Place sample into buffer
                    obj.Buffer(obj.PhaseRisingIndex) = VoltageAtClock;

                    % Quantize and release buffer to output for the next clock phase
                    obj.SampleOut(obj.PhaseReleaseIndex) = obj.quant(obj.Buffer(obj.PhaseReleaseIndex));

                end % obj.PhaseRisingIndex > 0

                % Output clock is a square wave +1/-1, avoids 0 values
                obj.ClockDigitalInternal = sign(ClockAnalog - eps);

                % Assign outputs
                SampleOut  = obj.SampleOut ;
                ClockDigital = obj.ClockDigitalInternal;
            else
                % Assign outputs
                SampleOut  = WaveIn;
                ClockDigital = 0;
            end

        end
        function [sz_1,sz_2] = getOutputSizeImpl(obj)
            % Return size for each output port
            sz_1 = [obj.NumberOfClocks 1];
            sz_2 = [obj.NumberOfClocks 1];
        end
        function [c1,c2] = isOutputFixedSizeImpl(~)
            c1 = true;
            c2 = true;
        end
        function [dt1,dt2] = getOutputDataTypeImpl(obj)
            dt1 = propagatedInputDataType(obj,1);
            dt2 = propagatedInputDataType(obj,2);
        end
        function [c1,c2] = isOutputComplexImpl(~)
            c1 = false;
            c2 = false;
        end
        function resetImpl(~)
            % Initialize / reset discrete-state properties
        end

        %% Simulink functions
        function icon = getIconImpl(~)
            % Define icon for System block
            icon = "Time\nInterleaved\nADC";
        end
        function [name1,name2] = getInputNamesImpl(~)
            name1 = 'Wave';
            name2 = sprintf('Analog\nClock');
        end
        function [name1,name2] = getOutputNamesImpl(~)
            name1 = 'Samples';
            name2 = sprintf('Digital\nClock');
        end
        function num = getNumInputsImpl(obj)
            if isSample(obj)
                num = 2;
            else
                num = 1;
            end
        end
        function s_q = quant(obj, s)
            % Quantize a sample

            % Infinite resolution: quantization OFF (bypass mode)
            if isinf(obj.Resolution)

                % 1. clip to +/- dynamic range
                s_q = obj.clip(s);

                % Finite resolution: quantization ON
            else

                % 1. clip to +/- dynamic range
                % 2. shift up by dynamic range
                % 3. scale by 1/LSB
                % 4. quantize
                % 5. scale back by LSB
                % 6. shift down by dynamic range
                s_q = -obj.DynamicRange + obj.LSB * round(     ...
                    (obj.clip(s) + obj.DynamicRange) / obj.LSB);
            end

        end

        function s_lim = clip(obj, s)
            % Clip a sample to +/- dynamic range
            s_lim = max(-obj.DynamicRange, min(obj.DynamicRange, s));
        end
    end
    methods(Static, Access=protected)
        function group = getPropertyGroupsImpl(~)
            % Define property section(s) for System block dialog
            group = matlab.system.display.SectionGroup(...
                'Title','Main',...
                'PropertyList',{'DynamicRange','Resolution','NumberOfClocks',...
                'SampleInterval'});
        end
    end
end
