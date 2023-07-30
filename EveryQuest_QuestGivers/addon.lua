---------------------------------------------------------
-- Addon declaration
local EveryQuest = LibStub("AceAddon-3.0"):GetAddon("EveryQuest")
local L = LibStub("AceLocale-3.0"):GetLocale("EveryQuest")
local Astrolabe = DongleStub("Astrolabe-0.4")
local MODNAME = "QuestGivers"
local QG = EveryQuest:NewModule(MODNAME, "AceEvent-3.0")
local db, dbpc
local options
local function getfaction(side)
	if UnitFactionGroup("player") == side then return true else return false end
end
local new, del
do
	local cache = setmetatable({},{__mode='k'})
	function new()
		local t = next(cache)
		if t then
			cache[t] = nil
			return t
		else
			return {}
		end
	end

	function del(t)
		for k in pairs(t) do
			t[k] = nil
		end
		cache[t] = true
		return nil
	end
end


---------------------------------------------------------
-- Our db upvalue and db defaults


local defaults = {
	profile = {
		icon_scale = 1.4,
		icon_alpha = 1.0,
		LoadData = true,
		QuestNames = true,
		FollowCharacterLevel = true,
		filters = {
			Alliance = getfaction("Alliance"),
			Level = true,
			Horde = getfaction("Horde"),
			SideBoth = true,
			SideNone = false,
			MinLevel = 1,
			MaxLevel = 80,
			
			Categories = {
				["*"] = true,
			},
		},
		ExtraOptions = {
			["QuestLevel"] = true,
			["ClassTag"] = true,
			["DungeonTag"]= true,
			["DifficultyColor"] = true
		},
		debug = false,
	},
}
function QG:Print(text)
    DEFAULT_CHAT_FRAME:AddMessage("|cff63FFA1HQG: |r" ..tostring(text))
end
function QG:Error(string)
	self:Print("|cffff0000"..string.."|r")
end
function QG:Debug(string)
	if db.debug then  
		self:Print(string)
	end
end

---------------------------------------------------------
-- Localize some globals
local next = next
local select = select
local string_find = string.find
local GameTooltip = GameTooltip
local WorldMapTooltip = WorldMapTooltip
local HandyNotes = HandyNotes


---------------------------------------------------------
-- Constants
local qinfopattern = "([^\031]*)\031([^\031]*)\031([^\031]*)\031([^\031]*)\031$"

local hover = nil

---------------------------------------------------------
-- Plugin Handlers to HandyNotes

local HTHandler = {}

local function hidePin(button, mapFile, coord)
	--local x, y = HandyNotes:getXY(coord)
	-- local npcid = strsplit("", EQG_Data[mapFile][coord])
	-- if not dbpc.npcs then
		-- dbpc.npcs = {}
	-- end
	-- dbpc.npcs[npcid] = true
	-- QG:SendMessage("HandyNotes_NotifyUpdate", "QuestGivers")
end
local function createWaypoint(button, mapFile, coord)
	local c, z = HandyNotes:GetCZ(mapFile)
	local x, y = HandyNotes:getXY(coord)
	local npcid,npcname,qcount = strsplit("", EQG_Data[mapFile][coord])
	if TomTom then
		TomTom:AddZWaypoint(c, z, x*100, y*100, npcname)
	elseif Cartographer_Waypoints then
		Cartographer_Waypoints:AddWaypoint(NotePoint:new(HandyNotes:GetCZToZone(c, z), x, y, npcname))
	end
end

local clickedNote, clickedNoteZone
local info = {}
local function generateMenu(button, level)
	if (not level) then return end
	for k in pairs(info) do info[k] = nil end
	if (level == 1) then
		-- Create the title of the menu
		info.isTitle      = 1
		info.text         = L["Quest Givers"]
		info.notCheckable = 1
		UIDropDownMenu_AddButton(info, level)

		if TomTom or Cartographer_Waypoints then
			-- Waypoint menu item
			info.disabled     = nil
			info.isTitle      = nil
			info.notCheckable = nil
			info.text = L["Create waypoint"]
			info.icon = nil
			info.func = createWaypoint
			info.arg1 = clickedNoteZone
			info.arg2 = clickedNote
			UIDropDownMenu_AddButton(info, level);
		end

		-- Delete menu item
		info.disabled     = nil
		info.isTitle      = nil
		info.notCheckable = nil
		info.text = L["Hide Quest Giver"]
		info.icon = nil
		info.func = hidePin
		info.arg1 = clickedNoteZone
		info.arg2 = clickedNote
		UIDropDownMenu_AddButton(info, level);

		-- Close menu item
		info.text         = L["Close"]
		info.icon         = nil
		info.isTitle      = nil
		info.disabled     = nil
		info.func         = function() CloseDropDownMenus() end
		info.arg1         = nil
		info.arg2         = nil
		info.notCheckable = 1
		UIDropDownMenu_AddButton(info, level);
	end
