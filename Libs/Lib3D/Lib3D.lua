-- lib3D2 by Shinni
-- some helper functions to be used for converting coordinate systems (local, global, world, renderspace)
-- also some functions to retrieve the camera and player position

local LIB_NAME = "Lib3D2"
local VERSION = 11
local lib, version = LibStub:NewLibrary(LIB_NAME, VERSION)
if not lib then return end
if version and version < VERSION then
	EVENT_MANAGER:UnregisterForEvent(LIB_NAME, EVENT_PLAYER_ACTIVATED)
	EVENT_MANAGER:UnregisterForEvent(LIB_NAME, EVENT_PLAYER_ALIVE)
end

local GPS = LibStub("LibGPS2")
local LMP = LibStub("LibMapPing")

local d = function() end
if false then -- set to true for debug output
	d = _G["d"]
	function GlobalPos()
		local x, y = GetMapPlayerPosition("player")
		x, y = GPS:LocalToGlobal(x, y)
		d(x,y)
	end
end

-- control which is used to take 3d world coordinate measurements
local measurementControl = _G[LIB_NAME .. "MeasurementControl"]
if not measurementControl then
	measurementControl = CreateControl(LIB_NAME .. "MeasurementControl", GuiRoot, CT_CONTROL)
	measurementControl:Create3DRenderSpace()
end

-- origin of the zone in global coords
local currentOriginGlobalX
local currentOriginGlobalY
local currentGlobalToWorldFactor
local currentWorldToGlobalFactor
local currentZoneIndex
local currentZoneId

lib.computedFactors = {}
lib.worldChangeCallbacks = {}

-- the passed zoneId should be the player's current zoneId
local function ComputeGlobalToWorldFactor(zoneId)
	if lib.computedFactors[zoneId] then
		return unpack(lib.computedFactors[zoneId])
	end
	local currentGlobalToWorldFactor, currentOriginGlobalX, currentOriginGlobalY
	
	local match = DoesCurrentMapMatchMapForPlayerLocation()
	SetMapToMapListIndex(TAMRIEL_MAP_INDEX)
	
	-- save current map ping, so we can restore it later
	local hasMapPing = LMP:HasMapPing(MAP_PIN_TYPE_PLAYER_WAYPOINT)
	local originalX, originalY = LMP:GetMapPing(MAP_PIN_TYPE_PLAYER_WAYPOINT)
	
	-- set two waypoints that are 25 km in X and Y direction apart from each other
	LMP:SuppressPing(MAP_PIN_TYPE_PLAYER_WAYPOINT)
	
	local centerX, _, centerY = GuiRender3DPositionToWorldPosition(0,0,0)
	local success = SetPlayerWaypointByWorldLocation(centerX - 125000, 0, centerY - 125000)
	if success then
		local firstX, firstY = LMP:GetMapPing(MAP_PIN_TYPE_PLAYER_WAYPOINT)
		success = SetPlayerWaypointByWorldLocation(centerX + 125000, 0, centerY + 125000)
		if success then
			local secondX, secondY = LMP:GetMapPing(MAP_PIN_TYPE_PLAYER_WAYPOINT)
			if firstX ~= secondX and firstY ~= secondY then
				currentGlobalToWorldFactor = 2 * 2500 / (secondX - firstX + secondY - firstY)
				currentOriginGlobalX = (firstX + secondX) * 0.5 - centerX * 0.01 / currentGlobalToWorldFactor
				currentOriginGlobalY = (firstY + secondY) * 0.5 - centerY * 0.01 / currentGlobalToWorldFactor
			end
		end
	end
	LMP:UnsuppressPing(MAP_PIN_TYPE_PLAYER_WAYPOINT)
	
	-- restore waypoint
	LMP:MutePing(MAP_PIN_TYPE_PLAYER_WAYPOINT)
	if hasMapPing then
		PingMap(MAP_PIN_TYPE_PLAYER_WAYPOINT, MAP_TYPE_LOCATION_CENTERED, originalX, originalY)
	else
		RemovePlayerWaypoint()
	end
	LMP:UnmutePing(MAP_PIN_TYPE_PLAYER_WAYPOINT)
	
	SetMapToPlayerLocation()
	if not match then
		CALLBACK_MANAGER:FireCallbacks("OnWorldMapChanged")
	end
	
	lib.computedFactors[zoneId] = {currentGlobalToWorldFactor, currentOriginGlobalX, currentOriginGlobalY}
	return currentGlobalToWorldFactor, currentOriginGlobalX, currentOriginGlobalY
end

