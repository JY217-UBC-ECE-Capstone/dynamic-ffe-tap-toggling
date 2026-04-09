classdef (StrictDefaults) TxFFE < serdes.SerdesAbstractSystemObject
    % [TX] FFE Feed forward equalizer
    %     obj = serdes.FFE returns a System object, obj, that modifies a
    %     input waveform according to the finite impulse response (FIR)
    %     transfer function defined in the object.
    %
    %     obj = serdes.FFE('PropertyName', PropertyValue, ...) returns a
    %     FFE object, obj, with each specified property set to the
    %     specified value.
    %
    %     Step method syntax:
    %
    %     Y = step(obj, X) modifies the input waveform X according to the
    %     FFE object defined by obj and returns the modified waveform in
    %     Y.
    %
    %     System objects may be called directly like a function instead of
    %     using the step method. For example, y = step(obj, x) and y =
    %     obj(x) are equivalent.
    %
    %   FFE methods:
    %
    %   step              - See above description for use of this method
    %   clone             - Create FFE object with same property values
    %   isLocked          - Locked status (logical)
    %   plot              - Visualize tap weights with stem plot
    %
    %   FFE properties:
    %
    %   Mode              - FFE Mode, 0=off, 1=fixed
    %   ModePort          - In Simulink enables Mode to be an input port
    %   TapWeights        - FFE Tap vector
    %   Normalize         - Normalize the TapsWeights so that
    %                       sum(abs(TapWeights))=1.  Default=true.
    %   TapWeightsPort    - In Simulink enables TapWeights to be an input
    %                       port
    %   TapSpacing        - Spacing of taps. Symbol spaced 'T-spaced' (default),
    %                        'T/2-spaced' or 'T/4-spaced'.
    %   WaveType          - Type of input waveform to the step method. Can
    %                       be 'Sample', 'impulse', or 'Waveform'.
    %   SymbolTime        - time of a single symbol duration
    %   SampleInterval    - uniform time step of the waveform
    %
    %   %Example: Impulse Response Processing
    %   SymbolTime = 100e-12; %100 ps symbol time
    %   SamplesPerSymbol = 16;
    %   dbloss = 16; %dB loss of example channel
    %   TapWeights = [0 0.7 -0.2 -0.10];
    %   FFEMode = 1; %0:Off, 1:On
    %
    %   %Calculate sample interval
    %   dt = SymbolTime/SamplesPerSymbol;
    %
    %   %Create FFE object
    %   FFE1 = serdes.FFE('SymbolTime',SymbolTime,'SampleInterval',dt,...
    %     'Mode',FFEMode,'WaveType','Impulse',...
    %     'TapWeights',TapWeights);
    %
    %   %Create channel impulse response
    %   channel = serdes.ChannelLoss('Loss',dbloss,'dt',dt,...
    %     'TargetFrequency',1/SymbolTime/2);
    %   impulseIn = channel.impulse;
    %
    %   %Process impulse response with FFE
    %   impulseOut = FFE1(impulseIn);
    %
    %   %Convert impulse responses to pulse, waveform and eye diagram for visualization
    %   ord = 6;
    %   dataPattern = prbs(ord,2^ord-1)-0.5;
    %
    %   pulseIn = impulse2pulse(impulseIn,SamplesPerSymbol, dt);
    %   waveIn = pulse2wave(pulseIn,dataPattern,SamplesPerSymbol);
    %   eyeIn = reshape(waveIn,SamplesPerSymbol,[]);
    %
    %   pulseOut = impulse2pulse(impulseOut,SamplesPerSymbol, dt);
    %   waveOut = pulse2wave(pulseOut,dataPattern,SamplesPerSymbol);
    %   eyeOut = reshape(waveOut,SamplesPerSymbol,[]);
    %
    %   %Create time vectors
    %   t = dt*(0:length(pulseOut)-1)/SymbolTime;
    %   teye = t(1:SamplesPerSymbol);
    %   t2 = dt*(0:length(waveOut)-1)/SymbolTime;
    %
    %   %Plot
    %   figure
    %   plot(t,pulseIn,t,pulseOut)
    %   legend('Input','Output')
    %   title('Pulse Response Comparison')
    %   xlabel('SymbolTimes'),ylabel('Voltage')
    %   grid on
    %   axis([47 60 -0.1 0.4])
    %
    %   figure
    %   plot(t2,waveIn,t2,waveOut)
    %   legend('Input','Output')
    %   title('Waveform Comparison')
    %   xlabel('SymbolTimes'),ylabel('Voltage')
    %   grid on
    %
    %   figure
    %   subplot(211),plot(teye,eyeIn,'b')
    %   ax = axis;
    %   xlabel('SymbolTimes'),ylabel('Voltage')
    %   grid on
    %   title('Input Eye Diagram')
    %   subplot(212),plot(teye,eyeOut,'b')
    %   axis(ax);
    %   xlabel('SymbolTimes'),ylabel('Voltage')
    %   grid on
    %   title('Output Eye Diagram')
    %
    %   See also serdes.VGA, serdes.CTLE, serdes.AGC, serdes.PassThrough,
    %     serdes.SaturatingAmplifier, serdes.DFECDR, serdes.ChannelLoss, serdes.CDR
    
    %   Copyright 2018-2024 The MathWorks, Inc.
    
    %#codegen
    properties(Nontunable) %port/property duality
        %ModePort ModePort
        %   Specify Mode from input port in Simulink
        ModePort (1, 1) logical = true;
    end
    properties
        %Mode Mode (0:Off, 1:Fixed)
        %   When Mode=0, the block is bypassed without modifying the
        %   waveform.  When Mode=1, the TapWeights is applied to the input
        %   waveform as a symbol space FIR filter.
        Mode = 1;
    end
    properties(Nontunable) %port/property duality
        %TapWeightsPort TapWeightsPort
        %Specify TapWeights from input port in Simulink
        TapWeightsPort (1, 1) logical = true;
    end
    properties(Nontunable)
        %Tap Spacing
        %   Define the spacing of the tap positions.  Either symbol spaced
        %   'T-spaced' (default), half-symbol spaced 'T/2-spaced' or
        %   quarter-symbol spaced 'T/4-spaced'.
        TapSpacing = 'T-spaced';
    end    
    properties
        %Tap weights
        %   TapWeights defines the number and magnitude of the pre-cursor,
        %   cursor and post-cursor tap weights.  The length of TapWeights
        %   vector defines the total number of tap weights and the tap with
        %   the maximum magnitude is the main cursor.  If all taps are set
        %   to zero, the first tap will be changed to 1 for a pass through
        %   response.
        TapWeights = [ 0 1 0 0 0];
    end
    properties (Nontunable)
        %Normalize Normalize taps
        %   Normalize TapWeights such that sum(abs(TapWeights))==1.
        Normalize (1, 1) logical = true;
        %Input waveform type
        %   Set the input wave type as one of 'Sample' | 'Impulse' |
        %   'Waveform'.  The default is 'Sample'.
        WaveType = 'Sample';
    end
    properties (Hidden,Constant)
        WaveTypeSet = matlab.system.StringSet({...
            'Sample',...
            'Impulse',...
            'Waveform'});
        TapSpacingSet = matlab.system.StringSet( { ...
            'T-spaced', ...
            'T/2-spaced', ...
            'T/4-spaced'} );
        
        SymbolTimeAttributes = {'NoDisplayInSerDesDesignerApp'};
        SampleIntervalAttributes = {'NoDisplayInSerDesDesignerApp'};
        ModulationAttributes = {'NoDisplayInSerDesDesignerApp'};
        WaveTypeAttributes = {'NoDisplayInSerDesDesignerApp'};
        TapWeightsAttributes = {'Vector'};
        
        Mode_ToolTip = getString(message('serdes:serdesdesigner:FFEMode_ToolTip'));
        TapWeights_NameInGUI = getString(message('serdes:serdesdesigner:FFETapWeights_NameInGUI'));
        TapWeights_ToolTip = getString(message('serdes:serdesdesigner:FFETapWeights_ToolTip'));
        Normalize_NameInGUI = getString(message('serdes:serdesdesigner:FFENormalize_NameInGUI'));
        Normalize_ToolTip = getString(message('serdes:serdesdesigner:FFENormalize_ToolTip'));

        TapSpacing_NameInGUI = getString(message('serdes:serdesdesigner:FFETapSpacing_NameInGUI'));
        TapSpacing_ToolTip = getString(message('serdes:serdesdesigner:FFETapSpacing_ToolTip'));
    end
    properties (SetAccess = immutable, Nontunable, Hidden)
        IsLinear = true;
        IsTimeInvariant = true;
    end
       
    properties(SetAccess = protected, Hidden)
        Buff
        FIRpointer
        WeightsInternal
        SamplesPerSymbol
        BuffSize
        TapCount

        privateSampleWaveType
    end    
    
    properties (Constant, Hidden) %port/property duality       
        ModeSet = matlab.system.SourceSet(...
            {'PropertyOrInput', 'SystemBlock', 'ModePort', 1, 'Mode'}, ...
            {'Property', 'MATLAB', 'ModePort'});
        TapWeightsSet = matlab.system.SourceSet( ...
            {'PropertyOrInput', 'SystemBlock', 'TapWeightsPort', 2, 'TapWeights'}, ...
            {'Property', 'MATLAB', 'TapWeightsPort'})        
    end

    methods
        % Constructor
        function obj = TxFFE(varargin)
            % Support name-value pair arguments when constructing object
            obj.BlockName = 'TxFFE';
            setProperties(obj,nargin,varargin{:})
        end
        function plot(obj,varargin)
            %PLOT Visualize FFE response
            %   plot(obj) draws a stem plot of the FFE tap weights in the
            %   current figure.
            %
            %   plot(obj,fhandle) draws a stem plot of the FFE tap weights
            %   in the figure specified by fhandle.
            
            if nargin>=2 && ~isempty(ishandle(varargin{1})) && ...
                    ishandle(varargin{1}) && strcmp(get(varargin{1}, 'type'), 'figure')
                figure(varargin{1})
            end
            
            %Ensure tap weights are calculated
            setupImpl(obj)
            
            %Determine main tap
            [~,mainTapIndex] = max(abs(obj.WeightsInternal));
            
            %Fractional tap scale
            ftapscale = obj.SamplesPerSymbol/round(obj.SymbolTime/obj.SampleInterval);

            %Determine plot horizontal vector
            x = ((1:obj.TapCount)-mainTapIndex)*ftapscale;

            %Create Stem plot
            h = stem(x,obj.WeightsInternal,'filled');
            hbase = h.BaseLine;
            hbase.LineStyle = '--';
            ylabel('Volts')
            xlabel('UI')            
            title(sprintf('FFE %s FIR Filter',obj.TapSpacing))
            grid on
            ax = axis;
            axis([ax(1:2)+[-1,1],ax(3:4)])
        end
    end
    methods (Hidden)
        % The below methods, getAMIParameters, getAMIInputNames and
        % getAMIOutputNames are for use only within the serdesDesigner App
        % and will not influence the AMI parameters in Simulink whatsoever.
        function amiParams = getAMIParameters(obj)
            
            ModeAMI = serdes.internal.ibisami.ami.parameter.SerDesModelSpecificParameter(...
                'Name', 'Mode',...
                'Description', 'FFE Mode: 0=off, 1=fixed',...
                'Usage', 'In',...
                'Type', 'Integer',...
                'Format', "List 1 0",...
                'CurrentValue', obj.Mode);
            ModeAMI.Format.ListTips = {'fixed','off'};
            ModeAMI.Format.Default=1;
            
            %Ensure tap weights are calculated
            setupImpl(obj);
            
            %Main Tap Index is assumed to be the tap with the largest
            %absolute value.
            if isempty(obj.TapWeights)
                localTaps = [0 1 0 0];
            else
                localTaps = obj.TapWeights;
            end
            [~,mainTapIndex] = max(abs(localTaps));
            if ~obj.Normalize
                range = "-2 2";
            else
                range = "-1e6 1e6";
            end
            TapsAMI = serdes.internal.ibisami.ami.TappedDelayLine(...
                'TapWeights',localTaps,...
                'mainTapIndex',mainTapIndex,...
                'range', range);
            amiParams = {ModeAMI,TapsAMI};
        end
        function names = getAMIInputNames(~)
            names = {'Mode','TapWeights'};
        end
        function names = getAMIOutputNames(~)
            names = {};
        end
    end
    methods
        function set.TapWeights(obj,val)
            validateattributes(val,...
                {'numeric'},...
                {'vector','finite'},...
                '','TapWeights');
            obj.TapWeights = val;
        end
        function set.Mode(obj,val)
            validateattributes(val,...
                {'numeric'},...
                {'scalar'},...
                '','Mode');
            mustBeMember(val, [0,1])
            obj.Mode = double(val);
        end
    end
    
    methods(Access = protected)
        function val = modeIsOff(obj)
            val = obj.Mode==double(0);
        end
        function val = modeIsFixed(obj)
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
        function validateInputsImpl(~,waveIn)
            validateattributes(waveIn,{'numeric'},{'finite'},'','waveIn');
        end
        function validatePropertiesImpl(obj)
            %validate obj.TapWeights (vector)
            validateattributes(obj.TapWeights,{'numeric'},{'vector','finite'},'','TapWeights');
        end
        function processTunedPropertiesImpl(obj)
            %TapWeights is the only tuneable property that could be changed
            %during a simulation. 
            setupWeights(obj)                       
        end
        function setupWeights(obj)
            %Determine the internal weights            

            %Validate and save tap weights
            if isempty(obj.TapWeights)
                localTaps = [0 1 0 0];
            else
                localTaps = obj.TapWeights;
            end
            
            sumabs = sum(abs(localTaps));
            if obj.Normalize && sumabs>0
                obj.WeightsInternal = localTaps(:).'/sumabs;
            elseif sumabs==0
                obj.WeightsInternal = 0*localTaps(:).';
                obj.WeightsInternal(1) = 1;
            else
                obj.WeightsInternal = localTaps(:).';
            end
        end
        function setupImpl(obj,varargin)
            
            %Do string compare once 
            obj.privateSampleWaveType = strcmpi(obj.WaveType,'Sample');

            setupWeights(obj)

            %Number of Taps
            obj.TapCount = length(obj.WeightsInternal);            
               
            % calculate effective samples per symbol
            if strcmpi('T/2-spaced',obj.TapSpacing)
                ftapValue = 0.5;
            elseif strcmpi('T/4-spaced',obj.TapSpacing)
                ftapValue = 0.25;
            else %if strcmpi('T-spaced',obj.TapSpacing)                
                ftapValue = 1;
            end            
            obj.SamplesPerSymbol = round(obj.SymbolTime/obj.SampleInterval)*ftapValue;

            % calculate buffer size to hold future/past samples based on # of taps
            obj.BuffSize = obj.SamplesPerSymbol*obj.TapCount;

            % initialize buffer for number of taps taking into account samples per bit
            obj.Buff = zeros(obj.BuffSize,1);
            % initialize position pointer in buffer to beginning
            obj.FIRpointer = 1;
        end
        function waveOut = stepImpl(obj,waveIn)
            
            % Loop through input to update buffer and compute output
            waveOut = waveIn;
            if modeIsFixed(obj)
                if obj.privateSampleWaveType %if sample-by-sample wavetype
                    for idx = 1:numel(waveIn)
                        % add current input to buffer
                        obj.Buff(obj.FIRpointer) = waveIn(idx);
                        % multiply normalized tap values array by shift register (contains pointers to buffer)
                        waveOut(idx) = obj.WeightsInternal*obj.Buff(mod(obj.FIRpointer-(0:obj.TapCount-1)*obj.SamplesPerSymbol-1,obj.BuffSize)+1);
                        % move pointer to next position (either +1 or back to
                        % beginning of buffer if you fall off the end)
                        obj.FIRpointer = mod(mod(obj.FIRpointer-1,obj.BuffSize)+1,obj.BuffSize)+1;
                    end
                else %Wavetype is Impulse or Waveform
                    %Apply FIR filter with a wrap around due to the
                    %assumed nature of impulse responses and prbs
                    %waveforms.
                    [nrows,ncols]=size(waveIn);
                    for jj = 1:ncols
                        y1 = zeros(nrows,1);
                        for ii = 1:obj.TapCount
                            y1 = y1 + obj.WeightsInternal(ii)*...
                                circshift(waveIn(:,jj),(ii-1)*obj.SamplesPerSymbol);
                        end
                        waveOut(:,jj)=y1;
                    end
                end
            end
        end
        function resetImpl(obj)
            % Initialize / reset discrete-state properties
            obj.Buff = zeros(obj.BuffSize,1);
            obj.FIRpointer = 1;
        end
        %% Simulink functions
        function icon = getIconImpl(~)
            % Define icon for System block
            icon = "FFE";
        end
        function name = getInputNamesImpl(~)
            name = 'In';
        end
        function name = getOutputNamesImpl(~)
            name = 'Out';
        end
        %% Backup/restore functions
        function s = saveObjectImpl(obj)
            % Set properties in structure s to values in object obj
            
            % Set public properties and states
            s = saveObjectImpl@matlab.System(obj);
            
            % Set private and protected properties
            s.Buff = obj.Buff;
            s.FIRpointer = obj.FIRpointer;
            s.WeightsInternal = obj.WeightsInternal;
            s.SamplesPerSymbol = obj.SamplesPerSymbol;
            s.BuffSize = obj.BuffSize;
            s.TapCount = obj.TapCount;
   
            s.privateSampleWaveType = obj.privateSampleWaveType;
        end
        function loadObjectImpl(obj,s,wasLocked)
            % Set properties in object obj to values in structure s
            
            % Set private and protected properties
            obj.Buff = s.Buff;
            obj.FIRpointer = s.FIRpointer;
            obj.WeightsInternal = s.WeightsInternal;
            obj.SamplesPerSymbol = s.SamplesPerSymbol;
            obj.BuffSize = s.BuffSize;
            obj.TapCount = s.TapCount;
            
            %Backward compatibility for new protected properties
            if isfield(s,'TapSpacing')
                obj.privateSampleWaveType = s.privateSampleWaveType;
            end

            % Set public properties and states
            loadObjectImpl@matlab.System(obj,s,wasLocked);
        end
        function plotButton(obj,actionData)
            f = actionData.UserData;
            if isempty(f) || ~ishandle(f)
                f = figure;
                actionData.UserData = f;
            else
                figure(f);
            end
            
            plot(obj,f)
        end
    end
    
    methods(Static, Access=protected)
        function group = getPropertyGroupsImpl(~)
            Actions = matlab.system.display.Action(@(actionData,obj) ...
                plotButton(obj,actionData),'Label','Visualize Response');

            % Define property section(s) for System block dialog
            mainGroup = matlab.system.display.SectionGroup(...
                'Title','Main',...
                'PropertyList',{'ModePort','Mode',...
                'TapSpacing',...
                'TapWeightsPort','TapWeights','Normalize',},...
                'Actions',Actions);
            advancedGroup = matlab.system.display.SectionGroup(...
                'Title','Advanced',...
                'PropertyList',{'SymbolTime','SampleInterval','WaveType'});
            group = [mainGroup,advancedGroup];
        end
    end
    methods (Access = protected) %Propagator methods
        function v1 = getOutputDataTypeImpl(obj)
            v1 = propagatedInputDataType(obj,1);
        end
        function sz1 = getOutputSizeImpl(obj)
            sz1 = propagatedInputSize(obj,1);
        end
        function val1 = isOutputFixedSizeImpl(obj)
            val1 = propagatedInputFixedSize(obj,1);
        end
        function val1 = isOutputComplexImpl(~)
            val1 = false;
        end
    end
end