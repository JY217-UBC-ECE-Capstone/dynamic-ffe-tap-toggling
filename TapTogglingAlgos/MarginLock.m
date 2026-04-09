classdef MarginLock < handle
    % Version: 0.1
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

        cooldownPeriod
        errCollectionPeriod

        initialErrCounter
        maxErr
        runningMeanErr
        errCounter
        cooldownCounter
        reachedHighCOM
        reducedErrSeqCounter
        increasedErrSeqCounter
    end

    methods
        function obj = MarginLock(LMSUpdateObj)
            obj.lastDisabledTap = -1;
            obj.internalFFETapsMask = LMSUpdateObj.FFE_TapsMask;
            obj.lastUpdateTime = LMSUpdateObj.StartFFEAdaptTime * LMSUpdateObj.WindowSize;
            obj.reachedHighErr = 0;

            obj.cooldownPeriod = 2;
            obj.errCollectionPeriod = 10;

            obj.initialErrCounter = 0;
            obj.maxErr = 0;
            obj.runningMeanErr = 0;
            obj.errCounter = 0;
            obj.cooldownCounter = 0;
            obj.reachedHighCOM = 0;
            obj.reducedErrSeqCounter = 0;
            obj.increasedErrSeqCounter = 0;
        end

        function FFETapsMask = GetFFETapsMask(obj, LMSUpdateObj)
            initialTogglingStart = LMSUpdateObj.LearningRatesAdjustTimes(1) + 8;
            canStartAlgo = LMSUpdateObj.IterCount > initialTogglingStart * LMSUpdateObj.WindowSize;
            errVecSize = max(size(LMSUpdateObj.ErrorVec));
            inCooldown = obj.cooldownCounter > 0;

            dlevDiff1 = LMSUpdateObj.Dlev_0p5 - LMSUpdateObj.Dlev_0p16;
            dlevDiff2 = LMSUpdateObj.Dlev_0p16 - LMSUpdateObj.Dlev_m0p16;
            dlevDiff3 = LMSUpdateObj.Dlev_m0p16 - LMSUpdateObj.Dlev_m0p5;
            minDlevDiff = min([dlevDiff1 dlevDiff2 dlevDiff3]);
            margin = minDlevDiff / 2;

            % if eye is not open yet, monitor when high enough COM is
            % reached
            if canStartAlgo && ~obj.reachedHighCOM && ~obj.reachedHighErr
                obj.maxErr = max(obj.maxErr, max(abs(LMSUpdateObj.ErrorVec)));
                obj.initialErrCounter = obj.initialErrCounter + 1;
            end

            % since maximum error can not be used very accurately for
            % monitoring high COM, the threshold for initial COM becomes 4dB
            if canStartAlgo && ~obj.reachedHighCOM && ~obj.reachedHighErr
                if obj.initialErrCounter >= 3 * LMSUpdateObj.WindowSize
                    approxMinCOM = 20*log10(margin / obj.maxErr);

                    if approxMinCOM >= 4
                        obj.reachedHighCOM = 1;
                    end

                    obj.initialErrCounter = 0;
                    obj.maxErr = 0;
                end
            end
            
            if canStartAlgo && ~inCooldown && obj.reachedHighCOM && ~obj.reachedHighErr
                obj.runningMeanErr = (sum(abs(LMSUpdateObj.ErrorVec)) + obj.runningMeanErr * obj.errCounter * errVecSize) / ((obj.errCounter + 1) * errVecSize);
                obj.errCounter = obj.errCounter + 1;
            end

            if canStartAlgo && inCooldown && ~obj.reachedHighErr
                obj.cooldownCounter = obj.cooldownCounter - 1;
            end

            weights = abs(LMSUpdateObj.TapWeights);

            % Take into account the neighboring taps as well
            weights_padded = [0 weights 0];
            weights_avg = (weights_padded(1:end-2) + 2*weights_padded(2:end-1) + weights_padded(3:end)) / 3;
            weights_avg(~obj.internalFFETapsMask) = inf;

            [~, minTapIndex] = min(weights_avg);

            if obj.errCounter >= obj.errCollectionPeriod * LMSUpdateObj.WindowSize && ~obj.reachedHighErr
                std = obj.runningMeanErr * sqrt(pi / 2);
                %std = std * 1.05; % due to ISI, samples are not all iid, so std is within +-5% with 95% CI
                possibleMaxErr = 4.75 * std; % trying to find COM over 1e6 symbols with 90% confidence => using 5std
                statMinCOM = 20*log10(margin / possibleMaxErr);

                if statMinCOM >= 3
                    % Stop the LMS adaptation of FFE and DFE taps
                    LMSUpdateObj.setLearningRates(0, 0, LMSUpdateObj.MuDlev);

                    obj.internalFFETapsMask(minTapIndex) = 0;
                    obj.lastDisabledTap = minTapIndex;
                    obj.lastUpdateTime = LMSUpdateObj.IterCount;

                    % cooldown for some LMS iterations so that other taps can
                    % adapt to the recently turned off tap and then start
                    % measuring the error distribution
                    obj.cooldownCounter = obj.cooldownPeriod * LMSUpdateObj.WindowSize;
                else
                    obj.reachedHighErr = 1;
                    if obj.lastDisabledTap ~= -1
                        obj.internalFFETapsMask(obj.lastDisabledTap) = 1;
                    end
    
                    % to make sure it throws an error in case tried being accessed
                    obj.lastDisabledTap = -1;
                end

                obj.errCounter = 0;
                obj.runningMeanErr = 0;
            end
        
            FFETapsMask = obj.internalFFETapsMask;
        end
    end
end