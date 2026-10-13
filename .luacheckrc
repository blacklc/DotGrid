-- luacheck configuration for DotGrid
-- Usage:  luacheck DotGrid/
-- The addon ships with no libraries, so only WoW client globals are declared here.

std = "lua51"
max_line_length = false

globals = {
    -- addon entry points / slash commands
    "SlashCmdList", "ADDON_LOADED", "PLAYER_LOGIN", "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED",
    "UNIT_PET",

    -- frames and regions
    "UIParent", "WorldFrame", "CreateFrame", "GetLocale", "GetTime",
    "SetClampedToScreen", "SetMovable", "SetResizable", "SetUserPlaced",

    -- units and auras
    "UnitExists", "UnitCanAttack", "UnitIsDead", "UnitIsDeadOrGhost", "UnitAffectingCombat",
    "UnitIsPlayer", "UnitIsUnit", "UnitName", "UnitGUID", "UnitThreatSituation",
    "UnitDistanceSquared", "CheckInteractDistance", "UnitAura", "UnitAuraSlots", "UnitAuraBySlot",
    "AuraUtil", "C_UnitAuras", "C_Spell", "C_NamePlate", "C_CVar", "C_AddOns", "C_Timer",
    "issecretvalue", "issecrettable",

    -- client resources and UI bits used by the settings window
    "ColorPickerFrame", "GameTooltip", "UIParent", "IsInInstance", "GetInstanceInfo",
    "InCombatLockdown", "GetCVar", "GetCVarBool", "GetScreenWidth", "GetScreenHeight",
    "UIFrameFadeIn", "UIFrameFadeOut", "BackdropTemplateMixin", "Mixin", "SOUNDKIT",
    "PlaySound", "wipe", "strsplit", "strjoin", "tinsert", "tremove", "floor", "ceil",
    "format", "gsub", "match", "find", "lower", "upper", "sub", "rep", "byte", "char",
    "pairs", "ipairs", "next", "select", "type", "tostring", "tonumber", "setmetatable",
    "getmetatable", "rawget", "rawset", "unpack", "pcall", "xpcall", "error", "assert",
    "print", "math", "string", "table", "os", "coroutine",
}

read_globals = { "LibStub" }

-- Nothing in this addon is allowed to touch the file system or the network.
files["DotGrid/*.lua"] = {
    ignore = { "212" },            -- unused argument (event handlers receive args they ignore)
}
