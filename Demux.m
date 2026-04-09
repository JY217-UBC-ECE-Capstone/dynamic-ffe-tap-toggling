classdef (StrictDefaults) Demux < serdes.SerdesAbstractSystemObject & TriggeredComponent
    % Demux     Demultiplexer
    %   obj = Demux returns a System Object, obj, that distributes the
    %   incoming sampled data to serveral outputs.
    %
    % Demux methods:
    %   step -  Distributes the incoming sampled data to several outputs
    %           using the digital clock input to determine when to update
    %           the outputs.
    %           [SampleOut,ClockOut] = step(obj,SampleIn,ClockIn)
    %
    % Demux properties:
    %   DemuxWidth     - Width of the output signal
    %   NumberOfClocks - Width of the input signal
    %   SymbolTime     - Symbol time of system
    %   SampleInterval - Uniform time step of the system

    %   Copyright 2021 The MathWorks, Inc.

    %#codegen

    properties (Nontunable)

        %Demux Width
        DemuxWidth = 32;

        %ADC Depth
        NumberOfClocks = 4;
    end
    properties (Hidden, SetAccess=private)
        %demux properties
        SampleBuffer        % Demux buffer
        SampleOutInternal   % Demux output
        DemuxChannelIndex   % Demux channel index
        ClockOutInternal    % Output clock
        OutputClockCounter  % Output clock counter
        ClockHalfPeriod     % Output clock half period, samples
        StartUpSyncFlag     % Flag to align with 0 degree phase at start up
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
        function obj = Demux(varargin)
            % Support name-value pair arguments when constructing object
            obj.BlockName = 'Demux';
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

            setupClock(obj)

            % Demux-specific properties
            obj.SampleBuffer        = zeros(obj.DemuxWidth, 1);
            obj.SampleOutInternal   = zeros(obj.DemuxWidth, 1);
            obj.DemuxChannelIndex   =  1;
            obj.OutputClockCounter  =  0;
            obj.ClockOutInternal    = -1;
            obj.StartUpSyncFlag     = false;

            % Output clock half period, samples
            SamplesPerSymbol    = round(obj.SymbolTime/obj.SampleInterval);
            obj.ClockHalfPeriod = (SamplesPerSymbol * obj.DemuxWidth) / 2;
        end

        function validateInputsImpl(~,waveIn)
            validateattributes(waveIn,{'numeric'},{'finite'},'','waveIn');
        end

        function [SampleOut,ClockOut] = stepImpl(obj,SampleIn,varargin)
            %[SampleOut,ClockOut] = stepImpl(obj,SampleIn,ClockIn)

            if nargin==3
                ClockIn = varargin{1};
            else
                ClockIn = 0;
            end


            if isSample(obj)
                ClockStep(obj,ClockIn)

                % On clock rising edge
                if obj.PhaseRisingIndex > 0

                    % If demux is not sync'ed up then sync it to the first rising
                    % edge of 0 deg input clock phase
                    if (~obj.StartUpSyncFlag) && (obj.PhaseRisingIndex == 1)
                        obj.StartUpSyncFlag = true;
                    end

                    % If demux is sync'ed up
                    if obj.StartUpSyncFlag

                        % Before populating first demux position
                        if obj.DemuxChannelIndex == 1

                            % Release buffer to output
                            obj.SampleOutInternal = obj.SampleBuffer;

                            % Set output clock to +1; reset clock counter
                            obj.ClockOutInternal = +1;
                            obj.OutputClockCounter   =  0;

                        end % obj.DemuxChannelIndex == 1

                        % Place input sample corresponding to the phase with rising
                        % clock edge into the next position of the output buffer
                        obj.SampleBuffer(obj.DemuxChannelIndex) = SampleIn(obj.PhaseRisingIndex);

                        % Update output buffer pointer
                        obj.DemuxChannelIndex = mod(obj.DemuxChannelIndex, obj.DemuxWidth) + 1;

                    end % obj.StartUpSyncFlag

                end % obj.PhaseRisingIndex > 0

                % Increment output clock counter
                obj.OutputClockCounter = obj.OutputClockCounter + 1;

                % After half period, set output clock to -1
                if obj.OutputClockCounter > obj.ClockHalfPeriod
                    obj.ClockOutInternal = -1;
                end

                % Assign outputs
                SampleOut  = obj.SampleOutInternal;
                ClockOut = obj.ClockOutInternal;
            else
                % Assign outputs
                SampleOut  = SampleIn;
                ClockOut = 0;
            end

        end
        function [sz_1,sz_2] = getOutputSizeImpl(obj)
            % Return size for each output port
            sz_1 = [obj.DemuxWidth 1];
            sz_2 = [1 1];
        end
        function [c1,c2] = isOutputFixedSizeImpl(~)
            c1 = true;
            c2 = true;
        end
        function [dt1,dt2] = getOutputDataTypeImpl(obj)
            dt1 = propagatedInputDataType(obj,1);
            dt2 = propagatedInputDataType(obj,1);
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
            icon = "Demux";
        end
        function [name1,name2] = getInputNamesImpl(~)
            name1 = 'Samples';
            name2 = 'Clock';
        end
        function [name1,name2] = getOutputNamesImpl(~)
            name1 = 'Samples';
            name2 = sprintf('Demux\nClock');
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
                'PropertyList',{'DemuxWidth','NumberOfClocks',...
                'SymbolTime','SampleInterval'});            
        end
    end
end