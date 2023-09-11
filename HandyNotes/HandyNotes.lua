﻿--[[
HandyNotes
]]

---------------------------------------------------------
-- Addon declaration
HandyNotes = LibStub("AceAddon-3.0"):NewAddon("HandyNotes", "AceConsole-3.0", "AceEvent-3.0")
local HandyNotes = HandyNotes
local L = LibStub("AceLocale-3.0"):GetLocale("HandyNotes", false)
local Astrolabe = DongleStub("Astrolabe-0.4")


---------------------------------------------------------
-- Our db upvalue and db defaults
local db
local options
local defaults = {
	profile = {
		enabled       = true,
		icon_scale    = 1.0,
		icon_alpha    = 1.0,
		icon_scale_minimap = 1.0,
		icon_alpha_minimap = 0.0,
		enabledPlugins = {
			['*'] = true,
		},
	},
}


---------------------------------------------------------
-- Localize some globals
local floor = floor
local tconcat = table.concat
local pairs, next, type = pairs, next, type
local CreateFrame = CreateFrame
local GetCurrentMapContinent, GetCurrentMapZone = GetCurrentMapContinent, GetCurrentMapZone
local GetCurrentMapDungeonLevel = GetCurrentMapDungeonLevel
local GetRealZoneText = GetRealZoneText
local WorldMapButton, Minimap = WorldMapButton, Minimap


---------------------------------------------------------
-- xpcall safecall implementation, copied from AceAddon-3.0.lua
-- (included in distribution), with permission from nevcairiel
local xpcall = xpcall

local function errorhandler(err)
	return geterrorhandler()(err)
end

local function CreateDispatcher(argCount)
	local code = [[
		local xpcall, eh = ...
		local method, ARGS
		local function call() return method(ARGS) end
	
		local function dispatch(func, ...)
			 method = func
			 if not method then return end
			 ARGS = ...
			 return xpcall(call, eh)
		end
	
		return dispatch
	]]
	
	local ARGS = {}
	for i = 1, argCount do ARGS[i] = "arg"..i end
	code = code:gsub("ARGS", tconcat(ARGS, ", "))
	return assert(loadstring(code, "safecall Dispatcher["..argCount.."]"))(xpcall, errorhandler)
end

local Dispatchers = setmetatable({}, {__index=function(self, argCount)
	local dispatcher = CreateDispatcher(argCount)
	rawset(self, argCount, dispatcher)
	return dispatcher
end})
Dispatchers[0] = function(func)
	return xpcall(func, errorhandler)
end

local function safecall(func, ...)
	-- we check to see if the func is passed is actually a function here and don't error when it isn't
	-- this safecall is used for optional functions like OnInitialize OnEnable etc. When they are not
	-- present execution should continue without hinderance
	if type(func) == "function" then
		return Dispatchers[select('#', ...)](func, ...)
	end
end


---------------------------------------------------------
-- Our frames recycling code
local pinCache = {}
local minimapPins = {}
local worldmapPins = {}
local pinCount = 0

local function recyclePin(pin)
	pin:Hide()
	pinCache[pin] = true
end

local function clearAllPins(t)
	for coord, pin in pairs(t) do
		recyclePin(pin)
		t[coord] = nil
	end
end

local function getNewPin()
	local pin = next(pinCache)
	if pin then
		pinCache[pin] = nil -- remove it from the cache
		return pin
	end
	-- create a new pin
	pinCount = pinCount + 1
	pin = CreateFrame("Button", "HandyNotesPin"..pinCount, WorldMapButton)
	pin:SetFrameLevel(5)
	pin:EnableMouse(true)
	pin:SetWidth(12)
	pin:SetHeight(12)
	pin:SetPoint("CENTER", WorldMapButton, "CENTER")
	local texture = pin:CreateTexture(nil, "OVERLAY")
	pin.texture = texture
	texture:SetAllPoints(pin)
	pin:RegisterForClicks("LeftButtonDown", "LeftButtonUp", "RightButtonDown", "RightButtonUp")
	pin:SetMovable(true)
	pin:Hide()
	return pin
