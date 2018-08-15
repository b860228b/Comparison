
local LIB_NAME = "LibQuickPin"
local lib = LibStub:NewLibrary(LIB_NAME, 2)

if not lib then
    return
end

lib.RegisteredPinTypes = {}

function lib:RegisterPinType(pinType)
	local pinTypeId
	if type(pinType) == "string" then
		pinTypeId = _G[pinType]
	elseif type(pinType) == "number" then
		pinTypeId = pinType
	end
	self.RegisteredPinTypes[pinTypeId] = true
end

function lib:UnregisterPinType(pinType)
	local pinTypeId
	if type(pinType) == "string" then
		pinTypeId = _G[pinType]
	elseif type(pinType) == "number" then
		pinTypeId = pinType
	end
	self.RegisteredPinTypes[pinTypeId] = nil
end

function lib.Init()
	
	if lib.initialized then return end
	lib.initialized = true
	EVENT_MANAGER:UnregisterForEvent(LIB_NAME, EVENT_ADD_ON_LOADED)
	
	-- register all default pin types
	for pinType = MAP_PIN_TYPE_ITERATION_BEGIN, MAP_PIN_TYPE_ITERATION_END do
		lib:RegisterPinType(pinType)
	end
	
	-- help function to replace ClearAnchors of the pins
	local emptyFunction = function() end
	local function replaceClearAnchor(control)
		-- check if simply replacing the anchor is valid, and we do not have to call ClearAnchors
		local isFirstAnchorValid = select(2, control:GetAnchor(0)) == CENTER or not control:GetAnchor(0)
		local isSecondAnchorValid = not control:GetAnchor(1)
		
		if isFirstAnchorValid and isSecondAnchorValid then
			local origFunction = control.ClearAnchors
			control.ClearAnchors = emptyFunction
			return origFunction
		end
	end
	
	-- hook which will remove ClearAnchors to improve performance
	local function HookPinClass(PinClass)
		local origUpdateLocation = PinClass.UpdateLocation
		PinClass.UpdateLocation = function(self, ...)
			-- don't manipulate anything unless an addon registered their pinType
			if lib.RegisteredPinTypes[self.m_PinType] then
				-- replace the ClearAnchors functions
				local control = self:GetControl()
				local origClear, origClearBlob
				origClear = replaceClearAnchor(control)
				if self.pinBlob then
					origClearBlob = replaceClearAnchor(self.pinBlob)
				end
				-- update the pin location
				origUpdateLocation(self, ... )
				-- revert the ClearAnchors change again
				if origClear then control.ClearAnchors = origClear end
				if origClearBlob then self.pinBlob.ClearAnchors = origClearBlob end
				
				return
			end
			-- otherwise, perform default behaviour
			origUpdateLocation(self, ... )
		end
	end
	HookPinClass(ZO_MapPin)
	--if AUI_Pin then HookPinClass(AUI_Pin) end
end

EVENT_MANAGER:UnregisterForEvent(LIB_NAME, EVENT_ADD_ON_LOADED)
EVENT_MANAGER:RegisterForEvent(LIB_NAME, EVENT_ADD_ON_LOADED, lib.Init)
