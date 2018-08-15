local Harvest = _G["Harvest"]
local Lib3D = LibStub("Lib3D2")
local GPS = LibStub("LibGPS2")

local PARENT = COMPASS.container
local pairs = _G["pairs"]
local zo_abs = _G["zo_abs"]
local zo_floor = _G["zo_floor"]
local pi = math.pi
local atan2 = math.atan2
local GetFrameTimeMilliseconds = _G["GetFrameTimeMilliseconds"]
local GetPlayerCameraHeading = _G["GetPlayerCameraHeading"]
local GetMapPlayerPosition = _G["GetMapPlayerPosition"]
local CallbackManager = Harvest.callbackManager
local Events = Harvest.events

local InRangePins = {}
Harvest.InRangePins = InRangePins

-- todo range/fov settings + refresh
-- todo add performance type 3d pins (which works like map pins)

function InRangePins:Initialize()
	self.pinUpdateCallback = self.UpdatePin
	self.lastUpdate = {}
	
	CallbackManager:RegisterForEvent(Events.SETTING_CHANGED, function(event, setting, ...)
		if setting == "compassPinsVisible" then
			local visible = ...
			self.displayCompassPins = visible
			self:CheckPause()
			self:RefreshRange()
		elseif setting == "worldPinsVisible" then
			local visible = ...
			self.displayWorldPins = visible
			self:CheckPause()
			if not visible then
				self:RefreshWorldPins()
			end
			self:RefreshRange()
		elseif setting == "worldPinsSimple" then
			local simple = ...
			if simple then
				if self.displayWorldPins then
					self.displayWorldPins = false
					self:CheckPause()
					self:RefreshWorldPins()
				end
			else
				local visible = Harvest.AreWorldPinsVisible()
				if visible ~= self.displayWorldPins then
					self.displayWorldPins = visible
					self:CheckPause()
				end
			end
			self:RefreshRange()
		elseif setting == "compassDistance" or setting == "worldDistance" then
			self:RefreshRange()
		elseif setting == "pinTypeColor" or setting == "mapPinTexture" then
			self:RefreshAllPins()
		elseif setting == "worldPinsUseDepth" then
			local useDepth = ...
			local beam, icon
			for _, control in pairs(self.worldControlPool:GetActiveObjects()) do
				beam = control:GetNamedChild("Beam")
				icon = control:GetNamedChild("Icon")
				control:Set3DRenderSpaceUsesDepthBuffer(useDepth)
				beam:Set3DRenderSpaceUsesDepthBuffer(useDepth)
				icon:Set3DRenderSpaceUsesDepthBuffer(useDepth)
			end
			self.useDepth = useDepth
		elseif setting:match("PinTypeVisible$") then
			local pinTypeId, visible = ...
			if self.zoneCache and visible then
				for map, mapCache in pairs(self.zoneCache.mapCaches) do
					Harvest.Data:CheckPinTypeInCache(pinTypeId, mapCache)
				end
			end
		elseif setting:match("FilterActive$") then
			local active = ...
			if self.zoneCache and active then
				for map, mapCache in pairs(self.zoneCache.mapCaches) do
					for _, pinTypeId in ipairs(Harvest.PINTYPES) do
						Harvest.Data:CheckPinTypeInCache(pinTypeId, mapCache)
					end
				end
			end
		end
	end)
	
	CallbackManager:RegisterForEvent(Events.NODE_UPDATED, function(event, map, pinTypeId, nodeId)
		if not self.zoneCache then return end
		if not self.zoneCache:DoesHandleMap(map) then return end
		
		local key = self.compassKeys[map][nodeId]
		if key then
			self.compassControlPool:ReleaseObject(key)
			self.compassKeys[map][nodeId] = nil
		end
		key = self.worldKeys[map][nodeId]
		if key then
			self.worldControlPool:ReleaseObject(key)
			self.worldKeys[map][nodeId] = nil
		end
	end)
	
	CallbackManager:RegisterForEvent(Events.NEW_ZONE_ENTERED, function(event, zoneCache, distanceCorrection)
		Harvest.Debug("change 3d/compass pins to zone " .. tostring(zoneIndex))
		self.zoneCache = zoneCache
		self.distanceCorrection = distanceCorrection
		self:RefreshAllPins()
	end)
	
	CallbackManager:RegisterForEvent(Events.MAP_ADDED_TO_ZONE, function(event, mapCache, zoneCache)
		if zoneCache ~= self.zoneCache then return end
		Harvest.Debug("added a new map to 3d/compass pins " .. mapCache.map)
		self.worldKeys[mapCache.map] = {}
		self.compassKeys[mapCache.map] = {}
		self.lastUpdate[mapCache.map] = {}
	end)
	
	self.compassControlPool = ZO_ControlPool:New("HM_CompassPin", PARENT, "HM_CompassPin")
	self.compassKeys = {}
	self.displayCompassPins = Harvest.AreCompassPinsVisible()
	
	self.worldControlPool = ZO_ControlPool:New("HM_WorldPin", HM_WorldPins, "HM_WorldPin")
	HM_WorldPins:Create3DRenderSpace()
	self.worldKeys = {}
	self.displayWorldPins = Harvest.AreWorldPinsVisible()
	
	self.FOV = pi * 0.6
	self.useDepth = Harvest.DoWorldPinsUseDepth()
	
	self.customPinCallbacks = {}
	self.customPins = {}
	self.customMap = "custom"
	
	self:CheckPause()
	self:RefreshRange()
	
	self.distanceCorrection = 1
	
	self.fragment = ZO_SimpleSceneFragment:New(HM_WorldPins)
	HUD_UI_SCENE:AddFragment(self.fragment)
	HUD_SCENE:AddFragment(self.fragment)
	LOOT_SCENE:AddFragment(self.fragment)
	
	Lib3D:RegisterWorldChangeCallback("HM_3DPins", function(identifier, zoneIndex, isValidZone, newZone)
		local worldX, worldZ, worldY = WorldPositionToGuiRender3DPosition(0,0,0)
		HM_WorldPins:Set3DRenderSpaceOrigin(worldX, worldZ, worldY)
		self:CheckPause()
	end)
