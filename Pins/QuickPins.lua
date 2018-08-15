
local LIB_NAME = "LibQuickPin2"
local LIB_VERSION = 1
local lib, version = LibStub:NewLibrary(LIB_NAME, LIB_VERSION)

--[[
Not for general use. This lib is tailored for HarvestMap.

This lib increases the performance when displaying thousands of pins.
- creating 2000 pins is reduced from 600 ms to 10ms on live and 60ms to 7ms on PTS (Summerset)
Main technical differences:
- Each pin is only a single texture control (ZOS' pins are 3 controls) which reduces the cost when changing the offset of a pins' anchor
- No ClearAnchor() to remove the need for ZOS' internal cycle detection when re-anchoring the pins (immense cost reduction on live)
- Reusing controls of the same pinType to remove the slow calls to SetTexture(...)
- Pre-pooling/creation of controls during the loading screen, because the first creations of controls is slow, but just changing the offset of a control's anchor is fast.
]]


if not lib then
    return
end

local QP_MapPin = ZO_Object:Subclass()
lib.QP_MapPin = QP_MapPin
QP_MapPin.pinId = 1

function QP_MapPin:New(layout)
    local pin = ZO_Object.New(self)
	
    local control = CreateControl("QP_MapPin" .. self.pinId, lib.Container, CT_TEXTURE)
	control:SetPixelRoundingEnabled(false)
	control:SetMouseEnabled(true)
	control:SetHandler("OnMouseUp", QP_MapPin.OnMouseUp)
	control:SetHandler("OnMouseEnter", QP_MapPin.OnMouseEnter)
	control:SetHandler("OnMouseExit", QP_MapPin.OnMouseExit)
	control:SetAnchor(CENTER, lib.Container, TOPLEFT, 0, 0)
		
    control.m_Pin = pin
    pin.m_Control = control
	pin.m_layout = layout
	pin:RefreshLayout()
	
    self.pinId = self.pinId + 1
	lib.numCreatedPins = lib.numCreatedPins + 1
    return pin
end

function QP_MapPin:OnMouseEnter(...)
	self.m_Pin:SetTargetScale(1.3)
end

function QP_MapPin:OnMouseExit()
	self.m_Pin:SetTargetScale(1)
end

function QP_MapPin:SetTargetScale(targetScale)
    if((self.targetScale ~= nil and targetScale ~= self.targetScale) or (self.targetScale == nil and targetScale ~= self.m_Control:GetScale())) then
        self.targetScale = targetScale
        EVENT_MANAGER:RegisterForUpdate(self.m_Control:GetName(), 0, function()
            local newScale = zo_deltaNormalizedLerp(self.m_Control:GetScale(), self.targetScale, 0.17)
            if(zo_abs(newScale - self.targetScale) < 0.01) then
                self.m_Control:SetScale(self.targetScale)
                self.targetScale = nil
                EVENT_MANAGER:UnregisterForUpdate(self.m_Control:GetName())
            else
                self.m_Control:SetScale(newScale)
            end
        end)
		
    end
end

function QP_MapPin:OnMouseUp(button, upInside, ctrl, alt, shift, command)
	if upInside and button == MOUSE_BUTTON_INDEX_LEFT then
		for i, handler in ipairs(self.m_Pin.m_layout.OnClickHandler) do
			if (not handler.show) or handler.show(self.m_Pin) then
				handler.callback(self.m_Pin, button)
				return
			end
		end
	end
	ZO_WorldMap_MouseUp(ZO_WorldMapContainer, button, MouseIsOver(ZO_WorldMapScroll))
end

function QP_MapPin:RefreshLayout()
	local control = self.m_Control
	local layout = self.m_layout
	control:SetTexture(layout.texture)
	control:SetDrawLevel(zo_max(layout.level, 1))

	if(layout.tint) then
		control:SetColor(self.m_layout.tint:UnpackRGBA())
	else
		control:SetColor(1, 1, 1, 1)
	end
end

function QP_MapPin:GetPinTypeAndTag()
	return self.m_PinType, self.m_PinTag
end

function QP_MapPin:SetData(pinType, pinTag)
	self.m_PinType = pinType
	self.m_PinTag = pinTag
end

function QP_MapPin:ClearData()
	self.m_PinType = nil
    self.m_PinTag = nil
end

local MIN_PIN_SIZE = 8
function QP_MapPin:UpdateSize()
	local size = self.m_layout.currentPinSize
	self.m_Control:SetDimensions(size, size)
	local inset = 0.25 * size
	self.m_Control:SetHitInsets(inset, inset, -inset, -inset)
end

function QP_MapPin:UpdateLocation()
    self.m_Control:SetAnchor(CENTER, lib.Container, TOPLEFT,
		self.normalizedX * lib.MAP_WIDTH,
		self.normalizedY * lib.MAP_HEIGHT)
end

function QP_MapPin:SetLocation(xLoc, yLoc)
    self.m_Control:SetHidden(false)

    self.normalizedX = xLoc
    self.normalizedY = yLoc

    self:UpdateLocation()
    self:UpdateSize()
end


function lib:GetUnusedPin(layout)
	local index = lib.unusedPins.index
	if index > 0 then
		lib.unusedPins.index = index - 1
		local pin = lib.unusedPins[index]
		pin.m_layout = layout
		pin:RefreshLayout()
		return pin
	end
end

QP_WorldMapPins = ZO_ObjectPool:Subclass()

function QP_WorldMapPins:New(layout)
    local factory = function(pool) return lib:GetUnusedPin(layout) or QP_MapPin:New(layout) end
    local reset = function(pin)
		pin:ClearData()
		pin.m_Control:SetHidden(true)
	end
	local pinManager = ZO_ObjectPool.New(self, factory, reset)
	pinManager.m_Layout = layout
	pinManager:UpdateSize()
    return pinManager
end

function QP_WorldMapPins:UpdateSize()
	local layout = self.m_Layout
	local minSize = layout.minSize or MIN_PIN_SIZE
	local zoom = lib.zoom.currentZoom / lib.maxZoom
	local scale = 1
	if not ZO_WorldMap_IsWorldMapShowing() then -- minimap
		if FyrMM then
			scale = FyrMM.pScalePercent
		end
		if AUI and AUI.Minimap:IsEnabled() then
			zoom = AUI.Minimap.GetCurrentZoomValue() / 15
		end
		if VOTANS_MINIMAP and VOTANS_MINIMAP.scale then
			scale = VOTANS_MINIMAP.scale
		end
	end
	local size = zo_max(layout.size * (0.4 * zoom + 0.6) / GetUICustomScale(), minSize)
	size = size * scale
	layout.currentPinSize = size
end

function lib:UpdatePinsForMapSizeChange(width, height)
	self.MAP_WIDTH, self.MAP_HEIGHT = width, height
	
	for pinType, pinManager in pairs(self.pinManagers) do
		pinManager:UpdateSize()
		local pins = pinManager:GetActiveObjects()
		for pinKey, pin in pairs(pins) do
			pin:UpdateLocation()
			pin:UpdateSize()
		end
	end
	
	local isMinimap = false
	if not ZO_WorldMap_IsWorldMapShowing() then -- minimap
		isMinimap = FyrMM or (AUI and AUI.Minimap:IsEnabled()) or VOTANS_MINIMAP
	end
	
	for identifier, callback in pairs(self.mapModeCallbacks) do
		callback(isMinimap)
	end
end

function lib:RegisterMapModeCallback(identifier, callback)
	self.mapModeCallbacks[identifier] = callback
end

function lib.RedrawPins()
	for pinType, callback in pairs(lib.PIN_CALLBACKS) do
		lib:RedrawPinsOfPinType(pinType)
	end
end

function lib:RefreshPinsOfPinType(pinType)
	if not self.PIN_CALLBACKS[pinType] then return end
	self:RemovePinsOfPinType(pinType)
	local pinManager = self.pinManagers[pinType]
	if pinManager then
		pinManager:UpdateSize()
		for pinKey, pin in pairs(pinManager.m_Free) do
			pin:RefreshLayout()
		end
	end
	self.PIN_CALLBACKS[pinType]()
end

function lib:RedrawPinsOfPinType(pinType)
	if not self.PIN_CALLBACKS[pinType] then return end
	self:RemovePinsOfPinType(pinType)
	local pinManager = self.pinManagers[pinType]
	if pinManager then
		pinManager:UpdateSize()
	end
	self.PIN_CALLBACKS[pinType]()
end

function lib:RemovePinsOfPinType(pinType)
	if not self.pinManagers[pinType] then return end
	self.pinManagers[pinType]:ReleaseAllObjects()
	self.lookUpTable[pinType] = {}
end

function lib:RegisterPinType(pinType, callback, layout)
	assert(self.PIN_LAYOUTS[pinType] == nil)
	self.PIN_LAYOUTS[pinType] = layout
	self.PIN_CALLBACKS[pinType] = callback
	self.lookUpTable[pinType] = {}
	if layout then
		local pinManager = QP_WorldMapPins:New(layout)
		--if layout.expectedPinCount then
		--	for i = 1, layout.expectedPinCount do
		--		pinManager:AcquireObject()
		--	end
		--	pinManager:ReleaseAllObjects()
		--end
		self.pinManagers[pinType] = pinManager
	end
end

function lib:CreatePin(pinType, pinTag, x, y)
	assert(self.pinManagers[pinType], pinType)
	local pin, pinKey = self.pinManagers[pinType]:AcquireObject()
	self.lookUpTable[pinType][pinTag] = pinKey
	pin:SetData(pinType, pinTag)
	pin:SetLocation(x, y)
	return pin
end

function lib:RemovePin(pinType, pinTag)
	self.pinManagers[pinType]:ReleaseObject(self.lookUpTable[pinType][pinTag])
	self.lookUpTable[pinType][pinTag] = nil
end
-- same syntax as LMP
lib.RemoveCustomPin = lib.RemovePin
lib.FindCustomPin = function() end

function lib.Init()
	
	if lib.initialized then return end
	lib.initialized = true
	EVENT_MANAGER:UnregisterForEvent(LIB_NAME, EVENT_PLAYER_ACTIVATED)
	
	
	ZO_PreHook(ZO_WorldMapPins, "UpdatePinsForMapSizeChange", function() lib:UpdatePinsForMapSizeChange(ZO_WorldMapContainer:GetDimensions()) end)
	ZO_PreHook("ZO_WorldMap_UpdateMap", lib.RedrawPins)
	ZO_PreHook(lib.zoom, "SetZoomMinMax", function(self, min, max)
		--d("set min max", min, max)
		--d("cur dimensions", ZO_WorldMapContainer:GetDimensions())
		lib.minZoom = min
		lib.maxZoom = max
		lib:UpdatePinsForMapSizeChange(ZO_WorldMapContainer:GetDimensions())
	end)
	
end

function lib:HookMinimap(minimapContainer)

	WORLD_MAP_FRAGMENT:RegisterCallback("StateChange", function(oldState, newState)
		if newState == SCENE_FRAGMENT_HIDDEN then
			self.Container:SetAnchor(TOPLEFT, minimapContainer, TOPLEFT, 0, 0)
			self.Container:SetParent(minimapContainer)
			local width, height = minimapContainer:GetDimensions()
			if self.MAP_WIDTH ~= width or self.MAP_HEIGHT ~= height then
				lib:UpdatePinsForMapSizeChange(width, height)
			end
		elseif newState == SCENE_FRAGMENT_SHOWING then
			self.Container:SetAnchor(TOPLEFT, ZO_WorldMapContainer, TOPLEFT, 0, 0)
			self.Container:SetParent(ZO_WorldMapContainer)
		end
	end)
	
	self.Container:SetAnchor(TOPLEFT, minimapContainer, TOPLEFT, 0, 0)
	self.Container:SetParent(minimapContainer)
			
	local oldDimensions = minimapContainer.SetDimensions
	minimapContainer.SetDimensions = function(self, width, height, ...)
		if not ZO_WorldMap_IsWorldMapShowing() then
			lib:UpdatePinsForMapSizeChange(width, height)
		end
		oldDimensions(self, width, height, ...)
	end
	
end

local layout = { texture="", level = 0 }
function lib.OnUpdate()
	local numMissingPins = lib.numRequestedPins - lib.numCreatedPins
	if numMissingPins <= 0 then
		EVENT_MANAGER:UnregisterForUpdate(LIB_NAME)
		return
	end
	local num = numMissingPins--zo_min(numMissingPins, 100)
	for i = lib.unusedPins.index + 1, lib.unusedPins.index + num do
		lib.unusedPins[i] = QP_MapPin:New(layout)
	end
	lib.unusedPins.index = lib.unusedPins.index + num
end

function lib:PreloadControls(num)
	self.numRequestedPins = num
	--EVENT_MANAGER:UnregisterForUpdate(LIB_NAME)
	--EVENT_MANAGER:RegisterForUpdate(LIB_NAME, 0, self.OnUpdate)
	lib.OnUpdate()--
end

function lib:Unload()
	EVENT_MANAGER:UnregisterForEvent(LIB_NAME, EVENT_PLAYER_ACTIVATED)
end

function lib:Load()
	EVENT_MANAGER:UnregisterForEvent(LIB_NAME, EVENT_PLAYER_ACTIVATED)
	EVENT_MANAGER:RegisterForEvent(LIB_NAME, EVENT_PLAYER_ACTIVATED, lib.Init)
	
	self.numCreatedPins = 0
	self.numRequestedPins = 0
	self.mapModeCallbacks = {}
	
	self.PIN_LAYOUTS = self.PIN_LAYOUTS or {}
	self.PIN_CALLBACKS = self.PIN_CALLBACKS or {}
	self.lookUpTable = {}
	self.pinManagers = {} -- todo implement a way to retrieve the previous pinmanager
	self.Container = self.Container or CreateControl("QP_Container" , ZO_WorldMapContainer, CT_CONTROL)
	self.Container:SetAnchor(TOPLEFT, ZO_WorldMapContainer, TOPLEFT, 0, 0)
	
	if Fyr_MM then
		self:HookMinimap(Fyr_MM_Scroll_Map)
	elseif AUI and AUI.Minimap then
		ASD = true
		self:HookMinimap(AUI_MapContainer)
	end
	
	self.zoom = ZO_WorldMap_GetPanAndZoom()
	lib.minZoom, lib.maxZoom = self.zoom.minZoom, self.zoom.maxZoom
	
	self.unusedPins = {}
	self.unusedPins.index = 0
end

if lib.version and lib.version < LIB_VERSION then
	lib:Unload()
else
	lib:Load()
end
