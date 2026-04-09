classdef LeveragedLMS < handle
    % Version: 0.2 (min-COM-based)
    % Description:
    %   If the smallest registered COM is above 3dB for some period,
    %   then assume it is safe to turn off the most "insignificant"
    %   tap (which now is, kind of, the smallest one)
    %
    %   However, if smallest COM drops below 3dB for some period,
    %   then activate the fallback mechanism and turn on the recently
    %   disabled tap and terminate the algorithm
    
    properties
        lastDisabledTap
        internalFFETapsMask
        lastUpdateTime
        reachedHighErr

        lastMeanErr
        maxErr
        reachedHighCOM
        reducedErrSeqCounter
        increasedErrSeqCounter

        targetCounters
        targetCounterIndex
    end

    methods
        function obj = LeveragedLMS(LMSUpdateObj)
            obj.lastDisabledTap = -1;
            obj.internalFFETapsMask = LMSUpdateObj.FFE_TapsMask;
            obj.lastUpdateTime = LMSUpdateObj.StartFFEAdaptTime * LMSUpdateObj.WindowSize;
            obj.reachedHighErr = 0;

            obj.lastMeanErr = inf;
            obj.maxErr = 0;
            obj.reachedHighCOM = 0;
            obj.reducedErrSeqCounter = 0;
            obj.increasedErrSeqCounter = 0;

            obj.targetCounters = [2 1];
            obj.targetCounterIndex = 1;
        end

        function FFETapsMask = GetFFETapsMask(obj, LMSUpdateObj)
            initialTogglingStart = LMSUpdateObj.StartFFEAdaptTime + 5;

            if ismember(LMSUpdateObj.IterCount, LMSUpdateObj.LearningRatesAdjustTimes * LMSUpdateObj.WindowSize)
                obj.targetCounterIndex = obj.targetCounterIndex + 1;
            end

            obj.maxErr = max(obj.maxErr, max(abs(LMSUpdateObj.ErrorVec)));

            if mod(LMSUpdateObj.IterCount, LMSUpdateObj.WindowSize) == 0 && ...
                    LMSUpdateObj.IterCount > initialTogglingStart * LMSUpdateObj.WindowSize && ~obj.reachedHighErr
                %avgErr = mean(abs(LMSUpdateObj.ErrorVec));

                dlevDiff1 = LMSUpdateObj.Dlev_0p5 - LMSUpdateObj.Dlev_0p16;
                dlevDiff2 = LMSUpdateObj.Dlev_0p16 - LMSUpdateObj.Dlev_m0p16;
                dlevDiff3 = LMSUpdateObj.Dlev_m0p16 - LMSUpdateObj.Dlev_m0p5;
                minDlevDiff = min([dlevDiff1 dlevDiff2 dlevDiff3]);
                t = minDlevDiff / 2;

                minCOM = 20*log10(t / obj.maxErr);

                if minCOM >= 3
                    obj.reducedErrSeqCounter = obj.reducedErrSeqCounter + 1;
                    obj.increasedErrSeqCounter = 0;
                    obj.reachedHighCOM = 1;
                else
                    obj.reducedErrSeqCounter = 0;
                    if obj.reachedHighCOM
                        obj.increasedErrSeqCounter = obj.increasedErrSeqCounter + 1;
                    end
                end
                %obj.lastMeanErr = avgErr * 1.125;

                obj.maxErr = 0;
            end

            weights = abs(LMSUpdateObj.TapWeights);

            % Take into account the neighboring taps as well
            weights_padded = [0 weights 0];
            weights_avg = (weights_padded(1:end-2) + 2*weights_padded(2:end-1) + weights_padded(3:end)) / 3;
            weights_avg(~obj.internalFFETapsMask) = inf;

            [~, minTapIndex] = min(weights_avg);

            if obj.reducedErrSeqCounter == obj.targetCounters(obj.targetCounterIndex) && ...
                    LMSUpdateObj.IterCount > initialTogglingStart * LMSUpdateObj.WindowSize && ~obj.reachedHighErr
                obj.internalFFETapsMask(minTapIndex) = 0;
                obj.lastDisabledTap = minTapIndex;
                obj.lastUpdateTime = LMSUpdateObj.IterCount;
                obj.reducedErrSeqCounter = 0;
                obj.increasedErrSeqCounter = 0;
            end
        
            if obj.increasedErrSeqCounter == obj.targetCounters(obj.targetCounterIndex)*2 && ~obj.reachedHighErr
                obj.reachedHighErr = 1;
                if obj.lastDisabledTap ~= -1
                    obj.internalFFETapsMask(obj.lastDisabledTap) = 1;
                end

                % to make sure it throws an error in case tried being accessed
                obj.lastDisabledTap = -1;
                obj.reducedErrSeqCounter = 0;
                obj.increasedErrSeqCounter = 0;
            end
        
            FFETapsMask = obj.internalFFETapsMask;
        end
    end
end