end

function InRangePins:RegisterCustomPinCallback(pinType, callback)
	self.customPinCallbacks[pinType] = callback
end

function InRangePins:AddCustomPin(pinTag, pinTypeId, range, globalX, globalY, worldZ)
	local pin = self.customPins[pinTag] or {}
	pin.pinTypeId = pinTypeId
	pin.range2 = range * range
	pin.x = globalX
	pin.y = globalY
	pin.worldZ = worldZ
	self.customPins[pinTag] = pin
end

function InRangePins:RefreshAllPins()
	self:RefreshCompassPins()
	self:RefreshWorldPins()
	self:RefreshCustomPins()
	self.lastUpdate = {}
	if not self.zoneCache then return end
	for map, mapCache in pairs(self.zoneCache.mapCaches) do
		self.lastUpdate[map] = {}
	end
	self.lastUpdate[self.customMap] = {}
end

function InRangePins:RefreshCompassPins()
	self.compassControlPool:ReleaseAllObjects()
	self.compassKeys = {}
	if not self.zoneCache then return end
	for map, mapCache in pairs(self.zoneCache.mapCaches) do
		self.compassKeys[map] = {}
	end
	self.compassKeys[self.customMap] = {}
end

function InRangePins:RefreshWorldPins()
	self.worldControlPool:ReleaseAllObjects()
	self.worldKeys = {}
	if not self.zoneCache then return end
	for map, mapCache in pairs(self.zoneCache.mapCaches) do
		self.worldKeys[map] = {}
	end
	self.worldKeys[self.customMap] = {}
end

function InRangePins:RefreshCustomPins()
	self.customPins = {}
	if not self.zoneCache then return end
	for pinType, callback in pairs(self.customPinCallbacks) do
		callback(self, pinType)
	end
end

