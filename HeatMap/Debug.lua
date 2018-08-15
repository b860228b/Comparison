
Harvest = Harvest or {}

local log = {numEntries = 0}
local maxNum = 300
-- helper function to only display debug messages if the debug mode is enabled
function Harvest.Debug( message )
	message = tostring(message)
	if Harvest.AreDebugMessagesEnabled() then
		d( message )
	end
	log.numEntries = log.numEntries + 1
	log[log.numEntries] = tostring(log.numEntries) .. ": " .. message
	log[log.numEntries - maxNum] = nil
end

function Harvest.OutputDebugLog()
	local tbl, j = {}, 1
	for i = 1, maxNum do
		tbl[i] = log[log.numEntries - i + 1]
	end
	ZO_ERROR_FRAME:OnUIError(table.concat(tbl, "\n"))
end

function Harvest.CheckFolderStructure()
	local success, error_msg = pcall(function() error("") end)
	local structure = string.match(error_msg, "user:/AddOns/(.-)Debug.lua:")
	if structure ~= "HarvestMap/" then
		ZO_ERROR_FRAME:OnUIError("The HarvestMap AddOn was installed incorrectly. The AddOn should be installed as: 'AddOns/HarvestMap/' instead of 'AddOns/" .. structure .."'")
	end
end

function Harvest.GetErrorLog()
	return Harvest.settings.savedVars.global.errorlog
end

function Harvest.AddToErrorLog(message)
	local log = Harvest.settings.savedVars.global.errorlog
	log.last = log.last + 1
	if log.last - log.start > 50 then
		log[log.start] = nil
		log.start = log.start + 1
	end
	log[log.last] = message
	if log.start > 50 then
		Harvest.ClearErrorLog()
		local newLog = Harvest.settings.savedVars.global.errorlog
		for i = log.start, log.last do
			newLog[i - log.start + 1] = log[i]
		end
	end
end

function Harvest.ClearErrorLog()
	Harvest.settings.savedVars.global.errorlog = {start = 1, last=0}
end

function Harvest.GenerateDebugInfo()
	list = {}
	table.insert(list, "[spoiler][code]\n")
	table.insert(list, "Version:")
	table.insert(list, Harvest.displayVersion)
	table.insert(list, "\n")
	for key, value in pairs(Harvest.settings.defaultSettings) do
		value = Harvest.settings.savedVars.settings[key]
		if type(value) ~= "table" then
			table.insert(list, key)
			table.insert(list, ":")
			table.insert(list, tostring(value))
			table.insert(list, "\n")
		else
			local k, v = next(value)
			if type(v) == "boolean" then
				table.insert(list, key)
				table.insert(list, ":")
				for k, v in ipairs(value) do
					if v then
						table.insert(list, "y")
					else
						table.insert(list, "n")
					end
				end
				table.insert(list, "\n")
			end
		end
	end
	table.insert(list, "Addons:\n")
	local addonManager = GetAddOnManager()
	for addonIndex = 1, addonManager:GetNumAddOns() do
		local name, _, _, _, enabled = addonManager:GetAddOnInfo(addonIndex)
		if enabled then
			table.insert(list, name)
			table.insert(list, "\n")
		end
	end
	table.insert(list, "[/code][/spoiler]")
	return table.concat(list)
end