end
local HT_Dropdown = CreateFrame("Frame", "HandyNotes_QuestGiversDropdownMenu")
HT_Dropdown.displayMode = "MENU"
HT_Dropdown.initialize = generateMenu

function HTHandler:OnClick(button, down, mapFile, coord)
	if button == "RightButton" and not down then
		clickedNoteZone = mapFile
		clickedNote = coord
		ToggleDropDownMenu(1, nil, HT_Dropdown, self, 0, 0)
	end
end
local MinimapSize = {
	indoor = {
		[0] = 300, -- scale
		[1] = 240, -- 1.25
		[2] = 180, -- 5/3
		[3] = 120, -- 2.5
		[4] = 80,  -- 3.75
		[5] = 50,  -- 6
	},
	outdoor = {
		[0] = 466 + 2/3, -- scale
		[1] = 400,       -- 7/6
		[2] = 333 + 1/3, -- 1.4
		[3] = 266 + 2/6, -- 1.75
		[4] = 200,       -- 7/3
		[5] = 133 + 1/3, -- 3.5
	},
}

local function GetClassColor(className)
	local classColor = "FFFFFF"
	if className == "DEATHKNIGHT" then
		classColor = "C41F3B"
	elseif className == "DRUID" then
		classColor = "FF7D0A"
	elseif className == "HUNTER" then
		classColor = "ABD473"
	elseif className == "MAGE" then
		classColor = "69CCF0"
	elseif className == "PALADIN" then
		classColor = "F58CBA"
	elseif className == "PRIEST" then
		classColor = "FFFFFF"
	elseif className == "ROGUE" then
		classColor = "FFF569"
	elseif className == "SHAMAN" then
		classColor = "0070DE"
	elseif className == "WARLOCK" then
		classColor = "9482C9"
	elseif className == "WARRIOR" then
		classColor = "C79C6E"
	end

	return classColor
end

local function rgbToHex(r,g,b)
    return format("|cff%.2x%.2x%.2x", r*255,g*255,b*255)
end

local function AddQuestLevel(questData, formattedQuestName)
	local questLevel = ""
	--check if quest has required or recommended level and add it to the string
	if not questData.c then
		if questData.l then
			questLevel = "["..questData.l.."] "
		elseif not questData.l and questData.r then
			questLevel = "["..questData.r.."] "
		end
	elseif questData.c then
		questLevel = "["..questData.r.."] "
	end
	formattedQuestName = questLevel..formattedQuestName
	return formattedQuestName
end

local function SetQuestDifficultyColor(formattedQuestName, questData)
	-- set difficulty color for quest
	if not questData.c then
		local questDifficultyColor = nil;
		if questData.l then
		 	questDifficultyColor = GetQuestDifficultyColor(tonumber(questData.l))
		elseif not questData.l and questData.r then
			questDifficultyColor = GetQuestDifficultyColor(tonumber(questData.r))
		end
		local hexColor = rgbToHex(questDifficultyColor.r, questDifficultyColor.g, questDifficultyColor.b)
		formattedQuestName = string.format(tostring(hexColor).."%s|r", formattedQuestName)
	elseif questData.c then
		local questDifficultyColor = GetQuestDifficultyColor(tonumber(questData.r))
		local hexColor = rgbToHex(questDifficultyColor.r, questDifficultyColor.g, questDifficultyColor.b)
		formattedQuestName = string.format(tostring(hexColor).."%s|r", formattedQuestName)
	end
	return formattedQuestName
end

local function SetDungeonOrRaidQuest(formattedQuestName, questData)
	--check if Dungeon Quest or not and add it to the string
	if questData and questData.dn then
		formattedQuestName = string.format("|cff36BFD1%s|r","["..questData.dn.."] ")..formattedQuestName
	end

	--check if Raid Quest or not and add it to the string
	if questData and questData.rn then
		formattedQuestName = string.format("|cff0A8515%s|r","["..questData.rn.."] ")..formattedQuestName
	end
	return formattedQuestName
