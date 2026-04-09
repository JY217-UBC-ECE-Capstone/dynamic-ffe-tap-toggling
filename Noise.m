classdef (StrictDefaults) Noise < serdes.SerdesAbstractSystemObject
    % Noise    Gaussian Noise Injection
    %   obj = Noise returns a System Object, obj, that adds Gaussian Noise
    %   of a specified power spectral density (PSD) to an input waveform.
    %
    % Noise methods:
    %   step - injects Gaussian noise to waveform. y = step(obj,x) modifies
    %          the input waveform, x, by adding Gaussian noise to create
    %          the noisy signal y.
    %
    % Noise properties:
    %   Mode           - Noise Mode, 0=off, 1=on
    %   ModePort       - In Simulink enables Mode to be an input port
    %   NoisePSD       - Input noise integrated power spectral density (PSD)
    %                    in units of V^2/GHz
    %   NoisePSDPort   - In Simulink enables NoisePSD to be an input port
    %   SampleInterval - Uniform time step of the waveform

    %   Copyright 2020-2021 The MathWorks, Inc.

    %#codegen

    properties(Nontunable)
        ModePort (1, 1) logical     = false;
    end

    properties
        Mode = 1; % Mode (0: Off, 1: On)
    end

    properties(Nontunable)
        NoisePSDPort (1, 1) logical = true;
    end

    properties
        NoisePSD = 0.0; % Input noise PSD (V^2/GHz)
    end

    properties (Constant, Hidden) %port/property duality
        ModeSet = matlab.system.SourceSet(...
            {'PropertyOrInput', 'SystemBlock', 'ModePort', 1, 'Mode'},...
            {'Property', 'MATLAB', 'ModePort'});

        NoisePSDSet = matlab.system.SourceSet(...
            {'PropertyOrInput', 'SystemBlock', 'NoisePSDPort', 2, 'NoisePSD'},...
            {'Property', 'MATLAB', 'NoisePSDPort'});
    end

    properties (SetAccess = protected, Hidden)
        NoiseRMS ; % Input noise RMS     , V
        FreqMax; % Simulation bandwidth, GHz
    end

    properties (Nontunable)
        %Input Waveform Type
        %   Set the input wave type as one of 'Sample' | 'Impulse' |
        %   'Waveform'.  The default is 'Sample'.
        WaveType = 'Sample';
    end

    properties (Hidden,Constant)
        WaveTypeSet = matlab.system.StringSet({'Sample','Impulse','Waveform'});
    end

    properties (SetAccess = immutable, Nontunable, Hidden)
        IsLinear = false;
        IsTimeInvariant = false;
    end

    methods
        % Constructor
        function obj = Noise(varargin)
            % Support name-value pair arguments when constructing object
            obj.BlockName = 'Noise';
            setProperties(obj,nargin,varargin{:})
        end
    end
    methods (Hidden)
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

    methods(Access = protected)
        %% Common functions
        function setupImpl(obj)
            % Convert noise PSD to RMS
            fs            = 1 / obj.SampleInterval; % Sampling frequency, Hz
            obj.FreqMax = (fs / 2) / 1e9;   % Simulation BW     , GHz
            obj.NoiseRMS  = sqrt(obj.NoisePSD * obj.FreqMax);
        end

        function validateInputsImpl(~,waveIn)
            validateattributes(waveIn,{'numeric'},{'finite'},'','waveIn');
        end

        function waveOut = stepImpl(obj,waveIn)
            % In time domain add Gaussian noise to the sample
            if obj.modeIsOn() && obj.isSample()
                % Add noise to output waveform
                waveOut = waveIn + (obj.NoiseRMS * randn(size(waveIn)));
            else
                waveOut = waveIn;
            end
        end

        function resetImpl(~)
            % Initialize / reset discrete-state properties
        end

        function processTunedPropertiesImpl(obj)
            %Run when NoisePSD is a port
            obj.NoiseRMS  = sqrt(obj.NoisePSD * obj.FreqMax);
        end

        % Auxilliary functions
        function val = modeIsOff(obj)
            val = obj.Mode==double(0);
        end
        function val = modeIsOn(obj)
            val = obj.Mode==double(1);
        end
        function val = isImpulse(obj)
            val = strcmpi(obj.WaveType,'Impulse');
        end
        function val = isWaveform(obj)
            val = strcmpi(obj.WaveType,'Waveform');
        end
        function val = isSample(obj)
            val = strcmpi(obj.WaveType,'Sample');
        end
        %% Simulink functions
        function icon = getIconImpl(~)
            % Define icon for System block
            icon = "Noise";
        end
    end
    methods(Static, Access=protected)
        function group = getPropertyGroupsImpl(~)
            % Define property section(s) for System block dialog
            mainGroup = matlab.system.display.SectionGroup(...
                'Title','Main',...
                'PropertyList',{'ModePort','Mode','NoisePSDPort','NoisePSD',...
                'SampleInterval'});
            group = mainGroup;
        end
    end
end