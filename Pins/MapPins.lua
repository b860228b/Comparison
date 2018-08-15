
local QuickPin = LibStub("LibQuickPin2")
local OldQuickPin = LibStub("LibQuickPin")
local LMP = LibStub("LibMapPins-1.0")

local Harvest = _G["Harvest"]
local pairs = _G["pairs"]
local IsUnitInCombat = _G["IsUnitInCombat"]

local CallbackManager = Harvest.callbackManager
local Events = Harvest.events

local MapPins = {}
Harvest.mapPins = MapPins

local TYPES = {
	ADD_DIVISION = 1,
	ADD_NODE = 2,
	REM_DIVISION = 3,
	REM_NODE = 4,
}

MapPins.commands = {length=0, index=1}

function MapPins:ClearQueue()
	self.commands = {length=0, index=1}
end

function MapPins:Add(Type, id, pinTypeId)
	local n = self.commands.length
	self.commands[n+1] = Type
	self.commands[n+2] = id
	self.commands[n+3] = pinTypeId
	self.commands.length = self.commands.length + 3
end

function MapPins:AddDivision(divisionId, pinTypeId)
	self:Add(TYPES.ADD_DIVISION, divisionId, pinTypeId)
end

function MapPins:RemoveDivision(divisionId, pinTypeId)
	self:Add(TYPES.REM_DIVISION, divisionId, pinTypeId)
end

function MapPins:AddNode(nodeId, pinTypeId)
	self:Add(TYPES.ADD_NODE, nodeId, pinTypeId or 0)
end

function MapPins:RemoveNode(nodeId, pinTypeId)
	self:Add(TYPES.REM_NODE, nodeId, pinTypeId or 0)
end

-- removes all resource pins from the map AND clears the pin queue.
function MapPins:RemoveAllNodes()
	self:ClearQueue()
	for _, pinTypeId in pairs(self.registeredPinTypeIds) do
		if not Harvest.HIDDEN_PINTYPES[pinTypeId] then
			QuickPin:RemovePinsOfPinType(Harvest.GetPinType(pinTypeId))
		end
	end
end

-- called whenever a node is hidden by the respawn timer or when it becomes visible again.
function MapPins:OnChangedNodeHiddenState(map, nodeId, newState)
	if self:IsActiveMap(map) then
		local pinTypeId = self.mapCache.pinTypeId[nodeId]
		if not pinTypeId then return end
		
		if not Harvest.IsMapPinTypeVisible(pinTypeId) then
			return
		end
		-- remove the node, if it was hidden.
		-- otherwise create the pin because the node is visible again.
		if newState then
			self:RemoveNode(nodeId, pinTypeId)
		else
			self:AddNode(nodeId, pinTypeId)
		end
		self:RefreshUpdateHandler()
	end
end

-- called whenever a resource is harvested (which adds a node or updates an already existing node)
-- or when a node is deleted by the debug tool
function MapPins:OnNodeChangedCallback(event, map, pinTypeId, nodeId)
	local nodeAdded = (event == Events.NODE_ADDED)
	local nodeUpdated = (event == Events.NODE_UPDATED)
	local nodeDeleted = (event == Events.NODE_DELETED)
	
	-- when the heatmap is active, the map pins aren't used
	if Harvest.IsHeatmapActive() then
		return
	end
	
	-- the node isn't on the currently displayed map
	if not self:IsActiveMap(map) then
		return
	end
	
	-- if the node's pin type is visible, then we do not have to manipulate any pins
	if not Harvest.IsMapPinTypeVisible(pinTypeId) then
		return
	end
	
	-- queue the pin change
	-- refresh a single pin by removing and recreating it
	if not nodeAdded then
		self:RemoveNode(nodeId, pinTypeId)
	end
	-- the (re-)creation of the pin is performed, if the pin isn't hidden by the respawn timer
	if not nodeDeleted and not self.mapCache:IsHidden(nodeId) then
		self:AddNode(nodeId, pinTypeId)
	end
	self:RefreshUpdateHandler()
end