end

local function SetClassQuestText(formattedQuestName, questData)
	--check if class quest
	if questData and questData.c then
		--get class color
		local classColor = GetClassColor(questData.c)
		formattedQuestName = string.format("|cff"..classColor.."%s|r","[" .. "Class Quest" .. "] ")..formattedQuestName
	end
	return formattedQuestName
end

local function FormatQuestName(questData, uid)
	local formattedQuestName = ""
	if questData then
		formattedQuestName = questData.n
		if db.ExtraOptions.QuestLevel then
			formattedQuestName = AddQuestLevel(questData, formattedQuestName)
		end
		if db.ExtraOptions.DifficultyColor then
			formattedQuestName = SetQuestDifficultyColor(formattedQuestName, questData)
		end
		if db.ExtraOptions.ClassTag then
			formattedQuestName = SetClassQuestText(formattedQuestName, questData)
		end
		if db.ExtraOptions.DungeonTag then
			formattedQuestName = SetDungeonOrRaidQuest(formattedQuestName, questData)
		end
	elseif not questData then
		formattedQuestName = uid .. L[": No longer in DB"]
	end
	return formattedQuestName
end

function HTHandler:OnEnter(mapFile, coord)
	
	--self:SetVertexColor(1, 0, 0)
	self:SetBackdropColor(0.098,0.368,1,1)
	local tooltip = self:GetParent() == WorldMapButton and WorldMapTooltip or GameTooltip
	QG.tooltip = tooltip
	if ( self:GetCenter() > UIParent:GetCenter() ) then -- compare X coordinate
		tooltip:SetOwner(self, "ANCHOR_LEFT")
	else
		tooltip:SetOwner(self, "ANCHOR_RIGHT")
	end
	-- we need to find all the relating close npc's here
	local thres
	if self:GetParent() ~= WorldMapButton then
		local Minimap = Minimap
		local curZoom = Minimap:GetZoom();
		if ( GetCVar("minimapZoom") == GetCVar("minimapInsideZoom") ) then
			if ( curZoom < 2 ) then
				Minimap:SetZoom(curZoom + 1)
			else
				Minimap:SetZoom(curZoom - 1)
			end
		end
		if ( GetCVar("minimapZoom")+0 == Minimap:GetZoom() ) then
			thres  = sqrt(MinimapSize.outdoor[Minimap:GetZoom()]) -- in yards
			--QG:Debug("outdoor")
			--self.minimapOutside = true;
		else
			thres  = sqrt(MinimapSize.indoor[Minimap:GetZoom()]) -- in yards
			--QG:Debug("indoor")
			--self.minimapOutside = false;
		end
		Minimap:SetZoom(curZoom)
		
		--thres = 1.5 / 100 -- in yards
	else
		thres = 1.5 / 100 -- in yards
	end
	--QG:Debug("GetObjectType(self) - "..self:GetObjectType())
	local x, y = HandyNotes:getXY(coord)
	local displaynpcs = {[coord] = true}
	local continent, zone = GetCurrentMapContinent(), GetCurrentMapZone()
	if mapFile then
		for coords, value in pairs(EQG_Data[mapFile]) do
			local cx, cy = HandyNotes:getXY(coords)
			local dist, xDelta, yDelta
			if self:GetParent() ~= WorldMapButton then
				dist = Astrolabe:ComputeDistance(continent, zone, x, y, continent, zone, cx, cy)
			else
				xDelta = (cx - x)
				yDelta = (cy - y)
				if ( xDelta and yDelta ) then
					dist = sqrt(xDelta*xDelta + yDelta*yDelta)
				end
			end
			if dist <= thres then -- we should group this up!
				displaynpcs[coords] = true
			end
		end
	end
	-- Acquire a tooltip with 3 columns, respectively aligned to left, center and right
	-- local tooltip2 = LibQTip:Acquire("HQGTooltip", 1, "LEFT")
	-- QG.tooltip2 = tooltip2
	local hasNPCsShown = false
	local playerLevel = UnitLevel("player")
	local questData, zone
	local displayedNpcsNumber = 1;
	for i,v in pairs(displaynpcs) do
		
		local value = EQG_Data[mapFile][i]
		--local npcid,npcname,qcount,quests = value:match(qinfopattern)
		local npcid,npcname,qcount,quests = strsplit("", EQG_Data[mapFile][i])
		--local vType, vName, vGuild = strsplit("", EQG_Data[mapFile][coord])
		
		local quests2 = new()
		local showquest
		quests2 = { strsplit("", quests) }
		local displaynpc = true
		local hordeq, allianceq, bothq, noneq = 0,0,0,0
		local questNames = {}
		local questCounter = 1
		local showcount = tonumber(qcount)
		for _,uid in pairs(quests2) do
			side = 3
			showquest = false
			--if string.find(uid, "\\%") ~= nil then
				uid, side = strsplit("%", uid)
				side = tonumber(side)
				-- EveryQuest:Print("uid: " .. tostring(uid) .. " - side:"..tostring(side))
			--end
			
			local requiredLevel = 0;
			local suggestedLevel = 0;
			if db.LoadData and not InCombatLockdown() then
				_, questData, zone = EveryQuest:GetQuestData( tonumber(uid) )
				side = questData and questData.s or 0
				if questData and not questData.l and questData.r then
					requiredLevel = questData.r or 0
				elseif questData and questData.l then
					suggestedLevel = questData.l or 0
				end
			end
			
			if side == 1 then allianceq = allianceq + 1 end
			if side == 2 then hordeq = hordeq + 1 end
			if side == 3 then bothq = bothq + 1 end
			if side == 0 then noneq = noneq + 1 end
			if side == 1 and db.filters.Alliance then showquest = true end
			if side == 2 and db.filters.Horde then showquest = true end
			if side == 3 and db.filters.SideBoth then showquest = true end
			if side == 0 and db.filters.SideNone then showquest = true end
			if EveryQuest.dbpc.profile.ignored[tonumber(uid)] then showquest = false end
			if db.filters.Level then
				if (suggestedLevel > 0) then
					if (suggestedLevel < db.filters.MinLevel) or (suggestedLevel > db.filters.MaxLevel) then
						showquest = false;
					end
				elseif not (suggestedLevel > 0) and (requiredLevel > 0) then
						if (requiredLevel < db.filters.MinLevel) or (requiredLevel > db.filters.MaxLevel) then
							showquest = false;
						end
				end
			end
			if not questData then
				showquest = false
			end
			local status, dcount = EveryQuest:GetHistoryStatus(tonumber(uid))
			if db.LoadData and not InCombatLockdown() then

				-- print(tostring(zone))
				-- print(EveryQuest:GetCategory(zone) .. "Toggle")
				local togglevar = EveryQuest:GetCategory(zone)
				togglevar = tostring(togglevar) .. "Toggle"
				if ((status or -2) >= 0 and dcount == nil) then
					-- print("Didn't pass status")
					showcount = showcount - 1
				elseif not showquest or not db.filters.Categories[togglevar] or not db.filters.Categories[tostring(zone)] then
					-- print("Didn't pass filter")
					showcount = showcount - 1
				else
					if db.QuestNames then
						questNames[questCounter] = FormatQuestName(questData, uid)
						questCounter = questCounter + 1
					end
				end
			else
				
				if ((status or -2) >= 0 and dcount == nil) then
					showcount = showcount - 1
				elseif not showquest then
					showcount = showcount - 1
				end
			end
		end
		-- EveryQuest:Print("showcount: " .. tostring(showcount))
		del(quests2)
		if showcount > 0 then
			if(displayedNpcsNumber > 1) then
				tooltip:AddLine(" ", 1, 1, 1)
			end
			if db.LoadData and db.QuestNames and not InCombatLockdown() then
				tooltip:AddLine( string.format("|cffffffff%s|r", npcname), 1, 1, 0 )
				for _, str in pairs(questNames) do
				   tooltip:AddLine( " " .. tostring(str), 1, 1, 1 )
				end
			else
				tooltip:AddLine("|cffffffff"..npcname.."|r", 1, 1, 0)
				tooltip:AddLine("  " .. string.format("%d Quests Left", showcount), 1, 1, 1)
			end
			hasNPCsShown = true
		end
		displayedNpcsNumber = displayedNpcsNumber + 1;
	end
	if hasNPCsShown then
		-- Use smart anchoring code to anchor the tooltip to our frame
		-- tooltip2:SmartAnchorTo(self)

		-- Show it, et voilà !
		tooltip:Show()
	end
