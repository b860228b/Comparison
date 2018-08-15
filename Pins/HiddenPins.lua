
local GPS = LibStub("LibGPS2")
local Lib3D = LibStub("Lib3D2")

local CallbackManager = Harvest.callbackManager
local Events = Harvest.events

local Callback
local Hidden = {}
Harvest.hidden = Hidden

function Hidden.Initialize()
	
	Hidden.ConfigureForSettings(Harvest.GetHiddenTime(), Harvest.IsHiddenOnHarvest())
	
	CallbackManager:RegisterForEvent(Events.SETTING_CHANGED, function(event, setting, value)
		if setting == "hiddenTime" then
			Hidden.ConfigureForSettings(Harvest.GetHiddenTime(), Harvest.IsHiddenOnHarvest())
		elseif setting == "hiddenOnHarvest" then
			Hidden.ConfigureForSettings(Harvest.GetHiddenTime(), Harvest.IsHiddenOnHarvest())
		end
	end)
	
	local function hideNode(event, map, pinTypeId, nodeId, mapCache)
		if Harvest.IsHiddenOnHarvest() and Harvest.GetHiddenTime() > 0 then
			mapCache:SetHidden(nodeId, true)
		end
	end
	CallbackManager:RegisterForEvent(Events.NODE_UPDATED, hideNode)
	CallbackManager:RegisterForEvent(Events.NODE_ADDED, hideNode)
end

function Hidden.ConfigureForSettings(hiddenTimeInMinutes, hiddenOnHarvest)
	if hiddenTimeInMinutes > 0 then
		-- since we hide pins in the order of minutes, we can call this function very rarely
		EVENT_MANAGER:RegisterForUpdate("HarvestMap-UnhidePins", 10 * 1000, Hidden.UnhideHiddenPins)
		-- when "hidden on harvest" is enabled, then we don't hide pins near the player
		if hiddenOnHarvest then
			EVENT_MANAGER:UnregisterForUpdate("HarvestMap-HidePins")
		else
			-- this function needs to be called often, so the player doesn't "tunnel" through nodes
			EVENT_MANAGER:RegisterForUpdate("HarvestMap-HidePins", 250, Hidden.HideNearbyPins)
		end
	else
		EVENT_MANAGER:UnregisterForUpdate("HarvestMap-HidePins")
		EVENT_MANAGER:UnregisterForUpdate("HarvestMap-UnhidePins")
	end
	Hidden.hiddenTimeInMs = hiddenTimeInMinutes * 60 * 1000
end

function Hidden.HideNearbyPins()

	local x, y = GPS:LocalToGlobal( GetMapPlayerPosition( "player" ) )
	-- some maps don't work (ie aurbis)
	if x then
		local cache = Harvest.Data:GetCurrentZoneCache()
		if cache then
			for _, mapCache in pairs(cache.mapCaches) do
				-- for every nearby node, execute mapCache:SetHidden(nodeId, true)
				mapCache:ForNearbyNodes(x, y, mapCache.SetHidden, true)
			end
		end
	end
	
end

function Hidden.UnhideHiddenPins( currentTimeInMs )
	-- check every single hidden pin, if it was hidden 'hiddenTimeInMs' ms ago
	-- if so, then unhide the pin
	local hiddenTimeInMs = Hidden.hiddenTimeInMs 
	for map, cache in pairs(Harvest.Data.mapCaches) do
		for nodeId, timeWhenHiddenInMs in pairs(cache.hiddenTime) do
			if currentTimeInMs - timeWhenHiddenInMs > hiddenTimeInMs then
				cache:SetHidden( nodeId, false )
			end
		end
	end
	
end
