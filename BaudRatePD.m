classdef (StrictDefaults) BaudRatePD < serdes.SerdesAbstractSystemObject & TriggeredComponent
    % BaudRatePD     Baud-Rate Phase Detector
    %   obj = BaudRatePD returns a System Object, obj, that performs a
    %   baud-rate or Meuller-Muller phase detection.
    %
    % BaudRatePD methods:
    %   step - Performs a baud-rate phase detection using the demux'ed input
    %          decisions and samples.  An example usage is as follows:
    %          UpDownOut = step(obj,ClockIn,DecisionIn,SampleIn)
    %
    % BaudRatePD properites:
    %   DemuxWidth - Width of input signals

    %   Copyright 2018-2019 The MathWorks, Inc.

    %#codegen

    properties (Nontunable)

        %Demux Width
        DemuxWidth = 32;
    end
    properties (Hidden, SetAccess=private)
        SamplePrevious      % Last sample   from previous frame
        DecisionPrevious    % Last decision from previous frame
        TimingFunctionValue % Timing function value
        SymmetricTransition % Symmetric transition indicator
        UpDownOutInternal   % Phase error output
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
        function obj = BaudRatePD(varargin)
            % Support name-value pair arguments when constructing object
            obj.BlockName = 'BaudRatePD';
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

            % Initialize sample and decision from previous frame
            obj.SamplePrevious = 0;
            obj.DecisionPrevious = 0;

            % Initialize timing function and symmetric transition indicator
            obj.TimingFunctionValue = zeros(obj.DemuxWidth, 1);
            obj.SymmetricTransition = zeros(obj.DemuxWidth, 1);

            % Initialize output
            obj.UpDownOutInternal = 0;
        end

        function validateInputsImpl(~,waveIn)
            validateattributes(waveIn,{'numeric'},{'finite'},'','waveIn');
        end

        function UpDownOut = stepImpl(obj,ClockIn,DecisionIn,SampleIn)
            %UpDownOut = stepImpl(obj,ClockIn,DecisionIn,SampleIn)

            %TODO
%             if nargin==4
%                 SampleIn = varargin{1};
%                 ClockIn = varargin{2};
%             else
%                 SampleIn = 0;
%                 ClockIn = 0;
%             end

            if isSample(obj)
                %Triggered clock step
                ClockStep(obj,ClockIn)

                % On falling clock edge, process frame of samples
                if obj.PhaseFallingIndex > 0

                    % Calculate timing function
                    % D[i]*S[i-1] - S[i]*D[i-1]
                    obj.TimingFunctionValue = SampleIn .* [obj.DecisionPrevious; DecisionIn(1:end-1)] - ...
                        DecisionIn .* [obj.SamplePrevious; SampleIn(1:end-1)];

                    % Mark symmetric transitions
                    % D[i] == -D[i-1]
                    obj.SymmetricTransition = double(abs(DecisionIn + [obj.DecisionPrevious; DecisionIn(1:end-1)]) < eps);

                    % Calculate phase error
                    % 1. Slice timing function from every sample in the frame
                    % 2. Only symmetric transitions contribute to phase error
                    % 3. Add contributions of all samples in the frame together
                    obj.UpDownOutInternal = sum(obj.SymmetricTransition .* sign(obj.TimingFunctionValue));

                    % Update previous frame decision and sample
                    obj.DecisionPrevious = DecisionIn(end);
                    obj.SamplePrevious = SampleIn(end);

                end % obj.PhaseFallingIndex > 0
            end

            % Assign output
            UpDownOut = obj.UpDownOutInternal;
        end

        function resetImpl(~)
            % Initialize / reset discrete-state properties
        end

        %% Simulink functions
        function icon = getIconImpl(~)
            % Define icon for System block
            icon = "Baud\nRate\nPhase\nDetector";
        end
        function [name1,name2,name3] = getInputNamesImpl(~)
            name1 = sprintf('Demux\nClock');
            name2 = 'Decision';
            name3 = 'Sample';            
        end
        function name1 = getOutputNamesImpl(~)
            name1 = 'UpDown';
        end
        function num = getNumInputsImpl(obj)
            if isSample(obj)
                num = 3;
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
                'PropertyList',{'DemuxWidth'});
        end
    end
end