-- the pin listed in the creation queue are only created, if should delay returns false.
-- i.e. the creation of pins can be delayed when the player is in-fight or the map is closed, to improve the performance.
function MapPins:ShouldDelay()
	if IsUnitInCombat("player") then
		return true
	end
	if not Harvest.IsMinimapCompatibilityModeEnabled() and ZO_WorldMap:IsHidden() and not self:IsInMinimapMode() then
		return true
	end
	return (self.commands.index >= self.commands.length)
end

local updateHandler
function MapPins:RefreshUpdateHandler()
	if self:ShouldDelay() then
		self:DisableUpdateHandler()
		return
	end
	self:EnableUpdateHandler()
end

function MapPins:EnableUpdateHandler()
	EVENT_MANAGER:UnregisterForUpdate("HarvestMap-Pins")
	updateHandler = updateHandler or function() self:PerformActions() end
	EVENT_MANAGER:RegisterForUpdate("HarvestMap-Pins", 50, updateHandler)
end

function MapPins:DisableUpdateHandler()
	EVENT_MANAGER:UnregisterForUpdate("HarvestMap-Pins")
end

function MapPins:IsInMinimapMode()
	local isMinimap = false
	if not ZO_WorldMap_IsWorldMapShowing() then -- minimap
		isMinimap = FyrMM or (AUI and AUI.Minimap:IsEnabled()) or VOTANS_MINIMAP
	end
	return isMinimap
end

function MapPins:RefreshVisibleDistance(newVisibleDistance)
	if not newVisibleDistance then
		newVisibleDistance = 0
		if self:IsInMinimapMode() or Harvest.HasPinVisibleDistance() then
			newVisibleDistance = Harvest.GetPinVisibleDistance()
		end
	end
	--newVisibleDistance = 0 -- debug
	--d(self.visibleDistance , "vs", newVisibleDistance)
	if newVisibleDistance ~= self.visibleDistance then
		self.visibleDistance = newVisibleDistance
		self:RedrawPins()
		if newVisibleDistance > 0 then
			EVENT_MANAGER:RegisterForUpdate("HarvestMap-VisibleRange", 2500, MapPins.UpdateVisibleMapPins)
		else
			EVENT_MANAGER:UnregisterForUpdate("HarvestMap-VisibleRange")
		end
	end
end

function MapPins:RestrictVisibleDistance()
	self:RefreshVisibleDistance(Harvest.GetPinVisibleDistance())
end

function MapPins:ExpandVisibleDistance()
	local newDistance = 0
	if Harvest.HasPinVisibleDistance() then
		newDistance = Harvest.GetPinVisibleDistance()
	end
	self:RefreshVisibleDistance(newDistance)
end

local GetGameTimeMilliseconds = GetGameTimeMilliseconds
local GetFrameTimeMilliseconds = GetFrameTimeMilliseconds
-- Creates and removes a bunch of queued pins.
function MapPins:PerformActions()
	
	local GetGameTimeMilliseconds = GetGameTimeMilliseconds
	local FrameTime = GetFrameTimeMilliseconds()
	
	local Type, id, x, y, defaultPinTypeId, pinTypeName, pin, index, pinManager, pinType
	index = self.commands.index
	if Harvest.IsMinimapCompatibilityModeEnabled() then
		pinManager = LMP
		if FyrMM or VOTANS_MINIMAP then
			defaultPinTypeId = 0
		end
	else
		pinManager = QuickPin
	end
	-- perform the update until timeout, but at least 10 entries from the queue
	local counter = 10
	if Harvest.IsMinimapCompatibilityModeEnabled() then
		counter = 99999
	end
	while counter > 0 or GetGameTimeMilliseconds() - FrameTime < 20 do
		-- retrieve data for the current command
		Type, id, pinTypeId = self.commands[index], self.commands[index+1], self.commands[index+2]
		index = index + 3
		
		if Type == TYPES.ADD_NODE then
			if not self.mapCache.hiddenTime[id] then
				pinTypeName = Harvest.GetPinType(defaultPinTypeId or pinTypeId)
				pinType = _G[pinTypeName]
				x = self.mapCache.localX[id]
				y = self.mapCache.localY[id]
				pin = pinManager:FindCustomPin(pinTypeName, id)
				if pin then
					pin:SetLocation(x, y)
				else
					pinManager:CreatePin(pinTypeName, id, x, y)
				end
			end	
		elseif Type == TYPES.REM_NODE then
			pinTypeName = Harvest.GetPinType(defaultPinTypeId or pinTypeId)
			pinManager:RemoveCustomPin(pinTypeName, id)
			
		elseif Type == TYPES.ADD_DIVISION then
			pinTypeName = Harvest.GetPinType(defaultPinTypeId or pinTypeId)
			for _, nodeId in pairs(self.mapCache.divisions[pinTypeId][id]) do
				if not self.mapCache.hiddenTime[nodeId] then
					x = self.mapCache.localX[nodeId]
					y = self.mapCache.localY[nodeId]
					pin = pinManager:FindCustomPin(pinTypeName, nodeId)
					if pin then
						pin:SetLocation(x, y)
					else
						pinManager:CreatePin(pinTypeName, nodeId, x, y)
					end
				end
			end
			
		elseif Type == TYPES.REM_DIVISION then
			pinTypeName = Harvest.GetPinType(defaultPinTypeId or pinTypeId)
			for _, nodeId in pairs(self.mapCache.divisions[pinTypeId][id]) do
				pinManager:RemoveCustomPin(pinTypeName, nodeId)
			end
		end
		
		if index >= self.commands.length then
			self.commands.length = 0
			self.commands.index = 1
			self:RefreshUpdateHandler()
			return
		end
		counter = counter - 1
	end
	self.commands.index = index
