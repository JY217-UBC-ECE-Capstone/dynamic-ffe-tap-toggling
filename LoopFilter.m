classdef (StrictDefaults) LoopFilter < serdes.SerdesAbstractSystemObject & TriggeredComponent
    % LoopFilter    Loop Filter
    %   obj = LoopFilter returns a System Object, obj, that integrates the
    %   input Up/Down signal and increments or decrements the output phase
    %   control signal.
    %
    % LoopFilter methods:
    %   step - Integrates the input Up/Down phase detector signal and
    %   increments or decrements the output phase control signal when the
    %   sum exceeds some limit.  The useage is:
    %   PhaseControl = step(obj,ClockIn,UpDown)
    %
    % LoopFilter properties:
    %   ProportionalGain - Proportional gain.  Typically set to 1/timeInterleaveDepth
    %   PhaseStep        - Step size for phase increment or decrement
    %   UpDownMaxLimit   - Up/down counter limit

    %   Copyright 2021 The MathWorks, Inc.

    %#codegen

    properties (Nontunable)

        % Proportional gain
        %   Typically set to 1/timeInterleaveDepth
        ProportionalGain =  1.0;

        % Step size for phase increment/decrement
        PhaseStep = 1/128;

        % Up/down counter limit
        UpDownMaxLimit = 16;
    end
    properties (Hidden, SetAccess=private)
        PhaseControlInternal % Phase control output
        UpDownSum            % Accumulated up/down pulses (sum)
        UpDownLimit          % Current limit of up/down sum
        PhaseChange          % Phase increment/decrement
    end
    properties(Hidden,Nontunable)
        %Required by abstract class but not used
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
        function obj = LoopFilter(varargin)
            % Support name-value pair arguments when constructing object
            obj.BlockName = 'LoopFilter';
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

            % Initialize phase error output
            obj.PhaseControlInternal = 0.0;

            % Initialize filter properties
            obj.UpDownSum   =  0.0;
            obj.UpDownLimit =  0.0;
            obj.PhaseChange =  0.0;
        end

        function validateInputsImpl(~,waveIn)
            validateattributes(waveIn,{'numeric'},{'finite'},'','waveIn');
        end

        function PhaseControl = stepImpl(obj,ClockIn,UpDown)
            %PhaseControl = stepImpl(obj,ClockIn,UpDown)

            if isSample(obj)
                %Triggered clock step
                ClockStep(obj,ClockIn)

                % On falling clock edge, filter the incoming phase error
                if obj.PhaseFallingIndex > 0

                    % Reset phase increment/decrement
                    obj.PhaseChange = 0.0;

                    % Update up/down accumulator
                    obj.UpDownSum = obj.UpDownSum + UpDown;

                    % Up/down sum exceed current limit (positive or negative side)
                    if abs(obj.UpDownSum) >= obj.UpDownLimit

                        % Set phase increment/decrement
                        obj.PhaseChange = sign(obj.UpDownSum) * obj.PhaseStep;

                        % Reset up/down accumulator
                        obj.UpDownSum = 0;

                        % Ramp up up/down limit at start up
                        if obj.UpDownLimit >= obj.UpDownMaxLimit
                            obj.UpDownLimit = obj.UpDownMaxLimit;
                        else
                            obj.UpDownLimit = obj.UpDownLimit + 1;
                        end

                    end

                    % Update phase control
                    obj.PhaseControlInternal = obj.PhaseControlInternal + obj.ProportionalGain * obj.PhaseChange;

                end % obj.PhaseFallingIndex > 0
            end

            % Assign output
            PhaseControl = obj.PhaseControlInternal;
        end

        function resetImpl(~)
            % Initialize / reset discrete-state properties
        end

        %% Simulink functions
        function icon = getIconImpl(~)
            % Define icon for System block
            icon = "Loop\nFilter";
        end
        function [name1,name2] = getInputNamesImpl(~)
            name1 = sprintf('Demux\nClock');
            name2 = 'UpDown';
        end
        function name1 = getOutputNamesImpl(~)
            name1 = sprintf('Phase\nControl');
        end
    end
    methods(Static, Access=protected)
        function group = getPropertyGroupsImpl(~)
            % Define property section(s) for System block dialog
            group = matlab.system.display.SectionGroup(...
                'Title','Main',...
                'PropertyList',{'ProportionalGain','PhaseStep',...
                'UpDownMaxLimit'});
        end
    end
end
