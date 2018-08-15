
local Lib3D = LibStub("Lib3D2")
Harvest = Harvest or {}

-- refreshes the pins of the given pin type
-- if no pinType is given, all pins are refreshed
function Harvest.RedrawPins( pinTypeId )
	Harvest.mapPins:RedrawPins( pinTypeId )
	Harvest.InRangePins:RefreshCustomPins( pinTypeId )
end

function Harvest.Get3DPosition()
	local x,y,z = Lib3D:ComputePlayerRenderSpacePosition()
	if IsMounted() then y = y - 1 end -- approx horse height
	return x,y,z
end

function Harvest.GetCameraHeight()
	local x, z, y = Lib3D:GetCameraRenderSpacePosition()
	return z
end

function Harvest.OnLoad(eventCode, addOnName)
	
	Harvest.Data:CheckSubModule(addOnName)

	if addOnName ~= "HarvestMap" then
		return
	end
	
	Harvest.CheckFolderStructure()
	-- load settings first, because other modules will behave according to the settings
	Harvest.settings:Initialize()
	-- initialize the data/caching system
	Harvest.Data:Initialize()
	-- initialize resource pins
	Harvest.mapPins:Initialize()
	-- initialize 3d and compass pins
	Harvest.InRangePins:Initialize()
	-- initialize the pin hiding logic
	Harvest.hidden:Initialize()
	
	Harvest.interaction:Initialize()
	
	-- main menu
	Harvest.menu:Initialize()
	Harvest.filters:Initialize()
	Harvest.farm:Initialize()
	Harvest.menu:Finalize()
	
	-- initialize bonus features
	if Harvest.IsHeatmapActive() then
		HarvestHeat.Initialize()
	end
	
end

-- initialization which is dependant on other addons is done on EVENT_PLAYER_ACTIVATED
-- because harvestmap might've been loaded before them
function Harvest.OnActivated()
	Harvest.farm:PostInitialize()
	EVENT_MANAGER:UnregisterForEvent("HarvestMap", EVENT_PLAYER_ACTIVATED, Harvest.OnActivated)
end

EVENT_MANAGER:RegisterForEvent("HarvestMap", EVENT_ADD_ON_LOADED, Harvest.OnLoad)
EVENT_MANAGER:RegisterForEvent("HarvestMap", EVENT_PLAYER_ACTIVATED, Harvest.OnActivated)