end

function MapPins:RegisterCallbacks()
	-- register callbacks for events, that affect map pins:
	-- respawn timer:
	CallbackManager:RegisterForEvent(Events.CHANGED_NODE_HIDDEN_STATE, function(event, map, nodeId, newState)
		self:OnChangedNodeHiddenState(map, nodeId, newState)
	end)
	-- creating/updating a node (after harvesting something) or deletion of a node (via debug tools)
	local callback = function(...) self:OnNodeChangedCallback(...) end
	CallbackManager:RegisterForEvent(Events.NODE_DELETED, callback)
	CallbackManager:RegisterForEvent(Events.NODE_UPDATED, callback)
	CallbackManager:RegisterForEvent(Events.NODE_ADDED, callback)
	-- when a map related setting is changed
	CallbackManager:RegisterForEvent(Events.SETTING_CHANGED, function(...) self:OnSettingsChanged(...) end)
	
	--CallbackManager:RegisterForEvent(Events.MAP_ADDED_TO_ZONE, function(event, mapCache, zoneCache)
	--	if Harvest.IsMinimapCompatibilityModeEnabled() then return end
	--	if Harvest.HasPinVisibleDistance() then return end
	--	if Harvest.IsHeatmapActive() then return end
	--	
	--	Harvest.Debug("requesting " .. tostring(zoneCache.estimatedNumOfPins) .. " pins")
	--	QuickPin:PreloadControls(zoneCache.estimatedNumOfPins)
	--end)
	
	EVENT_MANAGER:RegisterForEvent("HarvestMap-Pins", EVENT_PLAYER_COMBAT_STATE, function() self:RefreshUpdateHandler() end)
	
	local previousOnHideHandler = ZO_WorldMap:GetHandler("OnHide")
	local previousOnShowHandler = ZO_WorldMap:GetHandler("OnShow")
	ZO_WorldMap:SetHandler("OnHide", function(...)
		self:RefreshUpdateHandler()
		self:RefreshVisibleDistance()
		if previousOnHideHandler then previousOnHideHandler(...) end
	end)
	ZO_WorldMap:SetHandler("OnShow", function(...)
		--d("show map")
		self:RefreshUpdateHandler()
		self:RefreshVisibleDistance()
		if previousOnShowHandler then previousOnShowHandler(...) end
	end)
	--[[
	QuickPin:RegisterMapModeCallback("HarvestMap", function(isMinimap)
		--d("state change", not not isMinimap)
		self:RefreshVisibleDistance()
	end)
	]]
	--
	local stateChangeCallback = function(oldState, newState)
		if newState == SCENE_SHOWING then
			--d("map open")
			self:EnableUpdateHandler()
			self:ExpandVisibleDistance()
		elseif newState == SCENE_HIDING then
			--d("map closed")
			self:DisableUpdateHandler()
			self:RestrictVisibleDistance()
		end
	end 
	WORLD_MAP_SCENE:RegisterCallback("StateChange", stateChangeCallback)
	GAMEPAD_WORLD_MAP_SCENE:RegisterCallback("StateChange", stateChangeCallback)
	
