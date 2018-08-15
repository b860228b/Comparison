
Harvest = Harvest or {}
local GPS = LibStub("LibGPS2")
local Lib3D = LibStub("Lib3D2")

-- returns informations regarding the current location
-- if viewedMap is true, the data is relative to the currently viewed map
-- otherwise the data is related to the map the player is currently on
function Harvest.GetLocation( viewedMap )
	local mapChanged
	if not viewedMap then
		mapChanged = (SetMapToPlayerLocation() == SET_MAP_RESULT_MAP_CHANGED)
	end
	
	local x, y, heading = GetMapPlayerPosition( "player" )
	local zoneIndex = GetCurrentMapZoneIndex()
	-- some maps are bugged, i.e. vaults of madness returns the index of coldharbor
	if DoesCurrentMapMatchMapForPlayerLocation() then
		zoneIndex = GetUnitZoneIndex("player")
	end
	
	if not viewedMap then
		if WouldProcessMapClick(x, y) then
			ProcessMapClick(x, y)
			x, y, heading = GetMapPlayerPosition( "player" )
		end
	end
	
	local map = Harvest.GetMap()
	
	local measurement = GPS:GetCurrentMapMeasurements()
	measurement = Harvest.Combine3DInfoWithMeasurement(GetMapContentType(), map, measurement, zoneIndex)
	
	if mapChanged then
		CALLBACK_MANAGER:FireCallbacks("OnWorldMapChanged")
	end
	return map, x, y, measurement, zoneIndex, heading
end

-- adds 3d information (the distanceCorrection factor) to the measurement
function Harvest.Combine3DInfoWithMeasurement( mapType, map, measurement, zoneIndex)
	if not measurement then return end
	
	local zoneId = GetZoneId(zoneIndex)
	local distanceCorrection, computed = Lib3D:GetGlobalToWorldFactor(zoneId)
	
	if distanceCorrection then
		if computed then
			Harvest.settings.savedVars.global.measurements[map] = {distanceCorrection, GetTimeStamp(), zoneId, measurement.offsetX, measurement.offsetY, measurement.scaleX, measurement.scaleY}
		end
		-- usually 1 in global coords coresponds to 25 km, but some maps scale differently
		distanceCorrection = distanceCorrection / 25000
	elseif Harvest.settings.savedVars.global.measurements[map] then
		distanceCorrection = Harvest.settings.savedVars.global.measurements[map][1] / 25000
	else
		-- delves tend to be scaled down on the zone map, so we need to return a smaller value
		if mapType == MAP_CONTENT_DUNGEON and measurement.scaleX < 0.003 then
			distanceCorrection = math.sqrt(165)
		else
			distanceCorrection = 1
		end
	end
	
	measurement = {
		scaleX = measurement.scaleX,
		scaleY = measurement.scaleY,
		offsetX = measurement.offsetX,
		offsetY = measurement.offsetY,
		distanceCorrection = distanceCorrection,
		zoneId = zoneId,
	}
	
	return measurement
end

local lastMapTexture
local lastMap
function Harvest.GetMap()
	local textureName = GetMapTileTexture()
	if lastMapTexture ~= textureName then
		lastMapTexture = textureName
		textureName = string.lower(textureName)
		textureName = string.gsub(textureName, "^.*maps/", "")
		textureName = string.gsub(textureName, "_%d+%.dds$", "")

		if textureName == "eyevea_base" then
			textureName = "eyevea/" .. textureName
		end

		lastMap = textureName
	end
	return lastMap
end

local mapBlacklist = {
	["tamriel/tamriel"] = true,
	["tamriel/mundus_base"] = true,
}
function Harvest.IsMapBlacklisted( map )
	return mapBlacklist[ map ]
end
