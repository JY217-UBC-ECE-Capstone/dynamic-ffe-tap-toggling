classdef TriggeredComponent < handle
    %Triggered Clock Component
    %
% NumberOfClocks

    %   Copyright 2020 The MathWorks, Inc.
    
    %#codegen
    properties (Abstract)
        
        NumberOfClocks %Number of clock phases
        
    end
    properties (Hidden, SetAccess=protected)
        
        %triggered component properties
        
        ClockPrevious ; % Previous clock
        ClockCurrent  ; % Current  clock
        ClockRisingFlag   ; % Clock rising  edge  detect
        ClockFallingFlag   ; % Clock falling edge  detect
        PhaseRisingIndex ; % Clock phase with rising  edge detected
        PhaseFallingIndex ; % Clock phase with falling edge detected
    end
    
    methods
        % Constructor
        function obj = TriggeredComponent(varargin)
            % Support name-value pair arguments when constructing object
            %setProperties(obj,nargin,varargin{:})
        end
    end
    
    methods(Access = protected)
        %% Common functions
        function setupClock(obj)
            
            % Initialize buffers
            obj.ClockPrevious     = double(nan(obj.NumberOfClocks, 1));
            obj.ClockCurrent      = double(nan(obj.NumberOfClocks, 1));            
            obj.ClockRisingFlag   = false(obj.NumberOfClocks, 1);
            obj.ClockFallingFlag  = false(obj.NumberOfClocks, 1);
            obj.PhaseRisingIndex  = 0;
            obj.PhaseFallingIndex = 0;
        end
        
        function ClockStep(obj,ClockIn)
            
            %Triggered clock step
            
            % Update buffers
            obj.ClockPrevious = obj.ClockCurrent;
            obj.ClockCurrent = ClockIn     ;
            
            % Detect clock zero crossing, rising and falling edges
            obj.ClockRisingFlag = (obj.ClockPrevious <= 0) & (obj.ClockCurrent >  0);
            obj.ClockFallingFlag = (obj.ClockPrevious >  0) & (obj.ClockCurrent <= 0);
                        
            % On clock rising edge: get phase index with rising edge
            % If no rising edge, set index to zero
            % Assume only one phase has a rising edge
            if sum(obj.ClockRisingFlag) > 0
                [~, obj.PhaseRisingIndex] = max(obj.ClockRisingFlag);
            else
                obj.PhaseRisingIndex = 0;
            end
            
            % On clock falling edge: get phase index with falling edge
            % If no falling edge, set index to zero
            % Assume only one phase has a falling edge
            if sum(obj.ClockFallingFlag) > 0
                [~, obj.PhaseFallingIndex] = max(obj.ClockFallingFlag);
            else
                obj.PhaseFallingIndex = 0;
            end
        end
    end
end
