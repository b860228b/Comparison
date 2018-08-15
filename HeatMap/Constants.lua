
Harvest = Harvest or {}

-- data version numbers:
-- 10 = Orsinium (all nodes are saved as ACE strings)
-- 11 = Thieves Guild (nodes can now store multiple itemIds)
-- 12 = Trove fix
-- 13 = DB data (removed node names, enchantment item ids, added itemid -> timestamp format)
-- 14 = One Tamriel (changed pinTypeIds to be consecutive again)
-- 15 = Housing (split alchemy nodes)
-- 16 = Housing 2 (changed timestamp accuracy)
-- 17 = changed save file structure and node structure
Harvest.dataVersion = 17

-- addon version numbers:
-- 0 or nil = before this number was introduced
-- 1 = filter local nodes which were saved with their global coords instead of local ones
-- since 2.3.0 incremental:
-- 2 = 3.3.0
-- 3 = 3.3.1
-- 4 = 3.4.0
-- 5 = 3.4.1
-- 6 = 3.4.2
-- 7 = 3.4.3
-- 8 = 3.4.4 - 3.4.7
-- 9 = 3.4.8 - 3.4.10
-- 10 = 3.4.11 - 3.4.14
-- 11 = 3.4.15
-- 12 = 3.5.0
-- 13 = 3.5.4
-- 14 = 3.5.5 (might be 13)
-- 15 = 3.5.6
-- 16 = 3.6.0
-- 17 = 3.6.4 change in map focus logic
-- 18 revert to setmaptoplayerlocation
-- 19 save global on new node
-- 20 3.7.0
-- 21 3.7.5 changed 3d pin height
-- 22 3.7.7 changed 3d pin height
-- 23 3.8.0
-- 24 3.9.0 rework of data structure, added database exchange batch script
-- 25 3.9.4 save flags on harvest
-- 26 3.9.6 perform map click when retrieving node position
-- 27 3.10.0 save jewelry, clams and psijic portals
-- 28 3.10.10 changed merge logic
-- 29 3.10.11 updated data version
-- 30 3.11.0 refactored interaction code
Harvest.addonVersion = 30
Harvest.displayVersion = "3.11.4"

Harvest.author = "Shinni"

-- node version which is saved for each node
-- the node version encodes the current game and addon version
-- this is used to detect invalid data caused by addon bugs and game changes (ie sometimes maps get rescaled/translated)
local version, update, patch = string.match(GetESOVersionString(), "(%d+)%.(%d+)%.(%d+)")
-- encode 2.5.4 as 20504, let's hope we never get more than 99 patches for an update :D
local versionInteger = tonumber(version) * 10000 + tonumber(update) * 100 + tonumber(patch)
-- the addon has far less than 100 updates per year, so the upcoming 10 years should be fine with this offset
Harvest.VersionOffset = 1000
Harvest.nodeVersion = Harvest.VersionOffset * versionInteger + Harvest.addonVersion
local nodeVersion = Harvest.nodeVersion
-- example: game version is 2.5.4, addon version is 2:
-- node version is thus 20504002

Harvest.validGameVersions = {
	"4.0.0", -- summerset
	"3.3.0", -- dragon bones
	"3.2.0", -- CwC
	"3.1.0", -- hoftr
	"3.0.0", -- morrowind
	"2.7.0", -- housing
	"2.6.0", -- one tamriel
	"2.5.0", -- shadow of the hist
	"2.4.0", -- dark bortherhood
	"2.3.0", -- thieves guild
	-- the following game versions weren't stored in the node data
	-- "2.2.0", -- wrothgar
	-- "2.1.0", -- imperial city
	-- "2.0.0", -- tamriel unlimited
	"1.0.0",
}

Harvest.validGameVersionsDisplay = {
	"4.0.0 - Summerset",
	"3.3.0 - Dragon Bones",
	"3.2.0 - Clockwork City",
	"3.1.0 - Horns of the Reach",
	"3.0.0 - Morrowind",
	"2.7.0 - Housing",
	"2.6.0 - One Tamriel",
	"2.5.0 - Shadows of the Hist",
	"2.4.0 - Dark Brotherhood",
	"2.3.0 - Thieves Guild",
	-- the following game versions weren't stored in the node data
	-- "2.2.0", -- wrothgar
	-- "2.1.0", -- imperial city
	-- "2.0.0", -- tamriel unlimited
	"1.0.0",
}

function Harvest.GetGlobalMinDistanceBetweenPins()
	-- about 10m in tamriel map squared distance (only on zone/city maps)
	return 1.6e-7
end