local function OnPlayerActivated()
	-- check if the player entered a new world
	local zoneIndex = GetUnitZoneIndex("player")
	local newWorld = currentZoneIndex ~= zoneIndex
	
	if newWorld then
		currentZoneIndex = zoneIndex
		currentZoneId = GetZoneId(zoneIndex)
		
		currentGlobalToWorldFactor, currentOriginGlobalX, currentOriginGlobalY = ComputeGlobalToWorldFactor(currentZoneId)
		
		if not currentGlobalToWorldFactor then
			d("error, could not compute globalToWorld factor")
			currentWorldToGlobalFactor = nil
		else
			d("global to world factor", currentGlobalToWorldFactor)
			currentWorldToGlobalFactor = 1 / currentGlobalToWorldFactor
		end
		
	end
	
	local validZone = lib:IsValidZone()
	for identifier, callback in pairs(lib.worldChangeCallbacks) do
		callback(identifier, zoneIndex, validZone, newWorld)
	end
end
EVENT_MANAGER:RegisterForEvent(LIB_NAME, EVENT_PLAYER_ACTIVATED, OnPlayerActivated)
EVENT_MANAGER:RegisterForEvent(LIB_NAME, EVENT_PLAYER_ALIVE, OnPlayerActivated)

---
-- This function expects an identifier in addition to the callback. The identifier can be
-- used to unregister the callback.
-- The registered callback will be fired when the player enters a new 3d world. (e.g. a delve is entered)
-- The callbacks arguments are the identifier and the current 3d world's zoneIndex and zoneId
function lib:RegisterWorldChangeCallback(identifier, callback)
	self.worldChangeCallbacks[identifier] = callback
end

---
-- Unregisters the callback which belongs to the given identifier
function lib:UnregisterWorldChangeCallback(identifier)
	self.worldChangeCallbacks[identifier] = nil
end

---
-- Returns the global coordsystem to world system factor for the current zone.
-- Returns nil if the factor isn't known.
-- The 2nd return value tells you, if the value was computed or if it is a hardcoded fallback value
-- This factor can be used to convert distances between global coords to distances in meters.
function lib:GetGlobalToWorldFactor(zoneId)
	local result = self.computedFactors[zoneId]
	if result and result[1] then
		return result[1], true
	end
	return self.SPECIAL_GLOBAL_TO_WORLD_FACTORS[zoneId], false
end

function lib:GetWorldOriginAsGlobal()
	return currentOriginGlobalX, currentOriginGlobalY
end

---------------------------------------------------------------------
-- coordinate conversion functions
-- first map to world coords
-- then world coords to map coords further below
---------------------------------------------------------------------

---
-- Expects a point given in global map coordinates and returns
-- the point's world x and z coords in relation to the current world origin.
function lib:GlobalToWorld(x, y)
	x = x - currentOriginGlobalX
	y = y - currentOriginGlobalY
	x = x * currentGlobalToWorldFactor
	y = y * currentGlobalToWorldFactor
	return x, y
end

---
-- Expects a point given in local map coordinates and returns
-- the point's world x and z coords in relation to the current world origin.
function lib:LocalToWorld(x, y)
	x, y = GPS:LocalToGlobal(x, y)
	if not x then return nil end
	return self:GlobalToWorld(x, y)
end

---
-- Expects a point given in world x and z coords in relation to the current world origin
-- and returns the point in global map coordinates
function lib:WorldToGlobal(x, z)
	x = x * currentWorldToGlobalFactor
	z = z * currentWorldToGlobalFactor
	x = x + currentOriginGlobalX
	z = z + currentOriginGlobalY
	return x, y
end

---
-- Expects a point given in world x and z coords in relation to the current world origin
-- and returns the point in local map coordinates
function lib:WorldToLocal(x, z)
	x, z = self:WorldToGlobal(x, z)
	x, z = GPS:GlobalToLocal(x, z)
	return x, z
end

function lib:LocalDistance2InMeters(x1, y1, x2, y2)
	local measurements = GPS:GetCurrentMapMeasurements()
	if not measurements then return nil end
	x1 = (x1 - x2) * measurements.scaleX
	y1 = (y1 - y2) * measurements.scaleY
	return (x1*x1 + y1*y1) * currentGlobalToWorldFactor * currentGlobalToWorldFactor
end

function lib:LocalDistanceInMeters(x1, y1, x2, y2)
	local measurements = GPS:GetCurrentMapMeasurements()
	if not measurements then return nil end
	x1 = (x1 - x2) * measurements.scaleX
	y1 = (y1 - y2) * measurements.scaleY
	return (x1*x1 + y1*y1)^0.5 * currentGlobalToWorldFactor
end

