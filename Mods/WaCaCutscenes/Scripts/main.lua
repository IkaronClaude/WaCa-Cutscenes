-- WaCa Cutscenes: cutscenes from plain text - a cast of cats set out in a premade shape at a place, then a timeline of
-- beats (walk in, look, pose, say, camera moves). Any mod plays one by name (the PlayCutscene event; Clan Life's scenes:
-- "Cutscene: <Name>"). Needs WaCa Core.
local VERSION = "0.2.0"
local hasCore, WaCa = pcall(require, "WaCa")    -- (no WaCa Core: its library is missing too)

local modDir = debug.getinfo(1, "S").source:match("^@(.+)[/\\]Scripts[/\\]main%.lua$") or "."
local function log(fmt, ...) print(string.format("[WaCaCutscenes] " .. fmt .. "\n", ...)) end
log("%s loaded", VERSION)
if not (hasCore and WaCaNative_Command) then
    log("WaCa Core is not installed (or off) - this mod needs it: no cutscenes")
    return
end
if not WaCa.Needs("1.0.0", "WaCaCutscenes") then return end

require("cutscenes").Init({ WaCa = WaCa, log = log, modDir = modDir })

WaCa.Ready()
