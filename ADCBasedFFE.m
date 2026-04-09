classdef (StrictDefaults) ADCBasedFFE < serdes.SerdesAbstractSystemObject & TriggeredComponent
    %ADCBasedFFE    ADC Based Feed-Forward Equalizer
    %   obj = ADCBasedFFE returns a System Object, obj, that equalizes a
    %   demuxed signal with a feed-forward equalizer.
    %
    % ADCBasedFFE methods:
    %   step - Equalizes the demuxed signal of size DemuxWidth with the FFE
    %          tap weights specified by TapWeights. The object must be
    %          additionaly driven by the demux clock.
    %          SampleOut = stepImpl(obj,SampleIn,ClockIn)
    %
    % ADCBasedFFE properties:
    %   Mode           - Equalization mode, 0=pass throught, 1=apply equalization.
    %   DemuxWidth     - Demux size of the incoming waveform.
    %   TapWeights     - FFE tap weight vector.
    %   TapWeightsPort - In Simulink enables TapWeights to be an input port.
    %   SymbolTime     - Symbol time of the system.
    %   SampleInterval - Uniform time step of the system.

    %   Copyright 2021 The MathWorks, Inc.
    
    %#codegen
    
    properties (Nontunable)
        % Mode Mode (0: pass through, 1: Apply filter)        
        Mode     =  1;
        
        %Demux Width
        DemuxWidth = 32;
    end
    properties (Hidden, SetAccess=private)
        %FFE properties
        NumberOfTaps % Number of FFE taps
        FrameOut     % Output frame
        Buffer       % Output buffer
        BlockTail    % Block convolution BlockTail
    end
    properties (Nontunable, Hidden)
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
    
    properties       
        %Tap Weights
        TapWeights = 1;
    end
    
    properties(Nontunable) %port/property duality
       
        %TapWeightsPort TapWeightsPort
        %   Specify TapWeights from input port in Simulink
        TapWeightsPort (1, 1) logical = true;
    end
    
    properties (Constant, Hidden) %port/property duality
        TapWeightsSet = matlab.system.SourceSet(...
            {'PropertyOrInput', 'SystemBlock', 'TapWeightsPort', 1, 'TapWeights'}, ...
            {'Property', 'MATLAB', 'TapWeightsPort'});
    end

    properties (SetAccess = protected, GetAccess = public)
        % Power tracking results
        TotalEnergy = 0;
        CurrentPower = 0;
    end
    
    properties (SetAccess = protected, GetAccess = protected)
        % Power tracking variables
        CycleCount = 0;
        PreviousWeights;
        TapBits;
        MaxTapBits = 0;
    end

    
    methods
        % Constructor
        function obj = ADCBasedFFE(varargin)
            % Support name-value pair arguments when constructing object
            obj.BlockName = 'ADCBasedFFE';
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
            
            %specific properties
            obj.NumberOfTaps = length(obj.TapWeights);
            
            % Initialize convolution output and BlockTail to zero
            obj.FrameOut = zeros(obj.DemuxWidth               , 1);
            obj.Buffer = zeros(obj.DemuxWidth+obj.NumberOfTaps-1, 1);
            obj.BlockTail  = zeros(            obj.NumberOfTaps-1, 1);

            % Reset Power Vars
            obj.TotalEnergy = 0;
            obj.CurrentPower = single(0);
            obj.PreviousWeights = zeros(obj.NumberOfTaps);

            % Set bit sizes for FFE
            obj.TapBits = [10 10 11 12 12 12 0 0 12 12 11 11 11 10 10 9 9 9 8 8 8 8 8 8 8 8 8 8 8 8 7]; % 0 bits for fixed cursor and tap replaced by DFE
            obj.MaxTapBits = max(obj.TapBits);

            assert(numel(obj.TapBits) == obj.NumberOfTaps);
            assert(obj.MaxTapBits > 0);
        end
        
        function validateInputsImpl(~,waveIn)
            validateattributes(waveIn,{'numeric'},{'finite'},'','waveIn');
        end


        function [SampleOut,CurrentPowerOut] = stepImpl(obj,SampleIn,varargin)
            
            if nargin == 3
                ClockIn = varargin{1};
            else
                ClockIn = 0;
            end

            % Default to power output from the previous cycle
            CurrentPowerOut = obj.CurrentPower;
            
            if isImpulse(obj)
                %Apply FIR filter with a wrap around due to the
                %assumed nature of impulse responses waveforms.
                SamplesPerSymbol = round(obj.SymbolTime/obj.SampleInterval);
                [nrows,ncols]=size(SampleIn);
                SampleOut = zeros(size(SampleIn));
                for jj = 1:ncols
                    y1 = zeros(nrows,1);
                    for ii = 1:length(obj.TapWeights)
                        y1 = y1 + obj.TapWeights(ii)*...
                            circshift(SampleIn(:,jj),(ii-1)*SamplesPerSymbol);
                    end
                    SampleOut(:,jj)=y1;
                end

            elseif isSample(obj)
                %Triggered clock step
                ClockStep(obj,ClockIn)
                
                % On falling clock edge, process frame of samples
                if obj.PhaseFallingIndex
                    
                    if obj.Mode
                        % Convolve frame of input samples with FFE IR depending on Mode
                        obj.Buffer = conv(SampleIn, obj.TapWeights(:));
                        
                        % Add tail from previous block
                        obj.Buffer(1:obj.NumberOfTaps-1) = obj.Buffer(1:obj.NumberOfTaps-1) + obj.BlockTail;
                        
                        % Update the block convolution tail
                        obj.BlockTail = obj.Buffer(end-obj.NumberOfTaps+2:end);
                        
                        % Assign output
                        obj.FrameOut = obj.Buffer(1:obj.DemuxWidth);

                        % -- Power Computation --
                        % Count Zeros and Constant (non-zero) Multiplier Inputs
                        ZeroMask = (obj.TapWeights == 0);
                        NumberOfZeros = nnz(ZeroMask);
                        ConstantMask = (obj.PreviousWeights == obj.TapWeights);
                        NumberOfConstants = nnz(ConstantMask) - nnz(ZeroMask .* ConstantMask);

                        % Define one unit of energy as the energy required 
                        % to complete one multiplication for the largest multiplier
                        % This calculation makes the assumption that
                        % multiplier energy scales linearly with tap bit size
                        CycleEnergy = sum(obj.TapBits) / obj.MaxTapBits;

                        % 99% energy saving when an input is zero
                        CycleEnergy = CycleEnergy - 0.99 * sum(ZeroMask .* obj.TapBits) / obj.MaxTapBits;

                        % 25% energy penalty when tap weights are changing
                        % between cycles
                        % CycleEnergy = CycleEnergy + 1/(1-0.25) * (obj.NumberOfTaps - NumberOfConstants - NumberOfZeros);

                        % Scale by number of symbols processed
                        CycleEnergy = CycleEnergy * length(SampleIn);

                        % Update Outputs
                        obj.TotalEnergy = obj.TotalEnergy + CycleEnergy;
                        obj.CurrentPower = single(CycleEnergy);

                        % Update energy tracking state
                        obj.PreviousWeights = obj.TapWeights;

                        CurrentPowerOut = obj.CurrentPower;

                        % Assertions
                        assert(obj.TotalEnergy >= 0);
                        assert(obj.CurrentPower >= 0);
                    else
                        obj.FrameOut = SampleIn(:);
                        obj.BlockTail = zeros(size(obj.BlockTail));
                    end
                    
                end % obj.PhaseFallingIndex > 0
                
                % Assign outputs
                SampleOut = obj.FrameOut;
            end
            
        end

        function releaseImpl(obj)
            % Print the total energy used by FFE
            if obj.TotalEnergy > 0
                fprintf('Total Energy: %.2f\n', obj.TotalEnergy);
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
            dt2 = 'single';
        end
        function [c1,c2] = isOutputComplexImpl(~)
            c1 = false;
            c2 = false;
        end
        
        function resetImpl(obj)
            % Initialize / reset discrete-state properties
        end
        
        %% Simulink functions
        function icon = getIconImpl(~)
            % Define icon for System block
            icon = sprintf('ADC\nBased\nFFE');
        end
        function [name1,name2,name3] = getInputNamesImpl(~)
            name1 = 'Sample';
            name2 = sprintf('Demux\nClock');
            name3 = 'Taps';
        end        
        function [name1,name2] = getOutputNamesImpl(~)
            name1 = 'Sample';
            name2 = 'CurrentPower';
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
                'PropertyList',{'Mode','DemuxWidth','TapWeights','TapWeightsPort',...
                'SymbolTime','SampleInterval'});
        end
    end    
end