end

local function OnButtonToggled(pinTypeId, button, visible)
	Harvest.SetMapPinTypeVisible( pinTypeId, visible )
	CALLBACK_MANAGER:FireCallbacks("LAM-RefreshPanel", Harvest.optionsPanel)
end
-- code based on LibMapPin, see Libs/LibMapPin-1.0/LibMapPins-1.0.lua for credits
function MapPins:AddCheckbox(panel, text)
	local checkbox = panel.checkBoxPool:AcquireObject()
	ZO_CheckButton_SetLabelText(checkbox, text)
	panel:AnchorControl(checkbox)
	return checkbox
end

function MapPins:AddResourceCheckbox(panel, pinTypeId)
	local text = Harvest.GetLocalization( "pintype" .. pinTypeId )
	local checkbox = self:AddCheckbox(panel, text)
	ZO_CheckButton_SetCheckState(checkbox, Harvest.IsMapPinTypeVisible(pinTypeId))
	ZO_CheckButton_SetToggleFunction(checkbox, function(...) OnButtonToggled(pinTypeId, ...) end)
	return checkbox
end

function MapPins:RegisterResourcePinTypes()
	
	local emptyFunction = function() end
	self.layouts = {}
	
	for _, pinTypeId in ipairs(Harvest.PINTYPES) do
		-- only register the resource pins, not tour pins or hidden resources like psijic portals
		if not Harvest.HIDDEN_PINTYPES[pinTypeId] then
			local pinType = Harvest.GetPinType( pinTypeId )
			local layout = Harvest.GetMapPinLayout( pinTypeId )
			self.layouts[pinTypeId] = layout
			-- some extra layout fields exclusive for QuickPins
			--layout.expectedPinCount = Harvest.expectedPinCount[pinTypeId]
			layout.OnClickHandler = MapPins.clickHandler
			
			-- create the pin type for this resource
			QuickPin:RegisterPinType(
				pinType,
				emptyFunction, -- no callback is used,
				-- because all pins are created together in the pinType 0 callback
				layout
			)
			table.insert(self.registeredPinTypeIds, pinTypeId)
			LMP:AddPinType(
				pinType,
				emptyFunction,  -- no callback is used,
				-- because all pins are created together in the pinType 0 callback
				nil,
				layout
			)
			OldQuickPin:RegisterPinType(pinType)
			
			self:AddResourceCheckbox(WORLD_MAP_FILTERS.pvePanel, pinTypeId )
			self:AddResourceCheckbox(WORLD_MAP_FILTERS.pvpPanel, pinTypeId )
			self:AddResourceCheckbox(WORLD_MAP_FILTERS.imperialPvPPanel, pinTypeId )
			
		end
	end
end

function MapPins:RegisterDefaultPinType()
	-- pin type which is always visible to receive the global pin refresh callback
	-- if votan's or fyrakin's minimap are used, all nodes are of this pin type.
	-- this is because all pin types need to be refreshed at the same time, so the position of the player
	-- is the same. (the position is needed for the "display only nearby pins" option).
	-- FyrMM sometimes calls the refresh function for one specific pin type, so instead of multiple pin types, we use only one pin type.
	-- votan's minimap calls the refresh callback for each pin type with a delay of about 1sec. (probably to prevent lag when entering a city)
	-- so we use only one pintype again.
	-- if neither of the minimaps is used, we can use multiple pin types, because all refresh callbacks are called at the same time.
	self.defaultTexture = "EsoUI/Art/MapPins/hostile_pin.dds"
	self.defaultTint = ZO_ColorDef:New(1, 1, 1, 1)
	self.defaultLayout = {
		level = self.layouts[1].level,
		texture = function(pin)
			local pinTypeId = self.mapCache.pinTypeId[pin.m_PinTag]
			if pinTypeId then --stuck pin, this happens sometimes when FyrMM is used
				-- After a pin refresh, the minimap doesn't only display the newly created pins by the refresh callback.
				-- The minimap instead caches all pins and draws all pins that were ever created by previous refresh callbacks.
				-- If a resource node is deleted for instance, the minimap doesn't care and will try to draw a pin anyways,
				-- because the pin was created once in a previous refresh callback.
				return self.layouts[pinTypeId].texture
			end
			return self.defaultTexture
		end,
		size = Harvest.GetMapPinSize(0),
		tint = function(pin)
			local pinTypeId = self.mapCache.pinTypeId[pin.m_PinTag]
			if pinTypeId then --stuck pin, this happens sometimes when FyrMM is used. see above.
				return self.layouts[pinTypeId].tint
			end
			return self.defaultTint
		end,
	}
	
	LMP:AddPinType(
		Harvest.GetPinType( "0" ),
		function() if Harvest.IsMinimapCompatibilityModeEnabled() then self:PinTypeRefreshCallback() end end,
		nil,
		self.defaultLayout
	)
	OldQuickPin:RegisterPinType(Harvest.GetPinType( "0" ))
	
	-- this callback will receive the pin refresh request
	QuickPin:RegisterPinType(
		Harvest.GetPinType( "0" ),
		function() if not Harvest.IsMinimapCompatibilityModeEnabled() then self:PinTypeRefreshCallback() end end
	)

	table.insert(self.registeredPinTypeIds, 0)
