classdef (StrictDefaults) IBISBridge < serdes.SerdesAbstractSystemObject & TriggeredComponent
    % IBISBridge    IBIS Bridge
    %   obj = IBISBridge returns a System Object, obj, that recombines the
    %   demuxed samples into their original sequence.  Due to the ADC
    %   operation, the resulting waveform contains the same voltage
    %   throughout each unit interval or symbol duration.
    %
    % IBISBridge methods:
    %   step - Recombines the demuxed signals into a single signal as
    %          required by the IBIS-AMI standard.  The clock times are also
    %          processed and prepared for IBIS-AMI model generation.
    %
    % IBISBridge methods:
    %   DemuxWidth     - Width of the output signal
    %   SymbolTime     - Symbol time of system
    %   SampleInterval - Uniform time step of the system

    %   Copyright 2021-2024 The MathWorks, Inc.

    %#codegen

    properties (Nontunable)

        %Demux Width
        DemuxWidth = 32;
    end
    properties (Hidden, SetAccess=private)

        %Bridge properties
        MuxCounter           % Multiplexor counter
        SampleCounter        % Output clock counter
        SamplesPerHalfSymbol % Output clock half period, samples
        ClockOutInternal     % Output clock
        ClockTimesInternal   % Output clock times
        WaveOutInternal      % Wave out internal
        SamplesElapsed = 0;  % Samples Elapsed
        OutputBuffer
    end
    properties(Hidden)
        %Property required by abstract class but unused
        NumberOfClocks = 1;
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
        function obj = IBISBridge(varargin)
            % Support name-value pair arguments when constructing object
            obj.BlockName = 'IBISBridge';
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
    end
    methods(Access = protected)
        %% Common functions
        function setupImpl(obj)
            setupClock(obj);

            % Initialize properties
            obj.MuxCounter = 1;
            obj.SampleCounter  = 0;
            SamplesPerSymbol = round(obj.SymbolTime/obj.SampleInterval);
            obj.SamplesPerHalfSymbol = round(SamplesPerSymbol / 2);
            obj.SamplesElapsed = 0;
            obj.OutputBuffer = zeros(obj.DemuxWidth,1);

            % Initialize outputs to zero
            obj.WaveOutInternal  = 0;
            obj.ClockOutInternal = 0;
            obj.ClockTimesInternal = 0;
        end

        function validateInputsImpl(~,waveIn)
            validateattributes(waveIn,{'numeric'},{'finite'},'','waveIn');
        end

        function [WaveOut,ClockOut,Time] = stepImpl(obj,SampleIn,varargin)
            if nargin==3
                ClockIn = varargin{1};
            else
                ClockIn = 0;
            end

            if isSample(obj)
                % Triggered clock step
                ClockStep(obj,ClockIn)
                % Calculate Clock Time
                SimTime = obj.SamplesElapsed*obj.SampleInterval;
                clock_times = SimTime - obj.SymbolTime/2;
                if clock_times < 0
                    clock_times = 0;
                end
                % Buffer incoming frame upon its transition
                if SampleIn ~= obj.OutputBuffer
                    obj.OutputBuffer = SampleIn;
                    % Force output position to beginning of frame
                    obj.MuxCounter = 1;
                end
                % Update waveform output on the rising edge of any ADC clock(s)
                if any(obj.ClockRisingFlag)
                    obj.WaveOutInternal = obj.OutputBuffer(obj.MuxCounter);
                    if obj.MuxCounter < obj.DemuxWidth
                        obj.MuxCounter = obj.MuxCounter + 1;
                    end
                    % On rising clock edge, set output clock to 0 (edge sample location)
                    obj.ClockOutInternal = 0;
                    % Reset output clock counter
                    obj.SampleCounter = 0;
                end
                % Update output clock counter
                obj.SampleCounter = obj.SampleCounter + 1;
                % After half a UI, set output clock to 1 (data sample location) and update clock
                % times output with current time. Use previous ClockOutInternal to prevent executing
                % more than once per clock period.
                if obj.SampleCounter > obj.SamplesPerHalfSymbol && obj.ClockOutInternal == 0
                    obj.ClockOutInternal = 1;
                    obj.ClockTimesInternal = clock_times;
                end
            else
                obj.WaveOutInternal = SampleIn;
            end
            %Increment count
            obj.SamplesElapsed = obj.SamplesElapsed + 1;
            % Assign outputs
            WaveOut  = obj.WaveOutInternal;
            ClockOut = obj.ClockOutInternal;
            Time = obj.ClockTimesInternal;
        end
        function [sz_1,sz_2,sz_3] = getOutputSizeImpl(~)
            % Return size for each output port
            sz_1 = [1 1];
            sz_2 = [1 1];
            sz_3 = [1 1];
        end
        function [c1,c2,c3] = isOutputFixedSizeImpl(~)
            c1 = true;
            c2 = true;
            c3 = true;
        end
        function [dt1,dt2,dt3] = getOutputDataTypeImpl(obj)
            dt1 = propagatedInputDataType(obj,1);
            dt2 = propagatedInputDataType(obj,2);
            dt3 = "double";
        end
        function [c1,c2,c3] = isOutputComplexImpl(~)
            c1 = false;
            c2 = false;
            c3 = false;
        end
        function resetImpl(~)
            % Initialize / reset discrete-state properties
        end

        %% Simulink functions
        function icon = getIconImpl(~)
            % Define icon for System block
            icon = "IBIS\nBridge";
        end
        function [name1,name2] = getInputNamesImpl(~)
            name1 = 'Samples';
            name2 = 'Clock';
        end
        function [name1,name2,name3] = getOutputNamesImpl(~)
            name1 = 'Wave';
            name2 = 'Clock';
            name3 = 'Time';
        end
        function num = getNumInputsImpl(obj)
            if isSample(obj)
                num = 2;
            else
                num = 1;
            end
        end
    end
    methods(Static, Access=protected)
        function group = getPropertyGroupsImpl(~)
            % Define property section(s) for System block dialog
            group = matlab.system.display.SectionGroup(...
                'Title','Main',...
                'PropertyList',{'DemuxWidth',...
                'SymbolTime','SampleInterval'});
        end
    end
end