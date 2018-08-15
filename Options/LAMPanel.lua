
local LAM = LibStub("LibAddonMenu-2.0")

Harvest = Harvest or {}
Harvest.settings = Harvest.settings or {}
local Settings = Harvest.settings

local function CreateFilter( pinTypeId )
	local pinTypeId = pinTypeId
	local filter = {
		type = "checkbox",
		name = Harvest.GetLocalization( "pintype" .. pinTypeId ),
		tooltip = Harvest.GetLocalization( "pintypetooltip" .. pinTypeId ),
		getFunc = function()
			return Harvest.IsMapPinTypeVisible( pinTypeId )
		end,
		setFunc = function( value )
			Harvest.SetMapPinTypeVisible( pinTypeId, value )
		end,
		default = Harvest.settings.defaultSettings.isPinTypeVisible[ pinTypeId ],
	}
	return filter
end

local function CreateIconPicker( pinTypeId )
	local pinTypeId = pinTypeId
	local filter = {
		type = "iconpicker",
		name = Harvest.GetLocalization( "pintexture" ),
		--tooltip = Harvest.GetLocalization( "pintexturetooltip" .. pinTypeId ),
		getFunc = function()
			return Harvest.GetPinTypeTexture( pinTypeId )
		end,
		setFunc = function( value )
			Harvest.SetPinTypeTexture( pinTypeId, value )
		end,
		choices = Harvest.settings.availableTextures[pinTypeId],
		default = Harvest.settings.defaultSettings.pinLayouts[ pinTypeId ].texture,
		--width = "half",
	}
	return filter
end

local function CreateGatherFilter( pinTypeId )
	local pinTypeId = pinTypeId
	local gatherFilter = {
		type = "checkbox",
		name = zo_strformat( Harvest.GetLocalization( "savepin" ), Harvest.GetLocalization( "pintype" .. pinTypeId ) ),
		tooltip = Harvest.GetLocalization( "savetooltip" ),
		getFunc = function()
			return Harvest.IsPinTypeSavedOnGather( pinTypeId )
		end,
		setFunc = function( value )
			Harvest.SetPinTypeSavedOnGather( pinTypeId, value )
		end,
		default = Harvest.settings.defaultSettings.isPinTypeSavedOnGather[ pinTypeId ],
	}
	return gatherFilter
end

local function CreateSizeSlider( pinTypeId )
	local pinTypeId = pinTypeId
	local sizeSlider = {
		type = "slider",
		name = Harvest.GetLocalization( "pinsize" ),
		tooltip = Harvest.GetLocalization( "pinsizetooltip" ),
		min = 12,
		max = 64,
		getFunc = function()
			return Harvest.GetMapPinSize( pinTypeId )
		end,
		setFunc = function( value )
			Harvest.SetMapPinSize( pinTypeId, value )
		end,
		default = Harvest.settings.defaultSettings.pinLayouts[ pinTypeId ].size,
		--width = "half",
	}
	return sizeSlider
end

local function CreateColorPicker( pinTypeId )
	local pinTypeId = pinTypeId
	local colorPicker = {
		type = "colorpicker",
		name = Harvest.GetLocalization( "pincolor" ),
		tooltip = zo_strformat( Harvest.GetLocalization( "pincolortooltip" ), Harvest.GetLocalization( "pintype" .. pinTypeId ) ),
		getFunc = function() return Harvest.GetPinColor( pinTypeId ) end,
		setFunc = function( r, g, b ) Harvest.SetPinColor( pinTypeId, r, g, b ) end,
		default = Harvest.settings.defaultSettings.pinLayouts[ pinTypeId ].tint,
		--width = "half",
	}
	return colorPicker
end

