
local CallbackManager = Harvest.callbackManager
local Events = Harvest.events

local Harvest = Harvest or {}
local Interaction = {}
Harvest.interaction = Interaction

local GetInteractionType = GetInteractionType

function Interaction.Initialize()
	-- harvesting interaction takes 2 seconds, or 1 second with the champion perk
	-- so choose a delay that is a bit less than 1 second
	local delayInMs = 750
	EVENT_MANAGER:RegisterForUpdate("HarvestMap-InteractionType", delayInMs, Interaction.UpdateInteractionType)
	EVENT_MANAGER:RegisterForEvent("HarvestMap", EVENT_BEGIN_LOCKPICK, Interaction.BeginLockpicking)
	EVENT_MANAGER:RegisterForEvent("HarvestMap", EVENT_LOOT_RECEIVED, Interaction.OnLootReceived)
	EVENT_MANAGER:RegisterForEvent("HarvestMap", EVENT_LOOT_UPDATED, Interaction.OnLootUpdated)
	
	-- this hack saves the name of the object that was last interacted with
	local oldInteract = FISHING_MANAGER.StartInteraction
	FISHING_MANAGER.StartInteraction = function(...)
		local action, name, blockedNode, isOwned = GetGameCameraInteractableActionInfo()
		Interaction.lastInteractableAction = action
		Interaction.lastInteractableName = name
		Interaction.wasLastInteractableOwned = isOwned
		
		-- there is no EVENT_BEGIN_FISHING, so we have to use this hack instead
		-- here we check if the action is called "Fish"
		if action == GetString(SI_GAMECAMERAACTIONTYPE16) then
			-- there are some "Fish" quest interactions, which we don't want
			-- so we have to verify that we really start a fishing interaction
			local delayInMs = 500
			EVENT_MANAGER:RegisterForUpdate("HarvestMap-FishState", delayInMs, Interaction.CheckFishingState)
		end
		
		return oldInteract(...)
	end
	
end

function Interaction.OnLootReceived( eventCode, receivedBy, itemLink, stackCount, soundCategory, lootType, lootedBySelf )
	if not lootedBySelf then return end
	if not lootType == LOOT_TYPE_ITEM then return end
	local wasHarvesting = (Interaction.lastInteractionType == INTERACTION_HARVEST)
	local wasContainer = Harvest.IsInteractableAContainer( Interaction.lastInteractableName )
	if not wasHarvesting and not wasContainer then return end
	
	local itemId = select(4, ZO_LinkHandler_ParseLink( itemLink ))
	itemId = tonumber(itemId) or 0
	-- get the pin type depending on the item we looted and the name of the harvest node
	local pinTypeId = Harvest.GetPinTypeId(itemId, Interaction.lastInteractableName)
	-- abort if we couldn't find a matching pin type
	if pinTypeId == nil then
		Harvest.Debug( "OnLootReceived failed: pin type id is nil" )
		return
	end
	
	local map, x, y, measurement, zoneIndex = Harvest.GetLocation()
	local z = select(2, Harvest.Get3DPosition())
	
	Harvest.Debug( "Discovered a new node. pintypeid:" .. tostring(pinTypeId) .. " on map " .. map )
	CallbackManager:FireCallbacks(Events.NODE_DISCOVERED, map, x, y, z, measurement, zoneIndex, pinTypeId)
	
	-- reset the interaction state, so we do not fire the event again for other items in the same container/node
	Interaction.lastInteractionType = nil
	-- reset the interactable name variable
	-- otherwise looting a container item after opening heavy sacks, thieves troves, stashes etc can cause wrong pins
	Interaction.lastInteractableName = ""
	
end

-- neded for those players that play without auto loot
function Interaction.OnLootUpdated()
	-- verify the most basic conditions, so we do not iterate over all
	-- loot whenever the player takes one item
	if not Interaction.lastInteractionType == INTERACTION_HARVEST then return end
	if Harvest.IsInteractableAContainer( Interaction.lastInteractableName ) then return end
	-- i usually play with auto loot on
	-- everything was programmed with auto loot in mind
	-- if auto loot is disabled (ie OnLootUpdated is called)
	-- let harvestmap believe auto loot is enabled by calling
	-- OnLootReceived for each item in the loot window
	local items = GetNumLootItems()
	for lootIndex = 1, items do
		local lootId, _, _, count = GetLootItemInfo( lootIndex )
		Interaction.OnLootReceived( nil, nil, GetLootItemLink( lootId, LINK_STYLE_DEFAULT ), count, nil, LOOT_TYPE_ITEM, true )
	end
end

function Interaction.UpdateInteractionType(timeInMs)
	-- remember the most recent interaction type for upto 2 seconds
	-- this is because lag can cause the loot window to open a bit after
	-- the harvesting interaction has ended
	local currentInteractionType = GetInteractionType()
	if currentInteractionType then
		Interaction.lastInteractionType = currentInteractionType
		Interaction.lastInteractionTimeInMs = timeInMs
	elseif timeInMs - Interaction.lastInteractionTimeInMs > 2000 then
		Interaction.lastInteractionType = nil
	end
end

function Interaction.BeginLockpicking()
	-- if the interactable is owned by an NPC but the action isn't called "Steal From"
	-- then it wasn't a safebox but a simple door: don't place a chest pin
	if Interaction.wasLastInteractableOwned and Interaction.lastInteractableAction ~= GetString(SI_GAMECAMERAACTIONTYPE20) then
		Harvest.Debug( "not a chest or justice container(?)" )
		return
	end
	local pinTypeId = nil
	-- normal chests aren't owned and their interaction is called "unlock"
	-- other types of chests (ie for heists) aren't owned but their interaction is "search"
	-- safeboxes are owned
	if (not Interaction.wasLastInteractableOwned) and Interaction.lastInteractableAction == GetString(SI_GAMECAMERAACTIONTYPE12) then
		-- normal chest
		pinTypeId = Harvest.CHESTS
	elseif Interaction.wasLastInteractableOwned then
		-- heist chest or safebox
		pinTypeId = Harvest.JUSTICE
	end
	if not pinTypeId then return end
	
	-- lockpicking has its own interaction camera, which is different from the player position
	local z
	if IsInteractionUsingInteractCamera() then
		z = Harvest.GetCameraHeight()
	else
		-- this function returns wrong height values, if the interaction camera is active
		z = select(2, Harvest.Get3DPosition())
	end
	
	local map, x, y, measurement, zoneIndex = Harvest.GetLocation()
	CallbackManager:FireCallbacks(Events.NODE_DISCOVERED, map, x, y, z, measurement, zoneIndex, pinTypeId)
end

function Interaction.CheckFishingState()
	EVENT_MANAGER:UnregisterForUpdate("HarvestMap-FishState")
	if GetInteractionType() == INTERACTION_FISH then
		local map, x, y, measurement, zoneIndex = Harvest.GetLocation()
		local z = select(2, Harvest.Get3DPosition())
		local pinTypeId = Harvest.FISHING
		CallbackManager:FireCallbacks(Events.NODE_DISCOVERED, map, x, y, z, measurement, zoneIndex, pinTypeId)
	end
end
	