function lib:GlobalDistance2InMeters(x1, y1, x2, y2)
	x1 = x1 - x2
	y1 = y1 - y2
	return (x1*x1 + y1*y1) * currentGlobalToWorldFactor * currentGlobalToWorldFactor
end

function lib:GlobalDistanceInMeters(x1, y1, x2, y2)
	x1 = x1 - x2
	y1 = y1 - y2
	return (x1*x1 + y1*y1)^0.5 * currentGlobalToWorldFactor
end

---
-- Returns the camera position in render space coordinates
function lib:GetCameraRenderSpacePosition()
	Set3DRenderSpaceToCurrentCamera(measurementControl:GetName())
	return measurementControl:Get3DRenderSpaceOrigin()
end

---
-- Returns position, and the three basis vectors of the camera's render space (forward, right, up)
function lib:GetCameraRenderSpace()
	Set3DRenderSpaceToCurrentCamera(measurementControl:GetName())
	local x, y, z = measurementControl:Get3DRenderSpaceOrigin()
	local forwardX, forwardY, forwardZ = measurementControl:Get3DRenderSpaceForward()
	local rightX, rightY, rightZ = measurementControl:Get3DRenderSpaceRight()
	local upX, upY, upZ = measurementControl:Get3DRenderSpaceUp()
	return x, y, z, forwardX, forwardY, forwardZ, rightX, rightY, rightZ, upX, upY, upZ
end

---
-- Computs the player's render space position (including height)
-- by using camera information and the player's 2d position in render space
function lib:ComputePlayerRenderSpacePosition()
	local x, y, z, forwardX, forwardY, forwardZ, rightX, rightY, rightZ, upX, upY, upZ = self:GetCameraRenderSpace()
	
	local globalX, globalY = GPS:LocalToGlobal(GetMapPlayerPosition("player"))
	if not globalX then return end
	
	local worldX, worldZ = lib:GlobalToWorld(globalX, globalY)
	worldX, _, worldZ = WorldPositionToGuiRender3DPosition(worldX * 100, 0, worldZ * 100)
	-- follow the camera's view direction and return the height when it is closest to the player's position
	-- this way we get more accurate results than using the camera's view distance setting, which doesn't accurately describe the distance on maps with lots of occlusion
	-- e.g. the camera might be closer to the player because the player is standing close to a wall
	local dist = ((worldX - x) * forwardX + (worldZ - z) * forwardZ) / (forwardX*forwardX + forwardZ*forwardZ)
	local worldY = y + forwardY * dist
	-- if the camera is further away, we have a higher vertical offset
	worldY = worldY - dist * 0.05-- - GetSetting(SETTING_TYPE_CAMERA,CAMERA_SETTING_THIRD_PERSON_VERTICAL_OFFSET)
	return worldX, worldY, worldZ, dist
end

---
-- Returns an approximation of the player's current world coordinates in relation to the current world origin
-- The returned values are the position of the first person camera.
-- If the toggle between first and third person camera doesn't work (i.e the player is mounted), then the third person camera's cooridnates are returned.
-- Note that calling this function will toggle the camera twice, which can result in screen flickering when called outside of a key <Down> or <Up> callback.
-- Use with care!
function lib:GetFirstPersonRenderSpacePosition()
	if IsMounted() then return end
	
	Set3DRenderSpaceToCurrentCamera(measurementControl:GetName())
	local preToggleX, preToggleY, preToggleZ = measurementControl:Get3DRenderSpaceOrigin()
	ToggleGameCameraFirstPerson()
	Set3DRenderSpaceToCurrentCamera(measurementControl:GetName())
	local toggledX, toggledY, toggledZ = measurementControl:Get3DRenderSpaceOrigin()
	ToggleGameCameraFirstPerson()
	Set3DRenderSpaceToCurrentCamera(measurementControl:GetName())
	local reToggleX, reToggleY, reToggleZ = measurementControl:Get3DRenderSpaceOrigin()
	
	local resultX, resultY, resultZ
	-- unfortunately there is no api function to get the current camera state (first person or third person)
	-- but for some reason the distance between the camera position before the first toggle and after the 2nd toggle
	-- is only zero, if the camera toggled from first person to third person to first person
	if preToggleX == reToggleX and preToggleY == reToggleY and preToggleZ == reToggleZ then
		-- the camera toggled from first person to third person to first person
		resultX, resultY, resultZ = preToggleX, preToggleY, preToggleZ -- first person coords
	else
		-- the camera toggled from third person to first person to third person
		resultX, resultY, resultZ = toggledX, toggledY, toggledZ -- first person coords
	end
	
	return resultX, resultY, resultZ
end

---
-- Returns true if the library can be used for the current zone
function lib:IsValidZone()
	return (currentGlobalToWorldFactor ~= nil)
end