function InRangePins:RefreshRange()
	local range = 0
	if self.displayCompassPins then
		range = Harvest.GetCompassDistance()
	end
	if self.displayWorldPins then
		range = zo_max(range, Harvest.GetWorldDistance())
	end
	self.visibleRange = range
	self.visibleRange2 = range * range
	
	range = Harvest.GetCompassDistance()
	self.visibleCompassRange2 = range * range
	range = Harvest.GetWorldDistance()
	self.visibleWorldRange2 = range * range
end

function InRangePins:CheckPause()
	local paused = (not Lib3D:IsValidZone()) or not (self.displayCompassPins or self.displayWorldPins)
	if paused then
		EVENT_MANAGER:UnregisterForUpdate("HarvestMapInRangePinsUpdate")
		self:RefreshAllPins()
	else
		EVENT_MANAGER:UnregisterForUpdate("HarvestMapInRangePinsUpdate")
		EVENT_MANAGER:RegisterForUpdate("HarvestMapInRangePinsUpdate", 30, InRangePins.UpdatePins )
	end
end

function InRangePins.UpdatePins(timeInMs)
	local self = InRangePins
	
	if not self.fragment:IsHidden() then
		if not self.zoneCache then return end
		
		self.globalX, self.globalY = GPS:LocalToGlobal(GetMapPlayerPosition("player"))
		local heading = GetPlayerCameraHeading()
		if heading > pi then --normalize heading to [-pi,pi]
			heading = heading - 2 * pi
		end
		self.heading = heading
		self.timeInMs = timeInMs
		
		for map, mapCache in pairs(self.zoneCache.mapCaches) do
			mapCache:ForNodesInRange(self.globalX, self.globalY, heading, self.visibleRange, self.pinUpdateCallback, self, self.lastUpdate[map], self.compassKeys[map], self.worldKeys[map])
		end
		
		
		local lastUpdate = self.lastUpdate[self.customMap]
		local compassKeys = self.compassKeys[self.customMap]
		local worldKeys = self.worldKeys[self.customMap]
		for pinTag, layout in pairs(self.customPins) do
			self:UpdateCustomPin(pinTag, layout, lastUpdate, compassKeys, worldKeys)
		end
	end
	-- some pins might be out of range and thus weren't updated by the ForNodesInRange call
	local key, compassKeys, worldKeys
	for map, lastUpdatedIds in pairs(self.lastUpdate) do
		compassKeys = self.compassKeys[map]
		worldKeys = self.worldKeys[map]
		for nodeId, time in pairs(lastUpdatedIds) do
			if time < timeInMs then
				key = compassKeys[nodeId]
				if key then
					self.compassControlPool:ReleaseObject(key)
					compassKeys[nodeId] = nil
				end
				key = worldKeys[nodeId]
				if key then
					self.worldControlPool:ReleaseObject(key)
					worldKeys[nodeId] = nil
				end
				lastUpdatedIds[nodeId] = nil
			end
		end
	end
end