end


---------------------------------------------------------
-- Plugin handling
HandyNotes.plugins = {}
local pluginsOptionsText = {}

--[[ Documentation:
HandyNotes.plugins table contains every plugin which we will use to iterate over.
In this table, the format is:
	["Name of plugin"] = {table containing a set of standard functions, which we'll call pluginHandler}

Standard functions we require for every plugin:
	iter, state, value = pluginHandler:GetNodes(mapFile, minimap, dungeonLevel)
		Parameters
		- mapFile: The zone we want data for
		- minimap: Boolean argument indicating that we want to get nodes to display for the minimap
		- dungeonLevel: Level of the dungeon map. 0 indicates the zone has no dungeon levels
		Returns:
		- iter: An iterator function that will loop over and return 5 values
			(coord, mapFile, iconpath, scale, alpha)
			for every node in the requested zone. If the mapFile return value is nil, we assume it is the
			same mapFile as the argument passed in. Mainly used for continent mapFile where the map passed
			in is a continent, and the return values are coords of subzone maps.
		- state, value: First 2 args to pass into iter() on the initial iteration

Standard functions you can provide optionally:
	pluginHandler:OnEnter(mapFile, coord)
		Function we will call when the mouse enters a HandyNote, you will generally produce a tooltip here.
	pluginHandler:OnLeave(mapFile, coord)
		Function we will call when the mouse leaves a HandyNote, you will generally hide the tooltip here.
	pluginHandler:OnClick(button, down, mapFile, coord)
		Function we will call when the user clicks on a HandyNote, you will generally produce a menu here on right-click.
]]

function HandyNotes:RegisterPluginDB(pluginName, pluginHandler, optionsTable)
	if self.plugins[pluginName] ~= nil then
		error(pluginName.." is already registered by another plugin.")
	else
		self.plugins[pluginName] = pluginHandler
	end
	worldmapPins[pluginName] = {}
	minimapPins[pluginName] = {}
	options.args.plugins.args[pluginName] = optionsTable
	pluginsOptionsText[pluginName] = optionsTable and optionsTable.name or pluginName
end


local pinsHandler = {}
function pinsHandler:OnEnter(motion)
	WorldMapBlobFrame:SetScript("OnUpdate", nil) -- override default UI to hide the tooltip
	safecall(HandyNotes.plugins[self.pluginName].OnEnter, self, self.mapFile, self.coord)
end
function pinsHandler:OnLeave(motion)
	WorldMapBlobFrame:SetScript("OnUpdate", WorldMapBlobFrame_OnUpdate) -- restore default UI
	safecall(HandyNotes.plugins[self.pluginName].OnLeave, self, self.mapFile, self.coord)
end
function pinsHandler:OnClick(button, down)
	safecall(HandyNotes.plugins[self.pluginName].OnClick, self, button, down, self.mapFile, self.coord)
end


---------------------------------------------------------
-- Public functions

-- Public functions for plugins to convert between MapFile <-> C,Z
local continentMapFile = {
	[WORLDMAP_COSMIC_ID] = "Cosmic", -- That constant is -1
	[0] = "World",
	[1] = "Kalimdor",
	[2] = "Azeroth",
	[3] = "Expansion01",
	[4] = "Northrend",
}
local reverseMapFileC = {}
local reverseMapFileZ = {}
for C = 1, #Astrolabe.ContinentList do
	for Z = 1, #Astrolabe.ContinentList[C] do
		local mapFile = Astrolabe.ContinentList[C][Z]
		reverseMapFileC[mapFile] = C
		reverseMapFileZ[mapFile] = Z
	end
end
for C = -1, 4 do
	local mapFile = continentMapFile[C]
	reverseMapFileC[mapFile] = C
	reverseMapFileZ[mapFile] = 0
end

function HandyNotes:GetMapFile(C, Z)
	if not C or not Z then return end
	if Z == 0 then
		return continentMapFile[C]
	elseif C > 0 then
		return Astrolabe.ContinentList[C][Z]
	end
end
function HandyNotes:GetCZ(mapFile)
	return reverseMapFileC[mapFile], reverseMapFileZ[mapFile]
end

-- Public functions for plugins to convert between coords <--> x,y
function HandyNotes:getCoord(x, y)
	return floor(x * 10000 + 0.5) * 10000 + floor(y * 10000 + 0.5)
end
function HandyNotes:getXY(id)
	return floor(id / 10000) / 10000, (id % 10000) / 10000
end

-- Public functions for plugins to convert between GetRealZoneText() <-> C,Z
-- GetRealZoneText() returns localized strings, so these are also the functions
-- to get localized display strings.
local continentList = {GetMapContinents()}
local zoneList = {}
local reverseZoneC = {}
local reverseZoneZ = {}
for C, cname in pairs(continentList) do
	reverseZoneC[cname] = C
	reverseZoneZ[cname] = 0
	zoneList[C] = {GetMapZones(C)}
	for Z, zname in pairs(zoneList[C]) do
		reverseZoneC[zname] = C
		reverseZoneZ[zname] = Z
	end
end

function HandyNotes:GetZoneToCZ(zone)
	return reverseZoneC[zone], reverseZoneZ[zone]
end
function HandyNotes:GetCZToZone(C, Z)
	if not C or not Z then return end
	if Z == 0 then
		return continentList[C]
	elseif C > 0 then
		return zoneList[C][Z]
	end
end


---------------------------------------------------------
-- Core functions

-- This function updates all the icons of one plugin on the world map
function HandyNotes:UpdateWorldMapPlugin(pluginName)
	if not WorldMapButton:IsVisible() then return end

	clearAllPins(worldmapPins[pluginName])
	if not db.enabledPlugins[pluginName] then return end

	local ourScale, ourAlpha = 12 * db.icon_scale, db.icon_alpha
	local continent, zone, level = GetCurrentMapContinent(), GetCurrentMapZone(), GetCurrentMapDungeonLevel()
	local mapFile = GetMapInfo() or self:GetMapFile(continent, zone) -- Fallback for "Cosmic" and "World"
	local pluginHandler = self.plugins[pluginName]
	local frameLevel = WorldMapButton:GetFrameLevel() + 5
	local frameStrata = WorldMapButton:GetFrameStrata()

	for coord, mapFile2, iconpath, scale, alpha in pluginHandler:GetNodes(mapFile, false, level) do
		-- Scarlet Enclave check, only do stuff if we're on that map, since we have no zone translation for it yet in Astrolabe
		if mapFile2 ~= "ScarletEnclave" or mapFile2 == mapFile then
		local icon = getNewPin()
		icon:SetParent(WorldMapButton)
		icon:SetFrameStrata(frameStrata)
		icon:SetFrameLevel(frameLevel)
		scale = ourScale * scale
		icon:SetHeight(scale) -- Can't use :SetScale as that changes our positioning scaling as well
		icon:SetWidth(scale)
		icon:SetAlpha(ourAlpha * alpha)
		local t = icon.texture
		if type(iconpath) == "table" then
			if iconpath.tCoordLeft then
				t:SetTexCoord(iconpath.tCoordLeft, iconpath.tCoordRight, iconpath.tCoordTop, iconpath.tCoordBottom)
			else
				t:SetTexCoord(0, 1, 0, 1)
			end
			if iconpath.r then
				t:SetVertexColor(iconpath.r, iconpath.g, iconpath.b, iconpath.a)
			else
				t:SetVertexColor(1, 1, 1, 1)
			end
			t:SetTexture(iconpath.icon)
		else
			t:SetTexCoord(0, 1, 0, 1)
			t:SetVertexColor(1, 1, 1, 1)
			t:SetTexture(iconpath)
		end
		icon:SetScript("OnClick", pinsHandler.OnClick)
		icon:SetScript("OnEnter", pinsHandler.OnEnter)
		icon:SetScript("OnLeave", pinsHandler.OnLeave)
		local C, Z
		if mapFile2 then
			C, Z = self:GetCZ(mapFile2)
		else
			C, Z = continent, zone
		end
		local x, y = floor(coord / 10000) / 10000, (coord % 10000) / 10000
		if not C or not Z or C == WORLDMAP_COSMIC_ID then
			icon:ClearAllPoints()
			icon:SetPoint("CENTER", WorldMapButton, "TOPLEFT", x*WorldMapButton:GetWidth(), -y*WorldMapButton:GetHeight())
			icon:Show()
		else
			Astrolabe:PlaceIconOnWorldMap(WorldMapButton, icon, C, Z, x, y)
		end
		t:ClearAllPoints()
		t:SetAllPoints(icon) -- Not sure why this is necessary, but people are reporting weirdly sized textures
		worldmapPins[pluginName][(C or 0)*1e10 + (Z or 0)*1e8 + coord] = icon
		icon.pluginName = pluginName
		icon.coord = coord
		icon.mapFile = mapFile2 or mapFile
		end
	end
end

-- This function updates all the icons on the world map for every plugin
function HandyNotes:UpdateWorldMap()
	if not WorldMapButton:IsVisible() then return end
	for pluginName, pluginHandler in pairs(self.plugins) do
		safecall(self.UpdateWorldMapPlugin, self, pluginName)
	end
end


-- This function updates all the icons of one plugin on the world map
function HandyNotes:UpdateMinimapPlugin(pluginName)
	--if not Minimap:IsVisible() then return end

	for coordID, icon in pairs(minimapPins[pluginName]) do
		Astrolabe:RemoveIconFromMinimap(icon)
	end
	clearAllPins(minimapPins[pluginName])
	if not db.enabledPlugins[pluginName] then return end

	local continent, zone = HandyNotes:GetZoneToCZ(GetRealZoneText())
	local level = GetCurrentMapDungeonLevel()
	local mapFile = self:GetMapFile(continent, zone) -- or GetMapInfo() -- Astrolabe doesn't support BGs
	if not mapFile then return end

	local ourScale, ourAlpha = 12 * db.icon_scale_minimap, db.icon_alpha_minimap
	local pluginHandler = self.plugins[pluginName]
	local frameLevel = Minimap:GetFrameLevel() + 5
	local frameStrata = Minimap:GetFrameStrata()

	for coord, mapFile2, iconpath, scale, alpha in pluginHandler:GetNodes(mapFile, true, level) do
		local icon = getNewPin()
		icon:SetParent(Minimap)
		icon:SetFrameStrata(frameStrata)
		icon:SetFrameLevel(frameLevel)
		scale = ourScale * scale
		icon:SetHeight(scale) -- Can't use :SetScale as that changes our positioning scaling as well
		icon:SetWidth(scale)
		icon:SetAlpha(ourAlpha * alpha)
		local t = icon.texture
		if type(iconpath) == "table" then
			if iconpath.tCoordLeft then
				t:SetTexCoord(iconpath.tCoordLeft, iconpath.tCoordRight, iconpath.tCoordTop, iconpath.tCoordBottom)
			else
				t:SetTexCoord(0, 1, 0, 1)
			end
			if iconpath.r then
				t:SetVertexColor(iconpath.r, iconpath.g, iconpath.b, iconpath.a)
			else
				t:SetVertexColor(1, 1, 1, 1)
			end
			t:SetTexture(iconpath.icon)
		else
			t:SetTexCoord(0, 1, 0, 1)
			t:SetVertexColor(1, 1, 1, 1)
			t:SetTexture(iconpath)
		end
		icon:SetScript("OnClick", nil)
		icon:SetScript("OnEnter", pinsHandler.OnEnter)
		icon:SetScript("OnLeave", pinsHandler.OnLeave)
		local C, Z
		if mapFile2 then
			C, Z = self:GetCZ(mapFile2)
		else
			C, Z = continent, zone
		end
		local x, y = floor(coord / 10000) / 10000, (coord % 10000) / 10000
		Astrolabe:PlaceIconOnMinimap(icon, C, Z, x, y)
		t:ClearAllPoints()
		t:SetAllPoints(icon) -- Not sure why this is necessary, but people are reporting weirdly sized textures
		minimapPins[pluginName][(C or 0)*1e10 + (Z or 0)*1e8 + coord] = icon
		icon.pluginName = pluginName
		icon.coord = coord
		icon.mapFile = mapFile2 or mapFile
	end
end

-- This function updates all the icons on the minimap for every plugin
function HandyNotes:UpdateMinimap()
	--if not Minimap:IsVisible() then return end
	for pluginName, pluginHandler in pairs(self.plugins) do
		safecall(self.UpdateMinimapPlugin, self, pluginName)
	end
end

-- This function runs when we receive a "HandyNotes_NotifyUpdate"
-- notification from a plugin that its icons needs to be updated
-- Syntax is plugin:SendMessage("HandyNotes_NotifyUpdate", "pluginName")
function HandyNotes:UpdatePluginMap(message, pluginName)
	if self.plugins[pluginName] then
		self:UpdateWorldMapPlugin(pluginName)
		self:UpdateMinimapPlugin(pluginName)
	end
end

-- This function is called by Astrolabe whenever a note changes its OnEdge status
function HandyNotes.AstrolabeEdgeCallback()
	for pluginName, pluginHandler in pairs(HandyNotes.plugins) do
		for coordID, icon in pairs(minimapPins[pluginName]) do
			if Astrolabe.IconsOnEdge[icon] then
				icon:Hide()
			else
				icon:Show()
			end
		end
	end
end

-- OnUpdate frame we use to update the minimap icons
local updateFrame = CreateFrame("Frame")
updateFrame:Hide()
do
	local zone
	updateFrame:SetScript("OnUpdate", function()
		if zone ~= GetRealZoneText() then
			zone = GetRealZoneText()
			HandyNotes:UpdateMinimap()
		end
	end)
end


---------------------------------------------------------
-- Our options table

options = {
	type = "group",
	name = L["HandyNotes"],
	desc = L["HandyNotes"],
	args = {
		enabled = {
			type = "toggle",
			name = L["Enable HandyNotes"],
			desc = L["Enable or disable HandyNotes"],
			order = 1,
			get = function(info) return db.enabled end,
			set = function(info, v)
				db.enabled = v
				if v then HandyNotes:Enable() else HandyNotes:Disable() end
			end,
			disabled = false,
		},
		overall_settings = {
			type = "group",
			name = L["Overall settings"],
			desc = L["Overall settings that affect every database"],
			order = 10,
			get = function(info) return db[info.arg] end,
			set = function(info, v)
				local arg = info.arg
				db[arg] = v
				if arg == "icon_scale" or arg == "icon_alpha" then
					HandyNotes:UpdateWorldMap()
				else
					HandyNotes:UpdateMinimap()
				end
			end,
			disabled = function() return not db.enabled end,
			args = {
				desc = {
					name = L["These settings control the look and feel of HandyNotes globally. The icon's scale and alpha here are multiplied with the plugin's scale and alpha."],
					type = "description",
					order = 0,
				},
				icon_scale = {
					type = "range",
					name = L["World Map Icon Scale"],
					desc = L["The overall scale of the icons on the World Map"],
					min = 0.25, max = 2, step = 0.01,
					arg = "icon_scale",
					order = 10,
				},
				icon_alpha = {
					type = "range",
					name = L["World Map Icon Alpha"],
					desc = L["The overall alpha transparency of the icons on the World Map"],
					min = 0, max = 1, step = 0.01,
					arg = "icon_alpha",
					order = 20,
				},
				icon_scale_minimap = {
					type = "range",
					name = L["Minimap Icon Scale"],
					desc = L["The overall scale of the icons on the Minimap"],
					min = 0.25, max = 2, step = 0.01,
					arg = "icon_scale_minimap",
					order = 30,
				},
				icon_alpha_minimap = {
					type = "range",
					name = L["Minimap Icon Alpha"],
					desc = L["The overall alpha transparency of the icons on the Minimap"],
					min = 0, max = 1, step = 0.01,
					arg = "icon_alpha_minimap",
					order = 40,
				},
			},
		},
		plugins = {
			type = "group",
			name = L["Plugins"],
			desc = L["Plugin databases"],
			order = 20,
			args = {
				desc = {
					name = L["Configuration for each individual plugin database."],
					type = "description",
					order = 0,
				},
				show_plugins = {
					name = L["Show the following plugins on the map"], type = "multiselect",
					order = 20,
					values = pluginsOptionsText,
					get = function(info, k)
						return db.enabledPlugins[k]
					end,
					set = function(info, k, v)
						db.enabledPlugins[k] = v
						HandyNotes:UpdatePluginMap(nil, k)
					end,
				},
			},
		},
	},
}
options.args.plugins.disabled = options.args.overall_settings.disabled


---------------------------------------------------------
-- Addon initialization, enabling and disabling

function HandyNotes:OnInitialize()
	-- Set up our database
	self.db = LibStub("AceDB-3.0"):New("HandyNotesDB", defaults)
	self.db.RegisterCallback(self, "OnProfileChanged", "OnProfileChanged")
	self.db.RegisterCallback(self, "OnProfileCopied", "OnProfileChanged")
	self.db.RegisterCallback(self, "OnProfileReset", "OnProfileChanged")
	db = self.db.profile

	-- Register options table and slash command
	LibStub("AceConfigRegistry-3.0"):RegisterOptionsTable("HandyNotes", options)
	self:RegisterChatCommand("handynotes", function() LibStub("AceConfigDialog-3.0"):Open("HandyNotes") end)
	LibStub("AceConfigDialog-3.0"):AddToBlizOptions("HandyNotes", "HandyNotes")

	-- Get the option table for profiles
	options.args.profiles = LibStub("AceDBOptions-3.0"):GetOptionsTable(self.db)
	options.args.profiles.disabled = options.args.overall_settings.disabled
end

function HandyNotes:OnEnable()
	if not db.enabled then
		self:Disable()
		return
	end
	self:RegisterEvent("WORLD_MAP_UPDATE", "UpdateWorldMap")
	self:RegisterMessage("HandyNotes_NotifyUpdate", "UpdatePluginMap")
	Astrolabe:Register_OnEdgeChanged_Callback(self.AstrolabeEdgeCallback, true)
	updateFrame:Show()
	self:UpdateMinimap()
	self:UpdateWorldMap()
end

function HandyNotes:OnDisable()
	-- Remove all the pins
	for pluginName, pluginHandler in pairs(self.plugins) do
		for coordID, icon in pairs(minimapPins[pluginName]) do
			Astrolabe:RemoveIconFromMinimap(icon)
		end
		clearAllPins(worldmapPins[pluginName])
		clearAllPins(minimapPins[pluginName])
	end
	Astrolabe:Register_OnEdgeChanged_Callback(self.AstrolabeEdgeCallback)
	updateFrame:Hide()
end

function HandyNotes:OnProfileChanged(event, database, newProfileKey)
	db = database.profile
	self:UpdateMinimap()
	self:UpdateWorldMap()
end


-- vim: ts=4 noexpandtab
