classdef InformedMinCoeff < handle
    % InformedMinCoeff
    % Toggles taps based on the available "Error Budget" (Slack).
    %
    % Logic:
    % 1. Calculate Error Limit (half distance between Dlevs).
    % 2. Calculate Current Max Error.
    % 3. Slack = Limit - Current.
    % 4. Turn off smallest taps as long as sum(|Tap| * 0.5) < Slack.
    % 5. Wait for LMS to adapt, then repeat.

    properties
        WaitCycles       % How many iterations to wait between updates
        IterationCounter   % Internal counter
        ReloadPeriod
        CurrentMask      % The currently active mask
        MaxInputVal      % Worst case input assumption (0.5)
        MaxCycleError
    end

    methods
        function obj = InformedMinCoeff(LMSUpdateObj)
            obj.IterationCounter = 0;
            obj.ReloadPeriod     = 5;
            obj.MaxInputVal      = 0.5;
            obj.MaxCycleError    = 0;

            obj.WaitCycles = obj.ReloadPeriod * LMSUpdateObj.WindowSize; 
            
            tapCount = LMSUpdateObj.NumPreTaps + 1 + LMSUpdateObj.NumPostTaps;
            obj.CurrentMask = ones(1, tapCount);    
        end

        function mask = GetFFETapsMask(obj, lmsObj)
            % Only update logic if adaptation is active
            if lmsObj.Adapting == 0
                 mask = obj.CurrentMask;
                 return;
            end

            % Determine Current Max Error (From the latest window)
            maxStepError = max(abs(lmsObj.ErrorVec));
            if maxStepError > obj.MaxCycleError
                obj.MaxCycleError = maxStepError;
            end
            currentMaxError = obj.MaxCycleError;  


            obj.IterationCounter = obj.IterationCounter + 1;
            if obj.IterationCounter < obj.WaitCycles
                mask = obj.CurrentMask;
                return;
            end

            % Error Tolerance = min(distance_between_dlevs) / 2
            dlevs = sort([lmsObj.Dlev_m0p5, lmsObj.Dlev_m0p16, lmsObj.Dlev_0p16, lmsObj.Dlev_0p5]);
            maxAcceptableError = min(diff(dlevs)) / 2;
            
            slack = maxAcceptableError - currentMaxError;
            
            % Determine Taps to Turn Off
            if slack <= 0
                % Negative or zero slack: Cannot turn off anything. 
                % Ideally, we should turn everything ON to recover.
                mask = obj.CurrentMask;
            else
                % Get magnitude of current taps
                absTaps = abs(lmsObj.TapWeights);
                
                % Sort taps to find candidates (smallest first)
                % We need original indices to create the mask later
                [sortedVals, originalIndices] = sort(absTaps, 'ascend');
                
                accumulatedErrorCost = 0;
                tapsToDisableIndices = [];

                for k = 1:length(sortedVals)
                    % Calculate worst-case error contribution of this tap
                    % ErrorDelta = |Coeff * MaxInput|
                    cost = sortedVals(k) * obj.MaxInputVal;
                    
                    if (accumulatedErrorCost + cost) < slack
                        % We can afford to turn this off
                        accumulatedErrorCost = accumulatedErrorCost + cost;
                        tapsToDisableIndices(end+1) = originalIndices(k);
                    else
                        % Cannot afford any more
                        break;
                    end
                end
                
                % Create new mask
                newMask = ones(size(lmsObj.TapWeights));
                newMask(tapsToDisableIndices) = 0;
                
                % Force Main Cursor (Max Tap) to stay ON for safety
                [~, maxIdx] = max(absTaps);
                newMask(maxIdx) = 1;

                obj.CurrentMask = newMask;
            end

            % Reset Counter and return
            obj.MaxCycleError = 0;
            obj.IterationCounter = 0;
            mask = obj.CurrentMask;
        end
    end
end