end

function HTHandler:OnLeave(mapFile, coord)
	self:SetBackdropColor(1,1,1,1)
	--self:SetVertexColor(0, 0, 0)
	--[[if self:GetParent() == WorldMapButton then
		WorldMapTooltip:Hide()
	else
		GameTooltip:Hide()
	end]]
	-- Release the tooltip
	-- LibQTip:Release(QG.tooltip2)
	-- self.tooltip2 = nil
	QG.tooltip:Hide()
end

do
	local currentmapfile
	local f = UnitFactionGroup("player")
	if f == "Alliance" then
		faction = 1
	else
		faction = 2
	end
	-- This is a custom iterator we use to iterate over every node in a given zone
	local function iter(t, prestate)
		local side
		if not t then return nil end
		local state, value = next(t, prestate)
		while state do
			if value then
				-- print(tostring(state))
				
				local npcid,npcname,qcount,quests = strsplit("", value)
				local questData, zone
				local quests2 = new()
				local showquest
				quests2 = { strsplit("", quests or "") }
				local displaynpc = true
				local icon = "Interface\\AddOns\\EveryQuest_QuestGivers\\Artwork\\Quest"
				local showcount = tonumber(qcount)
				for _,uid in pairs(quests2) do
					side = 3
					showquest = false
					--if string.find(uid, "\\%") ~= nil then
						uid, side = strsplit("%", uid)
						side = tonumber(side)
						--EveryQuest:Print("uid: " .. uid .. " - side:"..side)
					--end
					local requiredLevel = 0
					local suggestedLevel = 0

					if db.LoadData and not InCombatLockdown() then
						_, questData, zone = EveryQuest:GetQuestData( tonumber(uid) )
						side = questData and questData.s or (side ~= nil and side or 0)
						if questData and not questData.l and questData.r then
							requiredLevel = questData.r or 0
						elseif questData and questData.l then
							suggestedLevel = questData.l or 0
						end
					end
					
					if side == 1 and db.filters.Alliance then showquest = true end
					if side == 2 and db.filters.Horde then showquest = true end
					if side == 3 and db.filters.SideBoth then showquest = true end
					if (side == 0 or side == nil) and db.filters.SideNone then showquest = true end
					
					if EveryQuest.dbpc.profile.ignored[tonumber(uid)] then showquest = false end
					if db.filters.Level then
						if suggestedLevel and (suggestedLevel > 0) then
							if (suggestedLevel < db.filters.MinLevel) or (suggestedLevel > db.filters.MaxLevel) then
								showquest = false;
							end
						elseif not (suggestedLevel > 0) and (requiredLevel > 0) then
								if (requiredLevel < db.filters.MinLevel) or (requiredLevel > db.filters.MaxLevel) then
									showquest = false;
								end
						end
					end
					if not questData then
					showquest = false
					end
					
					local status, daily = EveryQuest:GetHistoryStatus(tonumber(uid))
					if daily ~= nil then
						icon = "Interface\\AddOns\\EveryQuest_QuestGivers\\Artwork\\DQuest"
					end
					-- if tonumber(npcid) == 20735 then
						-- EveryQuest:Print("npcid: " .. tostring(npcid) .. " - showquest: " .. tostring(showquest) .. " - uid: " .. tostring(uid) .. " - status: " .. tostring(status) .. " - daily:"..tostring(daily) .. " - side:"..tostring(side))
					-- end
					if db.LoadData and not InCombatLockdown() then
						-- print(tostring(zone))
						-- print(EveryQuest:GetCategory(zone) .. "Toggle")
						local togglevar = EveryQuest:GetCategory(zone)
						togglevar = tostring(togglevar) .. "Toggle"
						if ((status or -2) >= 0 and daily == nil) then
							-- print("Didn't pass status")
							showcount = showcount - 1
						elseif not showquest or not db.filters.Categories[togglevar] or not db.filters.Categories[tostring(zone)] then
							-- print("Didn't pass filter")
							showcount = showcount - 1
						end
					else
						if ((status or -2) >= 0 and daily == nil) then
							showcount = showcount - 1
						elseif not showquest then
							showcount = showcount - 1
						end
					end
				end
				del(quests2)
				-- if tonumber(npcid) == 20735 then
				-- EveryQuest:Print("npcid: " .. tostring(npcid) .. " - showcount: " .. tostring(showcount) .. " - qcount:"..tostring(qcount))
				-- end
				if showcount > 0 then
					-- local x2, y2 = HandyNotes:getXY(state)
					-- local c2, z2 = GetCurrentMapContinent(), GetCurrentMapZone()
					-- local dist = Astrolabe:ComputeDistance( Astrolabe:GetCurrentPlayerPosition(), c2, z2, x2, y2 )
					-- print(tostring(dist))
					--if (not db.char.npcs[npcid]) then
						return state, nil, icon, db.icon_scale, db.icon_alpha --, db.quest_level
					--end
				end
			end
			state, value = next(t, state)
		end
		return nil, nil, nil, nil
	end
	function HTHandler:GetNodes(mapFile)
		currentmapfile = mapFile
		return iter, EQG_Data[mapFile], nil
	end
