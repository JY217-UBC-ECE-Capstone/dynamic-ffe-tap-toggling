function mask = Threshold(taps, thresholdPercent, ~)
    mask = ones(size(taps));
    maxTapVal = max(abs(taps));
    mask(abs(taps) < thresholdPercent*maxTapVal) = 0;
end