end

function MapPins:AddHeatMapCheckbox()
	local pve = self:AddCheckbox(WORLD_MAP_FILTERS.pvePanel, Harvest.GetLocalization( "filterheatmap" ))
	local pvp = self:AddCheckbox(WORLD_MAP_FILTERS.pvpPanel, Harvest.GetLocalization( "filterheatmap" ))
	local imperialPvP = self:AddCheckbox(WORLD_MAP_FILTERS.imperialPvPPanel, Harvest.GetLocalization( "filterheatmap" ))
	local fun = function(button, state)
		Harvest.SetHeatmapActive(state)
	end
	ZO_CheckButton_SetToggleFunction(pve, fun)
	ZO_CheckButton_SetToggleFunction(pvp, fun)
	ZO_CheckButton_SetToggleFunction(imperialPvP, fun)

	ZO_CheckButton_SetCheckState(pve, Harvest.IsHeatmapActive())
	ZO_CheckButton_SetCheckState(pvp, Harvest.IsHeatmapActive())
	ZO_CheckButton_SetCheckState(imperialPvP, Harvest.IsHeatmapActive())
end

function MapPins:AddDeletePinCheckbox()
	local pve = self:AddCheckbox(WORLD_MAP_FILTERS.pvePanel, Harvest.GetLocalization( "deletepinfilter" ))
	local pvp = self:AddCheckbox(WORLD_MAP_FILTERS.pvpPanel, Harvest.GetLocalization( "deletepinfilter" ))
	local imperialPvP = self:AddCheckbox(WORLD_MAP_FILTERS.imperialPvPPanel, Harvest.GetLocalization( "deletepinfilter" ))
	local fun = function(button, state)
		Harvest.SetPinDeletionEnabled(state)
	end
	ZO_CheckButton_SetToggleFunction(pve, fun)
	ZO_CheckButton_SetToggleFunction(pvp, fun)
	ZO_CheckButton_SetToggleFunction(imperialPvP, fun)

	ZO_CheckButton_SetCheckState(pve, Harvest.IsPinDeletionEnabled())
	ZO_CheckButton_SetCheckState(pvp, Harvest.IsPinDeletionEnabled())
	ZO_CheckButton_SetCheckState(imperialPvP, Harvest.IsPinDeletionEnabled())
end

function MapPins:Initialize()
	-- coords of the last pin update for the "display only nearby pins" option
	self.lastViewedX = -10
	self.lastViewedY = -10
	
	self:RegisterCallbacks()
	
	self.registeredPinTypeIds = {}
	self:RegisterResourcePinTypes()
	self:RegisterDefaultPinType()
	
	-- additional filter checkboxes
	self:AddHeatMapCheckbox()
	self:AddDeletePinCheckbox()
	
	self:RefreshVisibleDistance()
end

