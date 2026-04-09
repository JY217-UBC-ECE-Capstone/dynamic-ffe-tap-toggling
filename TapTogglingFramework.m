classdef TapTogglingFramework < handle
    % Simple framework for tap toggling experiments
    % Supports both stateless and stateful algorithms
    
    properties
        algorithmType  % String identifier for the algorithm
        state          % For stateful algorithms
    end
    
    methods
        function obj = TapTogglingFramework(algorithmType, LMSUpdateObj)
            % Store the algorithm type as a string
            obj.algorithmType = algorithmType;
            
            % Initialize state based on algorithm type
            switch algorithmType
                case 'base'
                    obj.state = [];
                    
                case 'allzeros'
                    obj.state = [];
                    
                case 'mincoeff'
                    obj.state = struct('N', 10 , 'startPoint', 0.8);
                    
                case 'leveraged'
                    obj.state = LeveragedLMS(LMSUpdateObj);

                case 'threshold'
                    obj.state = struct('thresholdPercent', 0.1, 'startPoint', 0.95);  

                case 'informedMinC'
                    obj.state = InformedMinCoeff(LMSUpdateObj);

                case 'marginLock'
                    obj.state = MarginLock(LMSUpdateObj);
                    
                otherwise
                    error('Unknown algorithm type: %s', algorithmType);
            end
        end
        
        function mask = getMask(obj, taps, LMSUpdateObj)
            % Dispatch based on algorithm type string
            mask = ones(size(taps));

            switch obj.algorithmType
                case 'base'
                    mask = obj.simpleToggle(taps);
                    
                case 'allzeros'
                    mask = zeros(size(taps));
                    
                case 'mincoeff'
                    mask = obj.minCoeffToggle(taps, LMSUpdateObj);

                case 'threshold'
                    mask = obj.thresholdToggle(taps, LMSUpdateObj);
                    
                case 'leveraged'
                    mask = obj.LMSToggle(taps, LMSUpdateObj);

                case 'informedMinC'
                    mask = obj.informedMinCToggle(taps, LMSUpdateObj);

                case 'marginLock'
                    mask = obj.MarginLockToggle(taps, LMSUpdateObj);
                    
                otherwise
                    error('Unknown algorithm type: %s', obj.algorithmType);
            end
        end
        
        %% Algorithms ----------------------------------------------------------------
        
        function mask = simpleToggle(obj, taps)
            mask = ones(size(taps));
        end
        
        function mask = minCoeffToggle(obj, taps, LMSUpdateObj)
            mask = ones(size(taps));
      
            if isempty(obj.state) || ~isfield(obj.state, 'N') || ~isfield(obj.state, 'startPoint')
                return;
            end

            if LMSUpdateObj.IterCount > round(obj.state.startPoint * LMSUpdateObj.NumSymbolFramesAdaptation * LMSUpdateObj.WindowSize) ||  LMSUpdateObj.Adapting == 0
                mask = MinCoeff(taps,obj.state.N);
            end
        end

        function mask = thresholdToggle(obj, taps, LMSUpdateObj)
            mask = ones(size(taps));

            if isempty(obj.state) || ~isfield(obj.state, 'thresholdPercent') || ~isfield(obj.state, 'startPoint')
                return;
            end
            
            if LMSUpdateObj.IterCount > round(obj.state.startPoint * LMSUpdateObj.NumSymbolFramesAdaptation * LMSUpdateObj.WindowSize) ||  LMSUpdateObj.Adapting == 0
                mask = Threshold(taps,obj.state.thresholdPercent);
            end
        end

        function mask = LMSToggle(obj, taps, LMSUpdateObj)
            mask = ones(size(taps));
            
            % Necessary otherwise simulink complains
            if isobject(obj.state) && ismethod(obj.state, 'GetFFETapsMask')
                mask = obj.state.GetFFETapsMask(LMSUpdateObj);
            else
                mask = ones(size(taps));
            end
        end

        function mask = informedMinCToggle(obj, taps, LMSUpdateObj)
            mask = ones(size(taps));
            
            % Necessary otherwise simulink complains
            startTime = round((LMSUpdateObj.StartDFEAdaptTime + 50) * LMSUpdateObj.WindowSize);
            if isobject(obj.state) && ismethod(obj.state, 'GetFFETapsMask') && LMSUpdateObj.IterCount > startTime
                mask = obj.state.GetFFETapsMask(LMSUpdateObj);
            else
                mask = ones(size(taps));
            end
        end

        function mask = MarginLockToggle(obj, taps, LMSUpdateObj)
            mask = ones(size(taps));
            
            % Necessary otherwise simulink complains
            if isobject(obj.state) && ismethod(obj.state, 'GetFFETapsMask')
                mask = obj.state.GetFFETapsMask(LMSUpdateObj);
            else
                mask = ones(size(taps));
            end
        end
     
    end
end