
local LMP = LibStub("LibMapPins-1.0")
local GPS = LibStub("LibGPS2")
local LAM = LibStub("LibAddonMenu-2.0")

local CallbackManager = Harvest.callbackManager
local Events = Harvest.events

local Farm = Harvest.farm
Farm.helper = {}
local Helper = Farm.helper

function Helper:Initialize(fragment)
	self.lastAnnouncement = 0
	self.startTime = 0
	
	self:InitializeCallbacks(fragment)
	self:InitializeControls()
end

function Helper:InitializeControls()
	self.buttons = {}
	
	HarvestFarmHelper.panel = HarvestFarmHelper
	HarvestFarmHelper.panel.data = {registerForRefresh = true}
	HarvestFarmHelper.panel.controlsToRefresh = {}
	
	local disabledFunction = function() return Farm.path == nil end
	
	HarvestFarmHelperDescription:SetText(Harvest.GetLocalization( "helperdescriptiondisabled" ))
	
	local control = WINDOW_MANAGER:CreateControlFromVirtual(nil, HarvestFarmHelper, "ZO_DefaultButton")
	control:SetText( Harvest.GetLocalization( "toggletour" ) )
	control:SetAnchor(TOPLEFT, HarvestFarmHelperDescription, BOTTOMLEFT, 0, 20)
	control:SetAnchor(TOPRIGHT, HarvestFarmHelperDescription, BOTTOMRIGHT, 0, 20)
	control:SetClickSound("Click")
	control:SetHandler("OnClicked", function(button, ...)
		if self:IsRunning() then
			self:Stop()
		else
			self:Start()
		end
	end)
	control:SetEnabled(false)
	local lastControl = control
	table.insert(self.buttons, control)
	
	control = WINDOW_MANAGER:CreateControlFromVirtual(nil, HarvestFarmHelper, "ZO_DefaultButton")
	control:SetText( Harvest.GetLocalization( "skiptarget" ) )
	control:SetAnchor(TOPLEFT, lastControl, BOTTOMLEFT, 0, 20)
	control:SetAnchor(TOPRIGHT, lastControl, BOTTOMRIGHT, 0, 20)
	control:SetClickSound("Click")
	control:SetHandler("OnClicked", function(button, ...)
		self:UpdateToNextTarget()
	end)
	control:SetEnabled(false)
	lastControl = control
	table.insert(self.buttons, control)
	
	control = WINDOW_MANAGER:CreateControlFromVirtual(nil, HarvestFarmHelper, "ZO_DefaultButton")
	control:SetText( Harvest.GetLocalization( "showtourinterface" ) )
	control:SetAnchor(TOPLEFT, lastControl, BOTTOMLEFT, 0, 20)
	control:SetAnchor(TOPRIGHT, lastControl, BOTTOMRIGHT, 0, 20)
	control:SetClickSound("Click")
	control:SetHandler("OnClicked", function(button, ...)
		self:SetCompassHidden(false)
	end)
	control:SetEnabled(false)
	table.insert(self.buttons, control)
end

function Helper:PostInitialize()
	HarvestFarmCompassSkipNodeButton:SetText( Harvest.GetLocalization( "skiptarget" ) )
	HarvestFarmCompassDistanceText:SetText( Harvest.GetLocalization( "distancetotarget" ) )
	if MasterMerchant then
		HarvestFarmCompassStatsText:SetText( Harvest.GetLocalization( "goldperminute" ) )
	else
		HarvestFarmCompassStatsText:SetText( Harvest.GetLocalization( "nodesperminute" ) )
	end
end