-- refreshes all resource pins or the farming helper tour pin.
-- if the given pintype is the tour, refresh only that pin
-- otherwise refresh all resource pins.
function MapPins:RefreshPinsBaseFunction( pinTypeId, quickPinFunction )
	-- refresh tour pin
	if pinTypeId == Harvest.TOUR then
		LMP:RefreshPins( Harvest.GetPinType( pinTypeId ))
		return
	end
	
	-- refresh all resource pins
	self:RemoveAllNodes()
	
	for _, pinTypeId in ipairs(self.registeredPinTypeIds) do
		if not Harvest.HIDDEN_PINTYPES[pinTypeId] then
			quickPinFunction(QuickPin, Harvest.GetPinType( pinTypeId ))
			LMP:RefreshPins( Harvest.GetPinType( pinTypeId ))
		end
	end
	quickPinFunction(QuickPin, Harvest.GetPinType( "0" ))
	LMP:RefreshPins( Harvest.GetPinType( "0" ))
end

function MapPins:RedrawPins( pinTypeId )
	--d("redraw")
	self:RefreshPinsBaseFunction( pinTypeId, QuickPin.RedrawPinsOfPinType )
end

function MapPins:RefreshPins( pinTypeId )
	self:RefreshPinsBaseFunction( pinTypeId, QuickPin.RefreshPinsOfPinType )
end

-- called every few seconds to update the pins in the visible range
function MapPins.UpdateVisibleMapPins()
	if Harvest.IsHeatmapActive() then return end

	local map = Harvest.GetMap()
	local x, y = GetMapPlayerPosition("player")

	MapPins:AddAndRemoveVisblePins(map, x, y)
end

-- If the player moved, some pins enter the visible radius while others leave it.
-- This function updates the queue with new creation/removal commands according to the movement.
function MapPins:AddAndRemoveVisblePins(map, x, y)
	-- if there is no pin data available, or the data doesn't match the current map, abort.
	if not self.mapCache then return end
	if self.mapCache.map ~= map then return end
	-- no pins are displayed when the heatmap mode is used.
	if Harvest.IsHeatmapActive() then return end
	
	-- add creation and removal commands to the pin queue.
	local shouldSaveCoords
	shouldSaveCoords = self.mapCache:SetPrevAndCurVisibleNodesToTable(self.lastViewedX, self.lastViewedY, x, y, self.visibleDistance, self)
	-- the queue is only updated if the distance of the player's current position and the position of the last update is large enough.
	-- if the distance was large enough, we have to save the current position
	if shouldSaveCoords then
		self.lastViewedX = x
		self.lastViewedY = y
		self:RefreshUpdateHandler()
	end
end

-- saves the current map and position
-- and loads the resource data for the current map
function MapPins:SetToMapAndPosition(map, x, y, measurement, zoneIndex)
	local newMap = self.currentMap ~= map
	-- save current map
	self.currentMap = map
	-- remove old cache and load the new one
	if self.mapCache then
		self.mapCache.accessed = self.mapCache.accessed - 1
	end
	self.mapCache = Harvest.Data:GetMapCache(nil, map, measurement, zoneIndex)
	-- if no data is available for this map, abort.
	if not self.mapCache then
		return
	end
	self.mapCache.accessed = self.mapCache.accessed + 1
	-- set the last position of the player when the map pins were refreshed, for the "display only in range pins" option
	self.lastViewedX = x
	self.lastViewedY = y
	if newMap then
		CallbackManager:FireCallbacks(Events.MAP_CHANGE)
	end
end

---Adds the nodes of the given pin type to the creation queue.
function MapPins:AddVisibleNodesOfPinType(pinTypeId)
	if not self.mapCache then return end
	Harvest.Data:CheckPinTypeInCache(pinTypeId, self.mapCache)
	self.mapCache:GetVisibleNodes(self.lastViewedX, self.lastViewedY, pinTypeId, self.visibleDistance, self)
end

function MapPins:IsActiveMap(map)
	if not self.mapCache then return false end
	return (self.mapCache.map == map)
end

