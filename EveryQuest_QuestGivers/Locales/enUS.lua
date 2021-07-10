local debug = false
--[===[@debug@
debug = true
--@end-debug@]===]

local L = LibStub("AceLocale-3.0"):NewLocale("EveryQuest", "enUS", true, debug)

L[": No longer in DB"] = true
L["Close"] = true
L["Create waypoint"] = true
L["Data Loading"] = true
L["DataLoadWarning"] = [=[|cffFF6D6DWarning:|r The following can make your game lag if you are in or looking at a zone with a lot of quests. Do not enable when using CPU profiling, highly likely your game will freeze.  |cffFF6D6DNot available while in combat.|r 

The EveryQuest database was not designed for systematic random lookups.]=]
L["Enable: "] = true
L["Enables Quest Names in tooltips and category filtering"] = true
L["Hide Quest Giver"] = true
L["Icon Alpha"] = true
L["Icon Scale"] = true
L["Icon Settings"] = true
L["Load Data from EveryQuest database"] = true
L["Query the EveryQuest database for quest names"] = true
L["Quest Givers"] = true
L["Show Quest Names in tooltip"] = true
L["The alpha transparency of the icons"] = true
L["The scale of the icons"] = true
L["These settings control the look and feel of the Quest Givers icons."] = true
L["Toggle Showing of Categories"] = true
L["Toggle the display of quests by quest giver based on faction availability."] = true