function InRangePins:UpdateCustomPin(pinTag, layout, lastUpdate, compassKeys, worldKeys)
	lastUpdate[pinTag] = self.timeInMs
	local xDif = self.globalX - layout.x
	local yDif = self.globalY - layout.y
	local angle = -atan2(xDif, yDif)
	angle = (angle + self.heading)
	if angle > pi then
		angle = angle - 2 * pi
	elseif angle < -pi then
		angle = angle + 2 * pi
	end
	local normalizedDistance = (xDif * xDif + yDif * yDif) / layout.range2
	local key
	-- first update the world pins
	local validWorldPin = self.displayWorldPins and layout.worldX
	if validWorldPin then
		key = worldKeys[pinTag]
		if normalizedDistance >= 1 then
			if key then
				self.worldControlPool:ReleaseObject(key)
				worldKeys[pinTag] = nil
			end
			key = nil
			validWorldPin = false
		end
		if validWorldPin then
			local control
			if key then
				control = self.worldControlPool:GetExistingObject(key)
			else
				control, key = self:GetNewWorldControl(layout.pinTypeId, pinTag,
					layout.x,
					layout.y,
					layout.worldZ)
				worldKeys[pinTag] = key
			end
			control:Set3DRenderSpaceOrientation(0,self.heading,0)
		end
	end
	
	if not self.displayCompassPins then return end
	
	key = compassKeys[pinTag]
	-- the pin is out of range, so remove the pin control from the compass
	if normalizedDistance >= 1 then
		if key then
			self.compassControlPool:ReleaseObject(key)
			compassKeys[pinTag] = nil
		end
		if not validWorldPin then
			lastUpdate[pinTag] = nil
		end
		return
	end
	
	-- normalize the angle to [-1, 1] where (-/+) 1 is the left/right edge of the compass
	local normalizedAngle = 2 * angle / self.FOV
	-- check if the bin is outside the FOV
	if zo_abs(normalizedAngle) > 1 then
		if key then
			self.compassControlPool:ReleaseObject(key)
			compassKeys[pinTag] = nil
		end
		if not validWorldPin then
			lastUpdate[pinTag] = nil
		end
		return
	end
	
	if key then
		control = self.compassControlPool:GetExistingObject(key)
	else
		control, key = self:GetNewCompassControl(layout.pinTypeId)
		compassKeys[pinTag] = key
	end
	control:ClearAnchors()
	control:SetAnchor(CENTER, PARENT, CENTER, 0.5 * PARENT:GetWidth() * normalizedAngle, 0)
	control:SetHidden(false)
	
	if zo_abs(normalizedAngle) > 0.25 then
		control:SetDimensions(36 - 16 * zo_abs(normalizedAngle), 36 - 16 * zo_abs(normalizedAngle))
	else
		control:SetDimensions(32, 32)
	end

	control:SetAlpha(1 - normalizedDistance)
end

function InRangePins.UpdatePin(mapCache, nodeId, self, lastUpdate, compassKeys, worldKeys)
	lastUpdate[nodeId] = self.timeInMs
	local xDif = (self.globalX - mapCache.globalX[nodeId])
	local yDif = (self.globalY - mapCache.globalY[nodeId])
	local angle = -atan2(xDif, yDif)
	angle = (angle + self.heading)
	if angle > pi then
		angle = angle - 2 * pi
	elseif angle < -pi then
		angle = angle + 2 * pi
	end
	local worldDistance = (xDif * xDif + yDif * yDif) * self.distanceCorrection * self.distanceCorrection
	local normalizedDistance = worldDistance / self.visibleCompassRange2
	local normalizedWorldDistance = worldDistance / self.visibleWorldRange2
	worldDistance = worldDistance * 25000 * 25000 -- distance in meters squared
	
	local pinTypeId = mapCache.pinTypeId[nodeId]
	local key
	-- first update the world pins
	local validWorldPin = self.displayWorldPins and mapCache.worldZ[nodeId]
	if validWorldPin then
		if Harvest.IsWorldFilterActive() then
			validWorldPin = Harvest.IsWorldPinTypeVisible(pinTypeId)
		else
			validWorldPin = Harvest.IsMapPinTypeVisible(pinTypeId)
		end
	end
	if validWorldPin then
		
		key = worldKeys[nodeId]
		if normalizedWorldDistance >= 1 then
			if key then
				self.worldControlPool:ReleaseObject(key)
				worldKeys[nodeId] = nil
			end
			key = nil
			validWorldPin = false
		end
		if validWorldPin then
			local control
			if key then
				control = self.worldControlPool:GetExistingObject(key)
			else
				control, key = self:GetNewWorldControl(
					pinTypeId,
					mapCache.globalX[nodeId],
					mapCache.globalY[nodeId],
					mapCache.worldZ[nodeId],
					mapCache.version[nodeId])
				worldKeys[nodeId] = key
			end
			control:Set3DRenderSpaceOrientation(0, self.heading, 0)
			--d(worldDistance)
			if worldDistance < 9 then
				control.beam:SetAlpha(worldDistance * 0.25)
			end
		end
	end
	
	if not self.displayCompassPins then return end
	
	if Harvest.IsCompassFilterActive() then
		if not Harvest.IsCompassPinTypeVisible(pinTypeId) then return end
	else
		if not Harvest.IsMapPinTypeVisible(pinTypeId) then return end
	end
	
	key = compassKeys[nodeId]
	-- the pin is out of range, so remove the pin control from the compass
	if normalizedDistance >= 1 then
		if key then
			self.compassControlPool:ReleaseObject(key)
			compassKeys[nodeId] = nil
		end
		if not validWorldPin then
			lastUpdate[nodeId] = nil
		end
		return
	end
	
	-- normalize the angle to [-1, 1] where (-/+) 1 is the left/right edge of the compass
	local normalizedAngle = 2 * angle / self.FOV
	-- check if the bin is outside the FOV
	if zo_abs(normalizedAngle) > 1 then
		if key then
			self.compassControlPool:ReleaseObject(key)
			compassKeys[nodeId] = nil
		end
		if not validWorldPin then
			lastUpdate[nodeId] = nil
		end
		return
	end
	
	if key then
		control = self.compassControlPool:GetExistingObject(key)
	else
		control, key = self:GetNewCompassControl(pinTypeId)
		compassKeys[nodeId] = key
	end
	control:ClearAnchors()
	control:SetAnchor(CENTER, PARENT, CENTER, 0.5 * PARENT:GetWidth() * normalizedAngle, 0)
	control:SetHidden(false)
	
	if zo_abs(normalizedAngle) > 0.25 then
		control:SetDimensions(36 - 16 * zo_abs(normalizedAngle), 36 - 16 * zo_abs(normalizedAngle))
	else
		control:SetDimensions(32, 32)
	end

	control:SetAlpha(1 - normalizedDistance)
