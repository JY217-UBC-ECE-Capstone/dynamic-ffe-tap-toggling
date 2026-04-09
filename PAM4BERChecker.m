classdef (StrictDefaults) PAM4BERChecker < matlab.System & matlab.system.mixin.Propagates
    % PAM4BERCheckerWithIgnore
    % Calculates Bit Error Rate (BER) for PAM4 signals.
    % 
    % UPDATED: 
    % 1. Includes Clock input for edge-triggered checking.
    % 2. Auto-detects if TxSymsIn is Voltage or Integer.
    % 3. Adds TxDelay to compensate for Channel/DFE latency.
    % 4. FIXED: Codegen error by ensuring TxBuffer state remains constant size.
    % 
    % Inputs:
    %   TxSymsIn:    Transmitted symbols (Integers 0-3 OR Voltages).
    %   RxDecisions: Decision voltages from the DFE/Receiver.
    %   ClockIn:     The Demux Clock signal.
    %
    % Outputs:
    %   TotalBitErrors: Cumulative bit errors counted *after* the ignore period.
    %   BER:            Bit Error Rate calculated *after* the ignore period.

    %#codegen

    properties (Nontunable)
        % DemuxWidth
        % Width of the parallel data path (must match your DFE/Bridge)
        DemuxWidth = 32;

        % IgnoreSymbols
        % Number of symbols to ignore at the start of the simulation 
        % (allows equalizer/CDR to adapt before counting errors).
        IgnoreSymbols = 1000;
        
        % TxDelay
        % Number of symbols to delay the Tx stream to align with Rx.
        % (Use this to compensate for Channel + DFE Latency)
        TxDelay = 0;
    end

    properties (Access = private)
        % Hardcoded thresholds based on standard PAM4 levels [-0.5, -0.16, 0.16, 0.5]
        ThreshLower = -0.3333; % -1/3
        ThreshMid   = 0.0;
        ThreshUpper = 0.3333;  %  1/3
        
        % Internal State Counters
        ErrorCount;       % Errors counted after the ignore period
        ValidBitCount;    % Bits processed after the ignore period
        SymbolsProcessed; % Total symbols seen since simulation start
        
        % Edge Detection State
        PreviousClock;
        
        % Buffer for Tx Delay
        % Must maintain CONSTANT size [TxDelay x 1] for Code Generation
        TxBuffer;
    end

    methods (Access = protected)
        function setupImpl(obj)
            obj.ErrorCount = 0;
            obj.ValidBitCount = 0;
            obj.SymbolsProcessed = 0;
            obj.PreviousClock = 0;
            
            % Initialize buffer with zeros equal to the requested delay.
            % The size of this property is locked at setup for Codegen.
            obj.TxBuffer = zeros(obj.TxDelay, 1);
        end

        function [TotalBitErrors, BER] = stepImpl(obj, TxSymsIn, RxDecisions, ClockIn)
            % Detect Rising Edge of the Clock
            isFallingEdge = (ClockIn < 0.5) && (obj.PreviousClock >= 0.5);
            obj.PreviousClock = ClockIn;

            if isFallingEdge
                
                % 1. Handle Tx Delay (Fixed-Size State Pattern)
                % Concatenate the History (TxBuffer) with New Data (TxSymsIn)
                % combinedTx size = TxDelay + InputSize
                combinedTx = [obj.TxBuffer; TxSymsIn(:)];
                
                % Extract the oldest 'DemuxWidth' symbols for processing.
                % NOTE: Logic assumes size(TxSymsIn) == DemuxWidth. 
                % If inputs are larger/smaller, ensure DemuxWidth parameter matches.
                currentTxRaw = combinedTx(1:obj.DemuxWidth);
                
                % Update the History (State)
                % We save the remaining tail as the new history.
                % New Size = (TxDelay + DemuxWidth) - DemuxWidth = TxDelay
                % This ensures obj.TxBuffer size never changes, fixing the Codegen error.
                obj.TxBuffer = combinedTx(obj.DemuxWidth+1:end);

                % 2. Auto-Detect Tx Format (Voltage vs Integer)
                % If we see negative values, it's definitely Voltage.
                if any(currentTxRaw < 0)
                    % Slice Voltage -> Integer
                    txInts = obj.sliceVoltages(currentTxRaw);
                else
                    % Assume it's already Integer (0, 1, 2, 3)
                    txInts = currentTxRaw;
                end
                
                % 3. Check Ignore Period
                startIdx = 1;
                if obj.SymbolsProcessed < obj.IgnoreSymbols
                    remainingToIgnore = obj.IgnoreSymbols - obj.SymbolsProcessed;
                    if remainingToIgnore >= obj.DemuxWidth
                        startIdx = obj.DemuxWidth + 1; % Ignore all
                    else
                        startIdx = remainingToIgnore + 1; % Ignore partial
                    end
                end
                
                % Update symbol counter
                obj.SymbolsProcessed = obj.SymbolsProcessed + obj.DemuxWidth;
    
                % 4. Process Valid Portion
                currentBlockErrors = 0;
                currentBlockBits = 0;
    
                if startIdx <= obj.DemuxWidth
                    % Slice inputs to valid range
                    validTx = txInts(startIdx:end);
                    validRxRaw = RxDecisions(startIdx:end);
                    
                    % Slice Rx Voltages into Integers (0, 1, 2, 3)
                    validRxInts = obj.sliceVoltages(validRxRaw);
    
                    % Convert both to Bits (Gray Coded)
                    [txMSB, txLSB] = obj.mapSymbolsToGrayBits(validTx);
                    [rxMSB, rxLSB] = obj.mapSymbolsToGrayBits(validRxInts);
    
                    % Count Errors
                    validLength = length(validTx);
                    for i = 1:validLength
                        if txMSB(i) ~= rxMSB(i)
                            currentBlockErrors = currentBlockErrors + 1;
                        end
                        if txLSB(i) ~= rxLSB(i)
                            currentBlockErrors = currentBlockErrors + 1;
                        end
                    end
                    
                    currentBlockBits = validLength * 2;
                end
    
                % 5. Update States
                obj.ErrorCount = obj.ErrorCount + currentBlockErrors;
                obj.ValidBitCount = obj.ValidBitCount + currentBlockBits;
            end

            % 6. Output Results
            TotalBitErrors = uint32(obj.ErrorCount);
            if obj.ValidBitCount > 0
                BER = single(obj.ErrorCount / obj.ValidBitCount);
            else
                BER = single(0);
            end
        end

        function rxInts = sliceVoltages(obj, rxVoltages)
            % Helper to slice float voltages into 0-3 integers
            len = length(rxVoltages);
            rxInts = zeros(len, 1);
            for i = 1:len
                val = rxVoltages(i);
                if val < obj.ThreshLower
                    rxInts(i) = 0;
                elseif val < obj.ThreshMid
                    rxInts(i) = 1;
                elseif val < obj.ThreshUpper
                    rxInts(i) = 2;
                else
                    rxInts(i) = 3;
                end
            end
        end

        function [msb, lsb] = mapSymbolsToGrayBits(~, symbols)
            % Maps integer symbols (0-3) to MSB and LSB bits using Gray Coding.
            msb = zeros(size(symbols));
            lsb = zeros(size(symbols));
            
            % MSB is 1 for symbols 2 and 3
            msb(symbols == 2 | symbols == 3) = 1;

            % LSB is 1 for symbols 1 and 2
            lsb(symbols == 1 | symbols == 2) = 1;
        end

        function resetImpl(obj)
            obj.ErrorCount = 0;
            obj.ValidBitCount = 0;
            obj.SymbolsProcessed = 0;
            obj.PreviousClock = 0;
            % Reset buffer to fixed size
            obj.TxBuffer = zeros(obj.TxDelay, 1);
        end

        %% Simulink Interface Definitions
        function [sz1, sz2] = getOutputSizeImpl(~)
            sz1 = [1 1]; sz2 = [1 1];
        end
        function [dt1, dt2] = getOutputDataTypeImpl(~)
            dt1 = 'uint32'; dt2 = 'single';
        end
        function [cp1, cp2] = isOutputComplexImpl(~)
            cp1 = false; cp2 = false;
        end
        function [fx1, fx2] = isOutputFixedSizeImpl(~)
            fx1 = true; fx2 = true;
        end
        
        function [n1, n2, n3] = getInputNamesImpl(~)
            n1 = 'TxSyms'; n2 = 'RxDec'; n3 = 'Clock';
        end
        function [n1, n2] = getOutputNamesImpl(~)
            n1 = 'TotalErrors'; n2 = 'BER';
        end
    end
end