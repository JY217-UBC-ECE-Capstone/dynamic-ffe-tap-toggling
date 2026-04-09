function mask = MinCoeff(taps, toggleCount, ~)
            mask = ones(size(taps));
            
            [~, sortedIdx] = sort(abs(taps), 'ascend');
            zeroIdx = sortedIdx(1:toggleCount);
            
            mask(zeroIdx) = 0;
        end