end

function InRangePins:GetNewCompassControl(pinTypeId)
	local pin, pinKey = self.compassControlPool:AcquireObject()
	
	layout = Harvest.GetMapPinLayout(pinTypeId)
	pin:SetTexture(layout.texture)
	pin:SetColor(layout.tint.r, layout.tint.g , layout.tint.b, 1)

	return pin, pinKey
end

function InRangePins:GetNewWorldControl(pinTypeId, globalX, globalY, worldZ, version)
	local pin, pinKey = self.worldControlPool:AcquireObject()
	
	local beam = pin:GetNamedChild("Beam")
	pin.beam = beam
	local icon = pin:GetNamedChild("Icon")
	pin.icon = icon
	if not pin:Has3DRenderSpace()  then
		pin:Create3DRenderSpace()
		beam:Create3DRenderSpace()
		beam:SetTexture("HarvestMap/Textures/worldMarker.dds")
		icon:Create3DRenderSpace()
	end
	pin:Set3DRenderSpaceUsesDepthBuffer(self.useDepth)
	beam:Set3DRenderSpaceUsesDepthBuffer(self.useDepth)
	icon:Set3DRenderSpaceUsesDepthBuffer(self.useDepth)
	
	local width = Harvest.GetWorldPinWidth() * 0.01
	local height = Harvest.GetWorldPinHeight() * 0.01
	icon:Set3DRenderSpaceOrigin(0, height + 0.125 * height + 0.25, 0)
	icon:Set3DLocalDimensions(0.25 * height + 0.5, 0.25 * height + 0.5)
	beam:Set3DRenderSpaceOrigin(0, 0.5 * height, 0)
	beam:Set3DLocalDimensions(width, height)
	
	layout = Harvest.GetMapPinLayout(pinTypeId)
	icon:SetTexture(layout.texture)
	
	beam:SetColor(layout.tint.r, layout.tint.g, layout.tint.b, 1)
	icon:SetColor(layout.tint.r, layout.tint.g , layout.tint.b, 1)
	
	local worldX, worldY = Lib3D:GlobalToWorld(globalX, globalY)
	pin:Set3DRenderSpaceOrigin(worldX, worldZ, worldY)
	
	return pin, pinKey
end