function Helper:InitializeCallbacks(fragment)
	
	EVENT_MANAGER:RegisterForEvent("HarvestMap-FarmingHelper", EVENT_LOOT_RECEIVED, function( eventCode, receivedBy, itemLink, stackCount, soundCategory, lootType, lootedBySelf )
		if lootedBySelf then
			self:GainedItem(itemLink, stackCount)
		end
	end)
	
	CallbackManager:RegisterForEvent(Events.NODE_DISCOVERED, function()
		Harvest.farm.helper:FarmedANode()
	end)

	CallbackManager:RegisterForEvent(Events.TOUR_CHANGED, function(event, path)
		self:Stop()
		if self.enabled == (path ~= nil) then
			return
		end
		self.enabled = (path ~= nil) 
		
		for _, button in pairs(self.buttons) do
			button:SetEnabled(self.enabled)
		end
		
		if self.enabled then
			HarvestFarmHelperDescription:SetText(Harvest.GetLocalization( "helperdescription" ))
		else
			HarvestFarmHelperDescription:SetText(Harvest.GetLocalization( "helperdescriptiondisabled" ))
		end
	end)
	
	function self.MapCallback(pinmanager)
		Harvest.Debug("farm map refresh called")
		--LMP.pinManager:RemovePins(LMP.pinManager.customPins[_G[ Harvest.GetPinType( Harvest.TOUR )]].pinTypeString)
		if not Farm.path then return end
		if not (Farm.path.mapCache.map == Harvest.GetMap()) then return end
		if not self:IsRunning() then return end
		local x, y = Farm.path:GetCoords(self.nextPathIndex)
		LMP:CreatePin( Harvest.GetPinType(Harvest.TOUR) , "TourPin", x, y )
		Harvest.Debug("farm map pins created")
	end

	function self.CompassCallback(pinmanager, pinType)
		Harvest.Debug("farm compass refresh called")
		if not Farm.path then return end
		if not self:IsRunning() then return end
		local x, y = Farm.path:GetGlobalCoords(self.nextPathIndex)
		local range = 1
		local pinTag = Harvest.GetPinType(Harvest.TOUR)
		pinmanager:AddCustomPin( pinTag, Harvest.TOUR, range, x, y )
		Harvest.Debug("farm compass pins created")
	end
	
	Harvest.InRangePins:RegisterCustomPinCallback(
		Harvest.TOUR,
		self.CompassCallback)
	
	self.tooltipCreator = {
		creator = function( pin ) -- this function is called when the mouse is over a pin and a tooltip has to be displayed
			local pinType, nodeId = pin:GetPinTypeAndTag()
			if nodeId == "TourPin" then
				InformationTooltip:AddLine( Harvest.GetLocalization("tourpin") )
				return
			end
		end,
		tooltip = 1
	}
	
	LMP:AddPinType(
		Harvest.GetPinType(Harvest.TOUR),
		self.MapCallback,
		nil,
		Harvest.GetMapPinLayout( Harvest.TOUR ),
		self.tooltipCreator
	)
	
	local sqrt = math.sqrt
	local pi = math.pi
	local atan2 = math.atan2
	local zo_round = _G["zo_round"]
	local zo_abs = _G["zo_abs"]
	local format = string.format
	local GetPlayerCameraHeading = _G["GetPlayerCameraHeading"]
	local GetMapPlayerPosition = _G["GetMapPlayerPosition"]
	local lastTime = 0
	
	function self.OnUpdate(time)
		
		HarvestFarmCompassStats:SetText(format("%.2f", self.numFarmedNodes / (time - self.startTime) * 1000 * 60))
		
		local x, y = GPS:LocalToGlobal(GetMapPlayerPosition( "player" ))
		if not x or not y then
			return
		end
		
		local targetX, targetY, worldZ = Farm.path:GetGlobalCoords(self.nextPathIndex)
		local dx = x - targetX
		local dy = y - targetY
		
		local minDistance = Harvest.GetGlobalMinDistanceBetweenPins()
		if dx * dx + dy * dy < minDistance * Harvest.GetVisitedRangeMultiplier() then
			self:UpdateToNextTarget()
		end
		
		HarvestFarmCompassDistance:SetText(format("%d m", zo_round(sqrt((dx * dx + dy * dy) / minDistance)*10*Farm.path.mapCache.measurement.distanceCorrection) ))
		
		if time - lastTime > 1000 then
			local x, y, z = Harvest.Get3DPosition()
			if not y then
				HarvestFarmCompassVerticalDistance:SetHidden(true)
			else
				HarvestFarmCompassVerticalDistance:SetHidden(false)
				local distance = y - worldZ
				local str
				if distance > 0 then
					str = zo_strformat(SI_TOOLTIP_BELOW_ME, format("%d m", zo_round(distance) ))
				else
					str = zo_strformat(SI_TOOLTIP_ABOVE_ME, format("%d m", zo_round(-distance) ))
				end
				HarvestFarmCompassVerticalDistance:SetText(str or "")
			end
			lastTime = time
		end
		
		local angle = -atan2(dx, dy)
		angle = (angle + GetPlayerCameraHeading())
		HarvestFarmCompassArrow:SetTextureRotation(-angle, 0.5, 0.5)
		if angle > pi then
			angle = angle - 2 * pi
		elseif angle < -pi then
			angle = angle + 2 * pi
		end
		angle = zo_abs(angle / pi)
		HarvestFarmCompassArrow:SetColor(2*angle-angle*angle, 1 - angle*angle, 0, 0.75)
		
	end