function Settings:InitializeLAM()
	-- first LAM stuff, at the end of this function we will also create
	-- a custom checkbox in the map's filter menu for the heat map
	local panelData = {
		type = "panel",
		name = "HarvestMap",
		displayName = ZO_HIGHLIGHT_TEXT:Colorize("HarvestMap"),
		author = Harvest.author,
		version = Harvest.displayVersion,
		registerForRefresh = true,
		registerForDefaults = true,
		website = "http://www.esoui.com/downloads/info57",
	}

	local optionsTable = setmetatable({}, { __index = table })

	optionsTable:insert({
		type = "description",
		title = nil,
		text = Harvest.GetLocalization("esouidescription"),
		width = "full",
	})

	optionsTable:insert({
		type = "button",
		name = Harvest.GetLocalization("openesoui"),
		func = function() RequestOpenUnsafeURL("http://www.esoui.com/downloads/info57") end,
		width = "half",
	})
	
	optionsTable:insert({
		type = "description",
		title = nil,
		text = Harvest.GetLocalization("exchangedescription"),
		width = "full",
	})
	
	optionsTable:insert({
		type = "header",
		name = "",
	})
	
	optionsTable:insert({
		type = "description",
		title = nil,
		text = Harvest.GetLocalization("debuginfodescription"),
		width = "full",
	})
	
	optionsTable:insert({
		type = "button",
		name = Harvest.GetLocalization("printdebuginfo"),
		func = function() HarvestDebugClipboardOutputBox:SetText(Harvest.GenerateDebugInfo()) end,
		width = "half",
	})
	
	optionsTable:insert({
		type = "header",
		name = "",
	})
	
	local submenuTable = setmetatable({}, { __index = table })
	optionsTable:insert({
		type = "submenu",
		name = Harvest.GetLocalization("outdateddata"),
		controls = submenuTable,
	})
	
	submenuTable:insert({
		type = "description",
		title = nil,
		text = Harvest.GetLocalization("outdateddatainfo")
	})
	
	submenuTable:insert({
		type = "dropdown",
		name = Harvest.GetLocalization("mingameversion"),
		tooltip = Harvest.GetLocalization("mingameversiontooltip"),
		choices = Harvest.validGameVersionsDisplay,
		choicesValues = Harvest.validGameVersions,
		getFunc = Harvest.GetDisplayedMinGameVersion,
		setFunc = Harvest.SetDisplayedMinGameVersion,
		width = "half",
		--default = Harvest.settings.defaultSettings.minGameVersion,
	})
	
	submenuTable:insert({--optionsTable
		type = "slider",
		name = Harvest.GetLocalization("timedifference"),
		tooltip = Harvest.GetLocalization("timedifferencetooltip"),
		min = 0,
		max = 712,
		getFunc = function()
			return Harvest.GetDisplayedMaxTimeDifference() / 24
		end,
		setFunc = function( value )
			Harvest.SetDisplayedMaxTimeDifference(value * 24)
		end,
		width = "half",
		default = 0,
	})
	
	submenuTable:insert({
		type = "button",
		name = GetString(SI_APPLY),--Harvest.GetLocalization("apply"),
		func = Harvest.ApplyTimeDifference,
		width = "half",
		warning = Harvest.GetLocalization("applywarning")
	})

	optionsTable:insert({
		type = "header",
		name = "",
	})

	optionsTable:insert({
		type = "checkbox",
		name = Harvest.GetLocalization("account"),
		tooltip = Harvest.GetLocalization("accounttooltip"),
		getFunc = Harvest.AreSettingsAccountWide,
		setFunc = Harvest.SetSettingsAccountWide,
		width = "full",
		warning = Harvest.GetLocalization("accountwarning"),
		--requireReload = true, -- doesn't work?
	})
	
	
	local submenuTable = setmetatable({}, { __index = table })
	optionsTable:insert({
		type = "submenu",
		name = Harvest.GetLocalization("performance"),
		controls = submenuTable,
	})
	
	submenuTable:insert({
		type = "checkbox",
		name = Harvest.GetLocalization("hasdrawdistance"),
		tooltip = Harvest.GetLocalization("hasdrawdistancetooltip"),
		warning = Harvest.GetLocalization("hasdrawdistancewarning"),
		getFunc = Harvest.HasPinVisibleDistance,
		setFunc = Harvest.SetHasPinVisibleDistance,
		default = Harvest.settings.defaultSettings.hasMaxVisibleDistance,
		width = "half",
	})

	submenuTable:insert({
		type = "slider",
		name = Harvest.GetLocalization("drawdistance"),
		tooltip = Harvest.GetLocalization("drawdistancetooltip"),
		warning = Harvest.GetLocalization("drawdistancewarning"),
		min = 100,
		max = 1000,
		getFunc = Harvest.GetDisplayPinVisibleDistance,
		setFunc = Harvest.SetPinVisibleDistance,
		default = 300,
		width = "half",
		disabled = function()
			if Harvest.HasPinVisibleDistance() then
				return false
			end
			if FyrMM or (AUI and AUI.Minimap:IsEnabled()) or VOTANS_MINIMAP then
				return false
			end
			return true
		end,
	})
	
	submenuTable:insert({
		type = "description",
		title = nil,
		text = Harvest.GetLocalization("minimapcompatibilitymodedescription"),
		width = "full",
	})
	
	submenuTable:insert({
		type = "checkbox",
		name = Harvest.GetLocalization("minimapcompatibilitymode"),
		tooltip = Harvest.GetLocalization("minimapcompatibilitymodewarning"),
		warning = Harvest.GetLocalization("minimapcompatibilitymodewarning"),
		getFunc = Harvest.IsMinimapCompatibilityModeEnabled,
		setFunc = Harvest.SetMinimapCompatibilityModeEnabled,
		default = Harvest.settings.defaultSettings.minimapCompatibility,
		width = "full",
	})
	
	local submenuTable = setmetatable({}, { __index = table })
	optionsTable:insert({
		type = "submenu",
		name = Harvest.GetLocalization("farmandrespawn"),
		controls = submenuTable,
	})
	
	submenuTable:insert({
		type = "slider",
		name = Harvest.GetLocalization("rangemultiplier"),
		tooltip = Harvest.GetLocalization("rangemultipliertooltip"),
		min = 5,
		max = 20,
		getFunc = Harvest.GetDisplayedVisitedRangeMultiplier,
		setFunc = Harvest.SetDisplayedVisitedRangeMultiplier,
		default = 10,
	})
	
	submenuTable:insert({
		type = "slider",
		name = Harvest.GetLocalization("hiddentime"),
		tooltip = Harvest.GetLocalization("hiddentimetooltip"),
		min = 0,
		max = 30,
		getFunc = Harvest.GetHiddenTime,
		setFunc = Harvest.SetHiddenTime,
		default = 0,
	})

	submenuTable:insert({
		type = "checkbox",
		name = Harvest.GetLocalization("hiddenonharvest"),
		tooltip = Harvest.GetLocalization("hiddenonharvesttooltip"),
		warning = Harvest.GetLocalization("hiddenonharvestwarning"),
		getFunc = Harvest.IsHiddenOnHarvest,
		setFunc = Harvest.SetHiddenOnHarvest,
		default = Harvest.settings.defaultSettings.hiddenOnHarvest,
	})
	
	
	local submenuTable = setmetatable({}, { __index = table })
	optionsTable:insert({
		type = "submenu",
		name = Harvest.GetLocalization("compassandworld"),
		controls = submenuTable,
	})
	
	submenuTable:insert({
		type = "checkbox",
		name = Harvest.GetLocalization("compass"),
		tooltip = Harvest.GetLocalization("compasstooltip"),
		getFunc = Harvest.AreCompassPinsVisible,
		setFunc = function(...)
			Harvest.SetCompassPinsVisible(...)
			CALLBACK_MANAGER:FireCallbacks("LAM-RefreshPanel", HarvestMapInRangeMenu.panel)
		end,
		default = Harvest.settings.defaultSettings.displayCompassPins,
	})

	submenuTable:insert({
		type = "slider",
		name = Harvest.GetLocalization("compassdistance"),
		tooltip = Harvest.GetLocalization("compassdistancetooltip"),
		min = 50,
		max = 250,
		getFunc = Harvest.GetDisplayedCompassDistance,
		setFunc = Harvest.SetDisplayedCompassDistance,
		default = 100,
	})
	
	submenuTable:insert({
		type = "checkbox",
		name = Harvest.GetLocalization("worldpins"),
		tooltip = Harvest.GetLocalization("worldpinstooltip"),
		getFunc = Harvest.AreWorldPinsVisible,
		setFunc = function(...)
			Harvest.SetWorldPinsVisible(...)
			CALLBACK_MANAGER:FireCallbacks("LAM-RefreshPanel", HarvestMapInRangeMenu.panel)
		end,
		default = Harvest.settings.defaultSettings.displayWorldPins,
	})

	submenuTable:insert({
		type = "slider",
		name = Harvest.GetLocalization("worlddistance"),
		tooltip = Harvest.GetLocalization("worlddistancetooltip"),
		min = 50,
		max = 250,
		getFunc = Harvest.GetDisplayedWorldDistance,
		setFunc = Harvest.SetDisplayedWorldDistance,
		default = 100,
	})
	
	submenuTable:insert({
		type = "slider",
		name = Harvest.GetLocalization("worldpinwidth"),
		tooltip = Harvest.GetLocalization("worldpinwidthtooltip"),
		min = 50,
		max = 300,
		getFunc = Harvest.GetWorldPinWidth,
		setFunc = Harvest.SetWorldPinWidth,
		default = Harvest.settings.defaultSettings.worldPinWidth,
	})
	
	submenuTable:insert({
		type = "slider",
		name = Harvest.GetLocalization("worldpinheight"),
		tooltip = Harvest.GetLocalization("worldpinheighttooltip"),
		min = 100,
		max = 600,
		getFunc = Harvest.GetWorldPinHeight,
		setFunc = Harvest.SetWorldPinHeight,
		default = Harvest.settings.defaultSettings.worldPinHeight,
	})
	
	submenuTable:insert({
		type = "checkbox",
		name = Harvest.GetLocalization("worldpinsdepth"),
		tooltip = Harvest.GetLocalization("worldpinsdepthtooltip"),
		--warning = Harvest.GetLocalization("worldpinsdepthwarning"),
		getFunc = Harvest.DoWorldPinsUseDepth,
		setFunc = Harvest.SetWorldPinsUseDepth,
		default = Harvest.settings.defaultSettings.worldPinDepth,
	})
	
	local submenuTable = setmetatable({}, { __index = table })
	optionsTable:insert({
		type = "submenu",
		name = Harvest.GetLocalization("pinoptions"),
		controls = submenuTable,
	})
	
	submenuTable:insert({
		type = "description",
		title = nil,
		text = Harvest.GetLocalization("extendedpinoptions"),
		width = "full",
	})

	submenuTable:insert({
		type = "button",
		name = Harvest.GetLocalization("extendedpinoptionsbutton"),
		func = function() Harvest.menu:Toggle() end,
		width = "half",
	})
	
	submenuTable:insert({
		type = "checkbox",
		name = Harvest.GetLocalization("level"),
		tooltip = Harvest.GetLocalization("leveltooltip"),
		getFunc = Harvest.ArePinsAbovePOI,
		setFunc = Harvest.SetPinsAbovePOI,
		default = Harvest.settings.defaultSettings.pinsAbovePoi,
	})
	
	submenuTable:insert({
		type = "slider",
		name = Harvest.GetLocalization( "pinminsize" ),
		tooltip = Harvest.GetLocalization( "pinminsizetooltip" ),
		min = 8,
		max = 32,
		getFunc = function()
			return Harvest.GetMapPinMinSize()
		end,
		setFunc = function( value )
			Harvest.SetMapPinMinSize( value )
		end,
		default = Harvest.settings.defaultSettings.mapPinMinSize,
		--width = "half",
	})
	
	for _, pinTypeId in ipairs( Harvest.PINTYPES ) do
		if not Harvest.HIDDEN_PINTYPES[pinTypeId] then--and not Harvest.GetPinTypeInGroup(pinTypeId) then
			submenuTable:insert({
				type = "header",
				name = Harvest.GetLocalization( "pintype" .. pinTypeId )
			})
			submenuTable:insert( CreateFilter( pinTypeId ) )
			--optionsTable:insert( CreateImportFilter( pinTypeId ) ) -- moved to the HarvestImport folder
			submenuTable:insert( CreateGatherFilter( pinTypeId ) )
			submenuTable:insert( CreateColorPicker( pinTypeId ) )
			submenuTable:insert( CreateIconPicker( pinTypeId ) )
			submenuTable:insert( CreateSizeSlider( pinTypeId ) )
		end
	end

	--optionsTable:insert({
	--	type = "header",
	--	name = Harvest.GetLocalization("debugoptions"),
	--})
	--[[
	optionsTable:insert({
		type = "checkbox",
		name = Harvest.GetLocalization( "debug" ),
		tooltip = Harvest.GetLocalization( "debugtooltip" ),
		getFunc = Harvest.AreDebugMessagesEnabled,
		setFunc = Harvest.SetDebugMessagesEnabled,
		default = Harvest.settings.defaultSettings.debug,
	})
	]]
	Harvest.optionsPanel = LAM:RegisterAddonPanel("HarvestMapControl", panelData)
	LAM:RegisterOptionControls("HarvestMapControl", optionsTable)

end
