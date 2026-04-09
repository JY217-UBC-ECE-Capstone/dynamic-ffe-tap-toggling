classdef (StrictDefaults) RxClock < serdes.SerdesAbstractSystemObject
    % RxClock    Receiver clock generator
    %   obj = RxClock returns a System Object, obj, that generates a
    %   multiphase clock.
    %
    % RxClock methods:
    %   step - Generates a multiphase clock.  Example usage:
    %           ClockOut = stepImpl(obj,PhaseControl)
    %
    % RxClock properties:
    %   MaxTimingMismatch - Maximum timing mismatch in UI between the 1st
    %                       and 2nd clock phases.
    %   NumberOfClocks    - Number of output clock phases
    %   SymbolTime        - Symbol time of the system
    %   SampleInterval    - Uniform time step of the system

    %   Copyright 2021 The MathWorks, Inc.

    %#codegen

    properties (Nontunable)

        %Max Timing Mismatch (UI)
        MaxTimingMismatch = 0.0

        %Number of output clock phases
        NumberOfClocks = 4

        %Symbol Time Multiplier Factor
        SymbolTimeMultiplier = 1;
    end
    properties (Hidden, SetAccess=private)
        Frequency       % Clock frequency, Hz
        Period          % Clock period, seconds
        PhaseInitial    % Initial core phase
        PhaseIncrement  % Phase increment per sampling interval
        PhaseCore       % Clock core phase
        PolyPhaseOffset % Array of VCO phase offsets
        PhaseOutput     % Output phases
        ClockRate       % Clock rate w.r.t. baud rate

        InterPhaseOutput
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
        function obj = RxClock(varargin)
            % Support name-value pair arguments when constructing object
            obj.BlockName = 'RxClock';
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

            % Derived parameters
            fb = 1/(obj.SymbolTime*obj.SymbolTimeMultiplier);
            obj.ClockRate = 1/obj.NumberOfClocks;
            obj.Frequency = fb * obj.ClockRate    ;
            obj.Period  = 1 / obj.Frequency         ;
            obj.PhaseIncrement = obj.SampleInterval / obj.Period     ;

            % Multi-phase clock setup, poly phase.  Inject an offset
            % between the 1st and 2nd clocks.            
            v = zeros(obj.NumberOfClocks,1);
            v(1) = obj.MaxTimingMismatch;
            obj.PolyPhaseOffset = (0:-1:-(obj.NumberOfClocks-1))' / obj.NumberOfClocks + ...
                v(mod(0:obj.NumberOfClocks-1,3)+1);

            % Initialize clock core and output phases
            obj.PhaseCore = -obj.PhaseIncrement;
            obj.PhaseOutput  = obj.PhaseCore + obj.PolyPhaseOffset;

            obj.InterPhaseOutput = 0;
        end

        function validateInputsImpl(~,waveIn)
            validateattributes(waveIn,{'numeric'},{'finite'},'','waveIn');
        end

        function [ck_out] = stepImpl(obj,ctrl_ph,initial_ph)
            %ck_out = stepImpl(obj,ctrl_ph)
            %ctrl_ph_const = -0.125;

            if isSample(obj)
                % Update clock core and output phases
                obj.PhaseCore = mod(obj.PhaseCore + obj.PhaseIncrement, 1);
                obj.InterPhaseOutput = obj.PhaseCore - ctrl_ph - initial_ph / obj.Period;
                obj.PhaseOutput  = obj.InterPhaseOutput + obj.PolyPhaseOffset;
            end
            % Update output clock
            ck_out  = sin(2*pi*obj.PhaseOutput);
        end
        function releaseImpl(obj)
            fprintf('[CDR] Phase Offset: %6.32f\n', obj.InterPhaseOutput);
        end
        function [out1] = getOutputSizeImpl(obj)
            % Return size for each output port
            out1 = [obj.NumberOfClocks 1];
        end
        function [dt1] = getOutputDataTypeImpl(~)
            dt1 = "double";
        end

        function [out1] = isOutputComplexImpl(obj)
            % Return true for each output port with complex data
            out1 = false;

            % Example: inherit complexity from first input port
            % out = propagatedInputComplexity(obj,1);
        end

        function [out1] = isOutputFixedSizeImpl(obj)
            % Return true for each output port with fixed size
            out1 = true;

            % Example: inherit fixed-size status from first input port
            % out = propagatedInputFixedSize(obj,1);
        end
        function resetImpl(~)
            % Initialize / reset discrete-state properties
        end

        %% Simulink functions
        function icon = getIconImpl(~)
            % Define icon for System block
            icon = sprintf("Rx\nClock");
        end
        function [name1, name2] = getInputNamesImpl(~)
            name1 = 'Ctrl Ph';
            name2 = 'Initial Ph';
        end
        function [name1] = getOutputNamesImpl(~)
            name1 = 'Clock';
        end
        function num = getNumInputsImpl(~)
            num = 2;
        end
    end
    methods(Static, Access=protected)
        function group = getPropertyGroupsImpl(~)
            % Define property section(s) for System block dialog
            group = matlab.system.display.SectionGroup(...
                'Title','Main',...
                'PropertyList',{'MaxTimingMismatch','NumberOfClocks',...
                'SymbolTime','SymbolTimeMultiplier','SampleInterval'});            
        end
    end    
end
