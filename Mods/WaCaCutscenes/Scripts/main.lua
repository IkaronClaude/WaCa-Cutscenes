-- WaCa Cutscenes: cutscenes from plain text - a cast of cats set out in a premade shape at a place, then a timeline of
-- beats (walk in, look, pose, say, camera moves). Any mod plays one by name (the PlayCutscene event; Clan Life's scenes:
-- "Cutscene: <Name>"). Needs WaCa Core.
local VERSION = "0.1.0"
local WaCa = require("WaCa")

local modDir = debug.getinfo(1, "S").source:match("^@(.+)[/\\]Scripts[/\\]main%.lua$") or "."
local function log(fmt, ...) print(string.format("[WaCaCutscenes] " .. fmt .. "\n", ...)) end
log("%s loaded", VERSION)
if not WaCaNative_Command then
    log("WaCa Core is not installed (or off) - this mod needs it: no cutscenes")
    return
end

require("cutscenes").Init({ WaCa = WaCa, log = log, modDir = modDir })

WaCa.Ready()