end

function Helper:SetCompassHidden(value)
	if (not value) and (not self:IsRunning()) then self:Start() end
	HarvestFarmCompass:SetHidden(value)
end

function Helper:IsCompassHidden()
	return HarvestFarmCompass:IsHidden()
end

function Helper:Start()
	self.startTime = GetFrameTimeMilliseconds()
	self.numFarmedNodes = 0
	self.nextPathIndex = 1
	
	EVENT_MANAGER:RegisterForUpdate("HarvestFarmUpdatePosition", 50, self.OnUpdate)
	self:SetCompassHidden(false)
	Harvest.RedrawPins( Harvest.TOUR )
end

function Helper:Stop()
	self.startTime = 0
	self.nextPathIndex = 1
	
	EVENT_MANAGER:UnregisterForUpdate("HarvestFarmUpdatePosition")
	HarvestFarmCompass:SetHidden(true)
	Harvest.RedrawPins( Harvest.TOUR )
end

function Helper:IsRunning()
	return self.startTime > 0
end

function Helper:OnPinClicked(pin)
	local pinType, nodeId = pin:GetPinTypeAndTag()
	
	local index = Farm.path:GetIndex(nodeId)
	if not index then return false end
	
	if not self:IsRunning() then
		self:Start()
	else
		self:SetCompassHidden(false)
	end
	
	self.nextPathIndex = index
	Harvest.RedrawPins( Harvest.TOUR )
	return true
end

function Helper:GainedItem(objectName, stackCount)
	if not (self.startTime > 0) then
		return
	end
	Harvest.Debug(objectName)
	if MasterMerchant then
		local stats = MasterMerchant:itemStats(objectName)
		if stats then
			self.numFarmedNodes = self.numFarmedNodes + (stats.avgPrice or 0) * stackCount
		end
	else
	--	self.numFarmedNodes = self.numFarmedNodes + 1
	end
end

function Helper:FarmedANode(objectName, stackCount)
	if not (self.startTime > 0) then
		return
	end
	Harvest.Debug(objectName)
	if MasterMerchant then
	--	self.numFarmedNodes = self.numFarmedNodes + (MasterMerchant:itemStats(objectName).avgPrice or 0) * stackCount
	else
		self.numFarmedNodes = self.numFarmedNodes + 1
	end
end

function Helper:UpdateToNextTarget()
	if not self:IsRunning() then return end
	self.nextPathIndex = (self.nextPathIndex % Farm.path.numNodes) + 1
	Harvest.RedrawPins( Harvest.TOUR )
	local time = GetFrameTimeMilliseconds()
	if time - self.lastAnnouncement > 1000 then
		CENTER_SCREEN_ANNOUNCE:AddMessage(0, CSA_EVENT_SMALL_TEXT, SOUNDS.QUEST_OBJECTIVE_STARTED, "HarvestMap farming tour updated")
		self.lastAnnouncement = time
	end
end