end


---------------------------------------------------------
-- Options table
local function getOptions()
	if not options then
		options = {
			type = "group",
			name = L["Quest Givers"],
			desc = L["Quest Givers"],
			get = function(info) return db[ info[#info] ] end,
			set = function(info, value) db[ info[#info] ] = value QG:SendMessage("HandyNotes_NotifyUpdate", "QuestGivers") end,
			args = {
				LoadData = {
					type = "group",
					order = 0,
					guiInline = true,
					name = L["Data Loading"],
					args = {
						desc = {
							name = L["DataLoadWarning"],
							type = "description",
							order = 0,
						},
						LoadData = {
							order = 10,
							type = 'toggle',
							name = L["Load Data from EveryQuest database"],
							desc = L["Enables Quest Names in tooltips and category filtering"],
							width = "double",
						},
						QuestNames = {
							order = 20,
							type = 'toggle',
							name = L["Show Quest Names in tooltip"],
							desc = L["Query the EveryQuest database for quest names"],
							disabled = function() return not db.LoadData end,
							width = "double",
						},
					},
				},
				Faction = {
					type = "group",
					order = 20,
					guiInline = true,
					name = "Quests Filters",
					desc = "Show quests for specific faction",
					get = function(info) return db.filters[ info[#info] ] end,
					set = function(info, value) db.filters[ info[#info] ] = value QG:SendMessage("HandyNotes_NotifyUpdate", "QuestGivers") end,
					args = {
						desc = {
							name = "Toggle filters you want to apply to quests showing on map/minimap.",
							type = "description",
							order = 0,
						},
						Alliance = {
							type = 'toggle',
							name = L["Alliance"],
							desc = L["Shows Alliance Quests"],
						},
						Horde = {
							type = 'toggle',
							name = L["Horde"],
							desc = L["Shows Horde Quests"],
						},
						SideBoth = {
							type = 'toggle',
							name = L["Both Factions"],
							desc = L["Shows quests that are available to both factions"],
						},
						SideNone = {
							type = 'toggle',
							name = L["No Side/No Data"],
							desc = L["Shows quests that don't have a side or don't have data for a specific side"],
						},
						Level = {
							type = 'toggle',
							name = L["Level Filter"],
						},
					},
				},
				Category = {
					type = "group",
					order = 30,
					guiInline = true,
					name = L["Toggle Showing of Categories"],
					get = function(info) return db.filters.Categories[ info[#info] ] end,
					set = function(info, value) db.filters.Categories[ info[#info] ] = value QG:SendMessage("HandyNotes_NotifyUpdate", "QuestGivers") end,
					disabled = function() return not db.LoadData end,
					args = {
					
					}
				},
				Icon = {
					type = "group",
					order = 10,
					guiInline = true,
					name = L["Icon Settings"],
					args = {
						desc = {
							name = L["These settings control the look and feel of the Quest Givers icons."],
							type = "description",
							order = 20,
						},
						icon_scale = {
							type = "range",
							name = L["Icon Scale"],
							desc = L["The scale of the icons"],
							min = 0.25, max = 2, step = 0.01,
							arg = "icon_scale",
							order = 30,
						},
						icon_alpha = {
							type = "range",
							name = L["Icon Alpha"],
							desc = L["The alpha transparency of the icons"],
							min = 0, max = 1, step = 0.01,
							arg = "icon_alpha",
							order = 40,
						},
					},
				},
				QuestDetails = {
					type = "group",
					order = 30,
					guiInline = true,
					name = "Extra Options for Quest Names",
					get = function(info) return db.ExtraOptions[ info[#info] ] end,
					set = function(info, value) db.ExtraOptions[ info[#info] ] = value QG:SendMessage("HandyNotes_NotifyUpdate", "QuestGivers") end,
					args = {
						desc = {
							name = "Toggle extra options you want to apply to quests showing on map/minimap",
							type = "description",
							order = 0,
						},
						QuestLevel = {
							type = 'toggle',
							name = "Show Quest Level",
							desc = "Shows quest level near the name of the quest",
						},
						DifficultyColor = {
							type = 'toggle',
							name = "Difficulty Color",
							desc = "Colors the name of the text by difficulty, accordingly to your current level",
						},
						ClassTag = {
							type = 'toggle',
							name = "Class Tag",
							desc = "Shows class tag near the name of the quest for class quests\n"..string.format("|cff"..GetClassColor(string.upper(UnitClass("player"))).."%s|r","[" .. "Class Quest" .. "]").." Name of Quest",
						},
						DungeonTag = {
							type = 'toggle',
							name = "Dungeon/Raid Tag",
							desc = "Shows dungeon/raid tag near the name of the quest for dungeon/raid quests\n"..string.format("|cff36BFD1%s|r","[Ragefire Chasm]").." Name of Quest",
						},
					},
				},
				Level = {
					type = "group",
					order = 30,
					guiInline = true,
					disabled = function() return not db.filters.Level end,
					name = L["Filter Quests by Level"],
					args = {
						FollowCharacterLevel = {
							order = 1,
							type = "toggle",
							name = L["Follow Character Level"],
							desc = L["Automatically adjusts the Minimum Level and Maximum Level filters to only show quests applicable to your level. Useful for leveling."],
							width = "double"
						},
						MinLevel = {
							order = 2,
							type = "range",
							name = L["Minimum Level"],
							get = function(info) return db.filters[ info[#info] ] end,
							set = function(info, value) db.filters[ info[#info] ] = value QG:SendMessage("HandyNotes_NotifyUpdate", "QuestGivers") end,
							min = 1,
							max = 80,
							step = 1,
							width = "double"
						},
						MaxLevel = {
							order = 3,
							type = "range",
							name = L["Maximum Level"],
							get = function(info) return db.filters[ info[#info] ] end,
							set = function(info, value) db.filters[ info[#info] ] = value QG:SendMessage("HandyNotes_NotifyUpdate", "QuestGivers") end,
							min = 1,
							max = 80,
							step = 1,
							width = "double"
						},
					},
				},
			},
		}
	end
	local order = 0
	local EQ_zones = EQ_zones
	local thearg = options.args.Category.args
	for _,v in pairs(EQ_zones) do
		thearg[v[1].."Toggle"] = {
			type = 'toggle',
			order = order,
			width = "double",
			name = L["Enable: "] .. v[3],
		}
		order = order +1
		if type(v[2]) == "table" then
			thearg[v[1]] = {
				type = "group",
				order = order,
				guiInline = true,
				disabled = function() return not db.filters.Categories[v[1].."Toggle"] or not db.LoadData end,
				name = v[3] or v[1],
				args = {
				
				},
			}
			order = order +1
			for _,cat in pairs(v[2]) do
				order = order +1
				if type(cat[2]) == "table" then
					thearg[v[1]].args[cat[1].."Toggle"] = {
						type = 'toggle',
						order = order,
						width = "double",
						name = L["Enable: "] .. cat[3],
					}
					order = order +1
					thearg[v[1]].args[cat[1]] = {
						type = "group",
						order = order,
						guiInline = true,
						disabled = function() return not db.filters.Categories[cat[1].."Toggle"] or not db.LoadData end,
						name = cat[3] or cat[1],
						args = {
						
						},
					}
					for _,dungeon in pairs(cat[2]) do
						order = order +1
						thearg[v[1]].args[cat[1]].args[tostring(dungeon[1])] = {
							type = 'toggle',
							order = order,
							name = dungeon[2],
						}
					end
				else
					thearg[v[1]].args[tostring(cat[1])] = {
						type = 'toggle',
						order = order,
						-- disabled = not db.filters.Categories[v[1].."Toggle"],
						name = cat[2],
					}
				end
			end
		end
	end
	-- Spew("thearg", thearg)

	return options
end

---------------------------------------------------------
-- Addon initialization, enabling and disabling

function QG:OnInitialize()
	-- Set up our database
	self.db = EveryQuest.dbpc:RegisterNamespace("QuestGivers", defaults)
	-- dbpc = EveryQuest.dbpc.profile
	EveryQuest:RegisterModuleOptions(MODNAME, getOptions, L["Quest Givers"])
	db = self.db.profile

	-- Initialize our database with HandyNotes
	HandyNotes:RegisterPluginDB("QuestGivers", HTHandler, options)
end

function AdjustClassFilters()
	db.filters.Categories["-372"] = false
	db.filters.Categories["-263"] = false
	db.filters.Categories["-261"] = false
	db.filters.Categories["-161"] = false
	db.filters.Categories["-141"] = false
	db.filters.Categories["-262"] = false
	db.filters.Categories["-162"] = false
	db.filters.Categories["-82"] = false
	db.filters.Categories["-61"] = false
	db.filters.Categories["-81"] = false
	
	local playerClass = UnitClass("player")
	
	if playerClass == "DeathKnight" then
		db.filters.Categories["-372"] = true
	elseif playerClass == "Druid" then
		db.filters.Categories["-263"] = true
	elseif playerClass == "Hunter" then
		db.filters.Categories["-261"] = true
	elseif playerClass == "Mage" then
		db.filters.Categories["-161"] = true
	elseif playerClass == "Paladin" then
		db.filters.Categories["-141"] = true
	elseif playerClass == "Priest" then
		db.filters.Categories["-262"] = true
	elseif playerClass == "Rogue" then
		db.filters.Categories["-162"] = true
	elseif playerClass == "Shaman" then
		db.filters.Categories["-82"] = true
	elseif playerClass == "Warlock" then
		db.filters.Categories["-61"] = true
	elseif playerClass == "Warrior" then
		db.filters.Categories["-81"] = true
	end
end

function AdjustLevelFilters()
	if db.FollowCharacterLevel then
		local playerLevel = UnitLevel("player")
		if playerLevel < 7 then
			db.filters.MinLevel = 1
			db.filters.MaxLevel = playerLevel + 3
		elseif playerLevel > 76 then
			db.filters.MinLevel = playerLevel - 5
			db.filters.MaxLevel = 80
		else 
			db.filters.MinLevel = playerLevel - 5
			db.filters.MaxLevel = playerLevel + 3
		end
	end
end

function AdjustTradeSkillFilters()
	db.filters.Categories["-181"] = false
	db.filters.Categories["-121"] = false
	db.filters.Categories["-304"] = false
	db.filters.Categories["-201"] = false
	db.filters.Categories["-324"] = false
	db.filters.Categories["-101"] = false
	db.filters.Categories["-24"] = false
	db.filters.Categories["-371"] = false
	db.filters.Categories["-373"] = false
	db.filters.Categories["-182"] = false
	db.filters.Categories["-264"] = false
	
	local professions = {}
	for i = 1, GetNumSkillLines() do
		local skillName, _, _, _ = GetSkillLineInfo(i)
		if skillName then
			table.insert(professions, {name = skillName})
		end
    end
	
	for _, profession in ipairs(professions) do
		if profession.name == "Alchemy" then
			db.filters.Categories["-181"] = true
		elseif profession.name == "Blacksmithing" then
			db.filters.Categories["-121"] = true
		elseif profession.name == "Cooking" then
			db.filters.Categories["-304"] = true
		elseif profession.name == "Engineering" then
			db.filters.Categories["-201"] = true
		elseif profession.name == "First Aid" then
			db.filters.Categories["-324"] = true
		elseif profession.name == "Fishing" then
			db.filters.Categories["-101"] = true
		elseif profession.name == "Herbalism" then
			db.filters.Categories["-24"] = true
		elseif profession.name == "Inscription" then
			db.filters.Categories["-371"] = true
		elseif profession.name == "Jewelcrafting" then
			db.filters.Categories["-373"] = true
		elseif profession.name == "Leatherworking" then
			db.filters.Categories["-182"] = true
		elseif profession.name == "Tailoring" then
			db.filters.Categories["-264"] = true
		end
	end
end

local adjustFilterFrame = CreateFrame("FRAME")
adjustFilterFrame:RegisterEvent("PLAYER_LEVEL_UP")
adjustFilterFrame:RegisterEvent("PLAYER_LOGIN")
adjustFilterFrame:SetScript("OnEvent", function(self, event, ...)
	if event == "PLAYER_LEVEL_UP" then
		AdjustLevelFilters()
	elseif event == "PLAYER_LOGIN" then
		AdjustClassFilters()
		AdjustLevelFilters()
		AdjustTradeSkillFilters()
	end
end)

function QG:OnEnable()
	--self:RegisterEvent("TRAINER_SHOW")
end