function MapPins:PinTypeRefreshCallback()
	Harvest.Debug("Refresh of pins requested.")
	
	-- clear the queue of remaining pin creation/removal commands
	self:ClearQueue()
	
	-- data is still being manipulated, better if we don't access it yet
	if not Harvest.IsUpdateQueueEmpty() then
		Harvest.Debug("your data is still being refactored/updated" )
		return
	end
	
	if Harvest.IsHeatmapActive() then
		Harvest.Debug("pins could not be refreshed, heatmap is active" )
		return
	end
	
	local map, x, y, measurement, zoneIndex = Harvest.GetLocation( true )
	self:SetToMapAndPosition(map, x, y, measurement, zoneIndex)
	for _, pinTypeId in ipairs(Harvest.PINTYPES) do
		if Harvest.IsMapPinTypeVisible(pinTypeId) then
			self:AddVisibleNodesOfPinType(pinTypeId)
		end
	end
	self:RefreshUpdateHandler()
end

-- when the debug mode is enabled, this is the description of what happens if the player clicks on a pin.
-- if a pin is clicked, the node is deleted.
MapPins.clickHandler = {-- debugHandler = {
	{
		callback = function(...) Harvest.farm.helper:OnPinClicked(...) end,
		show = function(pin)
			if not Harvest.farm.path then return false end
			
			local nodeId = pin.m_PinTag
			local index = Harvest.farm.path:GetIndex(nodeId)
			if not index then return false end
			
			return true
		end,
	},
	{
		name = MapPins.nameFunction,
		callback = function(pin)
			-- remove this callback if the debug mode is disabled
			if not Harvest.IsPinDeletionEnabled() or IsInGamepadPreferredMode() then
				return
			end
			-- otherwise request the node to be deleted
			local pinType, nodeId = pin.m_pinType, pin.m_PinTag
			local pinTypeId = MapPins.mapCache.pinTypeId[nodeId]
			local nodeIndex = MapPins.mapCache.nodeIndex[nodeId]
			local saveFile = Harvest.Data:GetSaveFile( MapPins.mapCache.map )
			MapPins.mapCache:Delete(nodeId)
			saveFile.savedVars.data[ MapPins.mapCache.map ][ pinTypeId ][ nodeIndex ] = nil
			
		end,
		show = function() return Harvest.IsPinDeletionEnabled() and not IsInGamepadPreferredMode() end,
	}
}

-- these settings are handled by simply refreshing the map pins.
MapPins.refreshOnSetting = {
	--hasVisibleDistance = true,
	--visibleDistance = true,
	heatmapActive = true,
}
function MapPins:OnSettingsChanged(event, setting, ...)
	if self.refreshOnSetting[setting] then
		self:RedrawPins()
	elseif setting == "hasVisibleDistance" or setting == "visibleDistance" then
		self:RefreshVisibleDistance()
	elseif setting == "mapPinTypeVisible" then
		-- the visiblity of a pin type was changed (e.g. a checkbox in the map's filter panel was used)
		-- enable the pin type and refresh the pins.
		local pinTypeId, visible = ...
		LMP:SetEnabled( Harvest.GetPinType(pinTypeId), visible )
		-- known bug:
		-- FyrMM doesn't refresh the pins
		-- probably because the minimap is hidden while the map's filter panel is visible
		self:RedrawPins()
	elseif setting == "mapPinsVisible" then
		self:RedrawPins()
	elseif setting == "pinTypeSize" then
		local pinTypeId, size = ...
		LMP:SetLayoutKey( Harvest.GetPinType( pinTypeId ), "size", size )
		self:RefreshPins()
	elseif setting == "mapPinTexture" then
		local pinTypeId, texture = ...
		LMP:SetLayoutKey( Harvest.GetPinType( pinTypeId ), "texture", texture )
		self:RefreshPins()
	elseif setting == "pinTypeColor" then
		local pinTypeId, r, g, b = ...
		local layout = LMP:GetLayoutKey( Harvest.GetPinType( pinTypeId ), "tint" )
		if layout then
			layout:SetRGB( r, g, b )
		end
		self:RefreshPins()
	elseif setting == "mapPinMinSize" then
		local pinTypeId, size = ...
		LMP:SetLayoutKey( Harvest.GetPinType( pinTypeId ), "minsize", size )
		self:RefreshPins()
	elseif setting == "cacheCleared" then
		local map = ...
		if map == self.currentMap or not map then
			self:RedrawPins()
		end
	elseif setting == "pinAbovePoi" then
		local above = ...
		if above then
			self.defaultLayout.level = 55
		else
			self.defaultLayout.level = 20
		end
		self:RefreshPins()
	end
end
