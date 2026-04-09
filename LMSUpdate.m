classdef (StrictDefaults) LMSUpdate < serdes.SerdesAbstractSystemObject & TriggeredComponent & handle
    %LMSUpdate - Output Updated Weigths based on Given Samples
    %   obj = ADCBasedFFE returns a System Object, obj, that equalizes a
    %   demuxed signal with a feed-forward equalizer.
    %
    % LMSUpdate methods:
    %   step - Updates internal FFE Taps, DFE Taps, and Dlevs using
    %          sign-sign LMS Algorithm and outputs them
    %
    % LMSUpdate properties:
    %   NumPreTaps  - Number of FFE Pre-Taps
    %   NumPostTaps - Number of FFE Post-Taps
    %
    %   Init_MuFFE  - Initial Learning Rate for updating FFE Taps
    %   Init_MuDFE  - Initial Learning Rate for updating DFE Tap
    %   Init_MuDlev - Initial Learning Rate for updating Dlevs
    %   
    %   Init_Dlevs  - Starting Dlev Values for better Adaptation
    %   
    %   StartFFEAdaptTime  - After Going over this many Symbol Frames,
    %                        start running ssLMS for FFE
    %   StartDFEAdaptTime  - After Going over this many Symbol Frames,
    %                        start running ssLMS for DFE
    %   StartDlevAdaptTime - After Going over this many Symbol Frames,
    %                        start running ssLMS for Dlevs
    %
    %   NumSymbolFramesAdaptation - After this many Symbol Frames,
    %                               End ssLMS Adaptation
    %
    %   LearningRatesAdjustTimes - Halve LMS Learning Rates after reaching
    %                              this many Symbol Frames


    %#codegen
    properties (Nontunable)
        NumPreTaps = 6;
        NumPostTaps = 24;
        Init_MuFFE = 0.005;
        Init_MuDFE = 0.0025;
        Init_MuDlev = 0.0005;

        Init_Dlevs = [-0.2 -0.075 0.075 0.2];

        StartFFEAdaptTime = 150;
        StartDFEAdaptTime = 250;

        WindowSize = 64;

        NumSymbolFramesAdaptation = 96000/64;
        LearningRatesAdjustTimes = [500, 850, 1250];

        TogglingAlgorithm {mustBeMember(TogglingAlgorithm, ...
            {'base', 'allzeros', 'mincoeff', 'leveraged', 'threshold', 'informedMinC', 'marginLock'} ...
            )} = 'base';
    end
    properties (Hidden, SetAccess=private)
        Mu
        MuDFE
        MuDlev

        TapWeights
        DFE_Tap

        InitializedTaps

        TogglingAlgoObj
        FFE_TapsMask

        IterCount

        Dlev_0p5
        Dlev_0p16
        Dlev_m0p16
        Dlev_m0p5

        Votes

        Vote_DFE_Tap

        Votes_Dlev_0p5
        Votes_Dlev_0p16
        Votes_Dlev_m0p16
        Votes_Dlev_m0p5

        AdcLSB
        AdcDynamicRange
        AdcResolution

        PrevAdcSamples_D0
        PrevAdcSamples_D1
        PrevAdcSamples_D2

        PrevDFEOutput
        PrevDesiredOutput

        ErrorVec

        Adapting
    end
    properties (Nontunable, Hidden)
        NumberOfClocks = 1;
    end

    properties (SetAccess = immutable, Nontunable, Hidden)
        IsLinear = true;
        IsTimeInvariant = true;
    end
    
    methods
        % Constructor
        function obj = LMSUpdate(varargin)
            % Support name-value pair arguments when constructing object
            obj.BlockName = 'LMSUpdate';
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
    methods(Access = public)
        function setLearningRates(obj, newMu, newMuDFE, newMuDlev)
            obj.Mu = newMu;
            obj.MuDFE = newMuDFE;
            obj.MuDlev = newMuDlev;
        end
    end
    methods(Access = protected)
        %% Common functions
        function setupImpl(obj)
            setupClock(obj)

            obj.Mu = obj.Init_MuFFE;
            obj.MuDFE = obj.Init_MuDFE;
            obj.MuDlev = obj.Init_MuDlev;

            obj.TapWeights = [zeros(1,obj.NumPreTaps) 1 zeros(1,obj.NumPostTaps)];
            obj.DFE_Tap = 0;

            obj.InitializedTaps = false;

            obj.FFE_TapsMask = ones(1, obj.NumPreTaps + 1 + obj.NumPostTaps);

            obj.IterCount = 0;

            % hard-coded initial dlevs
            obj.Dlev_0p5 = obj.Init_Dlevs(4);
            obj.Dlev_0p16 = obj.Init_Dlevs(3);
            obj.Dlev_m0p16 = obj.Init_Dlevs(2);
            obj.Dlev_m0p5 = obj.Init_Dlevs(1);

            obj.Votes = zeros(1, length(obj.TapWeights));

            obj.Vote_DFE_Tap = 0;

            obj.Votes_Dlev_0p5 = 0;
            obj.Votes_Dlev_0p16 = 0;
            obj.Votes_Dlev_m0p16 = 0;
            obj.Votes_Dlev_m0p5 = 0;

            obj.AdcDynamicRange = 0.35;
            obj.AdcResolution = 6;
            obj.AdcLSB = 2 * obj.AdcDynamicRange / (2^obj.AdcResolution - 1);

            obj.PrevAdcSamples_D0 = zeros(1,64).';
            obj.PrevAdcSamples_D1 = zeros(1,64).';
            obj.PrevAdcSamples_D2 = zeros(1,64).';

            obj.PrevDFEOutput = zeros(1,64).';
            obj.PrevDesiredOutput = zeros(1,64).';

            obj.ErrorVec = zeros(1,64);

            obj.Adapting = 1;

            obj.TogglingAlgoObj = TapTogglingFramework(obj.TogglingAlgorithm, obj);

            % Print Config:
            fprintf("[LMSUpdate] Toggling Algo: %s\n", obj.TogglingAlgorithm);
            fprintf("[LMSUpdate] NumPreTaps=%.0f, NumPostTaps=%.0f\n", obj.NumPreTaps, obj.NumPostTaps);
            fprintf("[LMSUpdate] WindowSize=%.0f, StartFFEAdaptTime=%.0f, StartDFEAdaptTime=%.0f\n", obj.WindowSize, obj.StartFFEAdaptTime, obj.StartDFEAdaptTime);
        end
        
        function [UpdatedTapWeights, UpdatedDFETap, UpdatedDlevs, Adapting, Dbg] = stepImpl(obj, AdcSamples, DFE_Output, Desired_Output, ClockIn, Init_FFE_Taps, Init_DFE_Tap)
            if obj.DFE_Tap == 0 && Init_DFE_Tap ~= 0
                obj.DFE_Tap = Init_DFE_Tap;
            end

            if ~obj.InitializedTaps
                obj.TapWeights = Init_FFE_Taps;
                obj.InitializedTaps = true;
            end

            %Triggered clock step
            ClockStep(obj,ClockIn);


            % Convert Decisions to ADC Samples
            Sampled_Desired_Output = Desired_Output;

            for i = 1:length(Desired_Output)
                % Adjust Desired Outputs (Decision Symbols) to Current Dlevs
                if Desired_Output(i) > 0.4
                    Sampled_Desired_Output(i) = obj.Dlev_0p5;
                elseif Desired_Output(i) < 0.3 && Desired_Output(i) > 0
                    Sampled_Desired_Output(i) = obj.Dlev_0p16;
                elseif Desired_Output(i) > -0.3 && Desired_Output(i) < 0
                    Sampled_Desired_Output(i) = obj.Dlev_m0p16;
                else
                    Sampled_Desired_Output(i) = obj.Dlev_m0p5;
                end
                
            end

                
            if obj.PhaseFallingIndex && obj.Adapting
                obj.IterCount = obj.IterCount + 1;

                % Extend ADC Samples to use later for updating FFE Taps
                ExtendedAdcSamples = [obj.PrevAdcSamples_D1.' obj.PrevAdcSamples_D0.'];

                obj.ErrorVec = Sampled_Desired_Output.' - DFE_Output.';

                if ismember(obj.IterCount, obj.WindowSize * obj.LearningRatesAdjustTimes)
                    obj.Mu = obj.Mu / 10;
                    obj.MuDFE = obj.MuDFE / 10;
                    obj.MuDlev = obj.MuDlev / 10;
                end

                % FFE Taps Adaptation (First)
                if obj.IterCount > obj.StartFFEAdaptTime * obj.WindowSize
    
                    for m = 1:(length(DFE_Output))
                        err = obj.ErrorVec(m);

                        for l = 1:length(obj.TapWeights)
                            extended_index = length(AdcSamples) + m - (l-1);
                            obj.Votes(l) = obj.Votes(l) + sign(err)*sign(ExtendedAdcSamples(extended_index));
                        end
                    end
    
                    if mod(obj.IterCount, obj.WindowSize) == 0
                        obj.Votes = obj.FFE_TapsMask .* obj.Votes;
                        DeltaWeights = 2 * obj.Mu * sign(obj.Votes);
                        DeltaWeights(obj.NumPreTaps+1) = 0; % fix the main cursor at 1
                        DeltaWeights(obj.NumPreTaps+2) = 0; % fix the first cursor to 0 (let DFE handle it)
                        obj.TapWeights = obj.TapWeights + DeltaWeights;

                        obj.Votes = zeros(1, length(obj.TapWeights));
                    end

                end

                % DFE Tap Adaptation (Second)
                if obj.IterCount > obj.StartDFEAdaptTime * obj.WindowSize
                    for m = 1:(length(DFE_Output))
                        err = obj.ErrorVec(m);
                        prev_dfe_dec = obj.PrevDesiredOutput(m);

                        obj.Vote_DFE_Tap = obj.Vote_DFE_Tap + sign(err)*sign(prev_dfe_dec);
                    end

                    if mod(obj.IterCount, obj.WindowSize) == 0
                        obj.DFE_Tap = obj.DFE_Tap + obj.MuDFE * sign(obj.Vote_DFE_Tap);
                        obj.Vote_DFE_Tap = 0;
                    end
                end

                % Dlevs Adaptation (Always On)
                if obj.IterCount >= obj.WindowSize
                    
                    for m = 1:(length(DFE_Output))
                        e = obj.ErrorVec(m);
    
                        if Sampled_Desired_Output(m) == obj.Dlev_0p5
                            obj.Votes_Dlev_0p5 = obj.Votes_Dlev_0p5 + sign(e);
                        elseif Sampled_Desired_Output(m) == obj.Dlev_0p16
                            obj.Votes_Dlev_0p16 = obj.Votes_Dlev_0p16 + sign(e);
                        elseif Sampled_Desired_Output(m) == obj.Dlev_m0p16
                            obj.Votes_Dlev_m0p16 = obj.Votes_Dlev_m0p16 + sign(e);
                        elseif Sampled_Desired_Output(m) == obj.Dlev_m0p5
                            obj.Votes_Dlev_m0p5 = obj.Votes_Dlev_m0p5 + sign(e);
                        end
                    end
    
                    if mod(obj.IterCount, obj.WindowSize) == 0
                        muRate = obj.MuDlev;
                        if obj.IterCount >= (obj.StartFFEAdaptTime) * obj.WindowSize
                            muRate = muRate / 2;
                        end
                        

                        obj.Dlev_0p5 = obj.Dlev_0p5 - muRate*sign(obj.Votes_Dlev_0p5);
                        obj.Dlev_0p16 = obj.Dlev_0p16 - muRate*sign(obj.Votes_Dlev_0p16);
                        obj.Dlev_m0p16 = obj.Dlev_m0p16 - muRate*sign(obj.Votes_Dlev_m0p16);
                        obj.Dlev_m0p5 = obj.Dlev_m0p5 - muRate*sign(obj.Votes_Dlev_m0p5);

                        obj.Votes_Dlev_0p5 = 0;
                        obj.Votes_Dlev_0p16 = 0;
                        obj.Votes_Dlev_m0p16 = 0;
                        obj.Votes_Dlev_m0p5 = 0;
                    end
                    
                end

                % Latch Samples
                obj.PrevAdcSamples_D2 = obj.PrevAdcSamples_D1;
                obj.PrevAdcSamples_D1 = obj.PrevAdcSamples_D0;
                obj.PrevAdcSamples_D0 = AdcSamples;
    
                obj.PrevDFEOutput = DFE_Output;
                obj.PrevDesiredOutput = Sampled_Desired_Output;

                % End adaptation after certain period of time
                if obj.IterCount >= round(obj.NumSymbolFramesAdaptation * obj.WindowSize)
                    obj.Adapting = 0;
                end

                obj.FFE_TapsMask = obj.TogglingAlgoObj.getMask(obj.TapWeights .* obj.FFE_TapsMask, obj);
            end

            %obj.TapWeights = obj.TapWeights .* obj.FFE_TapsMask;
            UpdatedTapWeights = obj.TapWeights .* obj.FFE_TapsMask;

            UpdatedDFETap = obj.DFE_Tap;

            UpdatedDlevs = [obj.Dlev_m0p5 obj.Dlev_m0p16 obj.Dlev_0p16 obj.Dlev_0p5];
            
            Adapting = obj.Adapting;
            Dbg = obj.FFE_TapsMask';
        end
        
        function releaseImpl(obj)
            % Print the final tap weights
            fprintf('[LMSUpdate] Final FFE Weights: ');
            for k = 1:numel(obj.TapWeights)
                fprintf(' %6.9f', obj.TapWeights(k));
            end
            fprintf('\n');
            fprintf("[LMSUpdate] Final DFE Tap: %6.16f", obj.DFE_Tap);
            fprintf('\n');
            fprintf('[LMSUpdate] Final Dlevs: ');
            fprintf(' %6.9f %6.9f %6.9f %6.9f', ...
                obj.Dlev_m0p5, obj.Dlev_m0p16, obj.Dlev_0p16, obj.Dlev_0p5);
            fprintf('\n');
            fprintf('[LMSUpdate] Final FFE Taps Mask: ');
            for k = 1:numel(obj.FFE_TapsMask)
                fprintf(' %1.0f', obj.FFE_TapsMask(k));
            end
            fprintf('\n');
        end
        
        %% Simulink functions
        function icon = getIconImpl(~)
            % Define icon for System block
            icon = sprintf('LMS\nUpdate');
        end
        function [name1,name2,name3,name4,name5,name6] = getInputNamesImpl(~)
            name1 = 'AdcSamples';
            name2 = 'DFE_Output';
            name3 = 'Desired_Output';
            name4 = 'Demux Clock';
            name5 = 'Init FFE Taps';
            name6 = 'Init DFE Tap';
        end        
        function [name1, name2, name3, name4, name5] = getOutputNamesImpl(~)
            name1 = sprintf('Updated\nTapWeights');
            name2 = sprintf('Updated\nDFE Tap');
            name3 = sprintf('Updated\nDlevs');

            name4 = 'Adapting';
            name5 = 'Dbg';
        end
        function num = getNumInputsImpl(~)
            num = 6;
        end
    end
    methods(Static, Access=protected)
        function group = getPropertyGroupsImpl(~)
            % Define property section(s) for System block dialog           
            group = matlab.system.display.SectionGroup(...
                'Title','Main',...
                'PropertyList',{'NumPreTaps','NumPostTaps',...
                'Init_MuFFE','Init_MuDFE','Init_MuDlev','Init_Dlevs',...
                'StartFFEAdaptTime','StartDFEAdaptTime','WindowSize',...
                'NumSymbolFramesAdaptation','LearningRatesAdjustTimes', ...
                'TogglingAlgorithm'});
        end
    end    
end