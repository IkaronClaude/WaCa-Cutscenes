-- CUTSCENES FROM TEXT (tickets: "what a writer would need to truly build their own story"). A cutscene is a section
-- of config/cutscenes.ini - or of any enabled mod's content/cutscenes.ini:
--   [Cutscene.RogueStandoff]
--   Place = Here                 where it plays: Here (in front of your cat), Pile (the fresh-kill pile), a place
--                                from places.ini, one of the game's zones (Zone:I- the Island, Zone:R-05 a camp),
--                                or "X Y Z [yaw]"
--   Shape = Facing               how the cats stand: a shape from shapes.ini (Facing, Circle, Line, Pair, Meeting,
--                                Ceremony ...) - its groups of marks, and which way each group looks
--   A = Player, Deputy           who stands on a group's marks, in order (A1 = your cat, A2 = the deputy): see cast.lua
--   B = Nearest, Nearest, Nearest
--   Beat1 = 0 WalkIn: B          the timeline: <seconds from the start> <action>[: <who> [= <what>]]
--   Beat2 = 2 Camera: Wide ~1.5
--   Beat3 = 4 Say: B1 = You're on our land now.
--   Beat4 = 6 Pose: A2 = Growl
--   Beat5 = 8 Camera: Portrait = A1
--   Beat6 = 12 End
-- Or one of the GAME'S OWN scenes, its cats dressed as yours (scenes.lua): Scene = RankUp, Leader = <who>, ...
-- Who: a mark (A1, B2), a group (B), All, Player. Actions:
--   WalkIn: <who>                the cats walk onto their marks (they start a few metres out - WalkFrom)
--   Walk: <who> = <who>          walk up to another cat (or Middle), facing it
--   Place: <who>                 onto their marks at once
--   Look: <who> = <who>          turn to a cat (or Middle, Camera)
--   Pose: <who> = <pose>         Sit, Lie, Sleep, Eat, Sniff, Meow, Play, Dig, Groom, Win, Hit, Hiss, Growl, TailUp, Stalk, Pounce,
--                                Stop - or a montage's path
--   Say: <who> = <line>          the line on screen with the cat's name ({PLAYER}, {P2} ... = names in the line)
--   Card: <text>                 a line on screen without a name
--   Camera: <shot> [= <who> ...] [~<seconds>]   see camera.lua
--   Fade: <seconds> / FadeIn: <seconds>
--   Emit: <event>                another mod's code runs here (WaCa.Emit)
--   Wait: <who> / <seconds>      the timeline holds till those cats are on their marks (WaitMax), or a pause
--   Ask: <var> = <question>; <answer 1>; <answer 2> ...   the player answers (WaCa Clan Life's Choice: the game's answer menu; "A1: ..." = A1 speaks it, {B1} names filled);
--                                the timeline holds till then (AskMax s at most); the story variable gets the number
--   [<var> = <value>] before an action: that beat plays only if it holds ("Beat7 = 10 [Shelter = 1] Say: A2 = ...";
--                                = != < > <= >=, several joined by ","). The variables: those set while Cutscenes
--                                runs (an Ask, a Set: beat, any story step), and a scene's own Set: beats.
--   End                          the cutscene is over (else 2 s after the last beat)
-- While one plays: your keys and the HUD are off, the cast's cats are held; at the end the cats go back where they
-- were, the game's camera comes back. Events for other mods: PlayCutscene(name) plays one (queued if one is on);
-- CutsceneStarted(name), CutsceneEnded(name, why).
local Cutscenes = {}

local WaCa, log, modDir
local Cast, Stage, Camera, Scenes
local CARD = "/Game/Art/UXD/Blueprints/Popups/WBP_GuiPopupCenterMessage.WBP_GuiPopupCenterMessage_C"
local storyVars = {}                -- story variables seen (WaCa Clan Life's StoryVar event) - beat guards read them
local cfg = { askMax = 300, on = true, ahead = 250, walkFrom = 600, fade = 0.6, maxSeconds = 180, endAfter = 2, hideHud = true, waitMax = 20,
              enclosedAt = 150,
              putPlayerBack = false, sayBase = 2, sayPerChar = 0.07, lineOffset = 380, farAway = 8000, farWait = 4 }
local defs, shapes, places = {}, {}, {}
local keepRunning, clearRunning        -- (a reload in mid-scene - below)
local subtitle                      -- the cutscene's subtitle widget (its object path)
local cards = {}                    -- Card: widgets up now: { path, till (cutscene seconds) }
local ACTIONS = {}                     -- (the beats' actions - below; the check reads it too)
local farFrom = {}                  -- a cutscene waiting for its far place to load -> where your cat was
local playing                       -- the cutscene on now
local queue = {}
local hud                           -- the game's HUD screen (its object path)

local function v(x, y, z) return { X = x, Y = y, Z = z } end
local function trim(s) return (tostring(s or ""):gsub("^%s+", ""):gsub("%s+$", "")) end
local function split(s, sep)
    local out = {}
    for raw in tostring(s or ""):gmatch("[^" .. sep .. "]+") do
        local part = trim(raw)
        if part ~= "" then out[#out + 1] = part end
    end
    return out
end

-- --- reading the files ---

-- a shape: [Shape.<Name>] <Group><n> = <forward> <side> (cm from the place's middle - forward away from the camera,
-- side to the right), Face<Group or mark> = Middle | Camera | Forward | <group> | <mark>
local function readShapes()
    local ini = WaCa.ReadContent(modDir .. "/config/shapes.ini", "shapes") or {}
    shapes = {}
    for section, sec in pairs(ini) do
        local name = type(sec) == "table" and section:match("^Shape%.(.+)$")
        if name and sec.Off ~= "1" then
            local s = { marks = {}, groups = {}, order = {}, face = {} }
            for _, k in ipairs(sec.__order or {}) do
                local group, n = k:match("^(%u)(%d+)$")
                if group then
                    local f, side = tostring(sec[k]):match("^%s*([%-%d%.]+)[%s,]+([%-%d%.]+)")
                    if f then
                        s.marks[k] = { fwd = tonumber(f), side = tonumber(side), group = group, n = tonumber(n) }
                        if not s.groups[group] then s.groups[group] = {} s.order[#s.order + 1] = group end
                        table.insert(s.groups[group], k)
                    end
                end
                local target = k:match("^Face(.+)$")
                if target then s.face[target] = trim(sec[k]) end
            end
            for _, list in pairs(s.groups) do
                table.sort(list, function(a, b) return s.marks[a].n < s.marks[b].n end)
            end
            shapes[name] = s
        end
    end
end

local function readPlaces()
    local ini = WaCa.ReadContent(modDir .. "/config/places.ini", "places") or {}
    places = {}
    for section, sec in pairs(ini) do
        local name = type(sec) == "table" and section:match("^Place%.(.+)$")
        if name and sec.Off ~= "1" then
            local x, y, z = tostring(sec.At or ""):match("([%-%d%.]+)[%s,]+([%-%d%.]+)[%s,]+([%-%d%.]+)")
            if x then places[name] = { at = v(tonumber(x), tonumber(y), tonumber(z)), yaw = tonumber(sec.Yaw or "") } end
        end
    end
end

-- a beat: "<seconds> [<guard>] <Action>[: <who> [= <what>]]"
local function parseBeat(text)
    local guard
    local t0, g, after = tostring(text):match("^%s*([%d%.]+)%s+%[(.-)%]%s*(.*)$")
    if t0 then text, guard = t0 .. " " .. after, trim(g) end
    local t, action, rest = tostring(text):match("^%s*([%d%.]+)%s+(%a+)%s*:?%s*(.-)%s*$")
    if not t then return nil end
    local blend
    local body, b = rest:match("^(.-)%s*~%s*([%d%.]+)$")
    if body then rest, blend = body, tonumber(b) end
    local who, what = rest:match("^(.-)%s*=%s*(.-)$")
    if not who then who, what = rest, nil end
    return { t = tonumber(t), action = action, who = trim(who), what = what and trim(what) or nil, blend = blend,
             guard = guard }
end

-- a beat's guard: "Var op value, ..." against the story variables seen - all must hold (a variable never seen = nil)
local OPS = {
    ["="] = function(a, b) return a == b end, ["!="] = function(a, b) return a ~= b end,
    ["<"] = function(a, b) return a ~= nil and a < b end, ["<="] = function(a, b) return a ~= nil and a <= b end,
    [">"] = function(a, b) return a ~= nil and a > b end, [">="] = function(a, b) return a ~= nil and a >= b end,
}
local function guardHolds(text)
    for cond in tostring(text or ""):gmatch("[^,]+") do
        local name, op, value = cond:match("^%s*([%w%.%_]+)%s*([<>=!]+)%s*(.-)%s*$")
        if not (name and OPS[op]) then return false end
        local have, want = storyVars[name], tonumber(value) or value
        if type(have) ~= type(want) and (op ~= "=" and op ~= "!=") then return false end
        local ok, r = pcall(OPS[op], have, want)
        if not (ok and r) then return false end
    end
    return true
end

local function readCutscenes()
    local ini = WaCa.ReadContent(modDir .. "/config/cutscenes.ini", "cutscenes") or {}
    local s = ini["Cutscenes"] or {}
    cfg.on = (s.On or "1") ~= "0"
    cfg.ahead = tonumber(s.Ahead or "") or cfg.ahead
    cfg.walkFrom = tonumber(s.WalkFrom or "") or cfg.walkFrom
    cfg.walkSpeed = tonumber(s.WalkSpeed or "")
    cfg.maxSeconds = tonumber(s.MaxSeconds or "") or cfg.maxSeconds
    cfg.waitMax = tonumber(s.WaitMax or "") or cfg.waitMax
    cfg.askMax = tonumber(s.AskMax or "") or cfg.askMax
    cfg.enclosedAt = tonumber(s.EnclosedAt or "") or cfg.enclosedAt
    cfg.hideHud = (s.HideHud or "1") ~= "0"
    cfg.lineOffset = tonumber(s.LineOffset or "") or cfg.lineOffset
    cfg.putPlayerBack = (s.PutPlayerBack or "0") == "1"
    cfg.whereKey, cfg.previewKey, cfg.preview = trim(s.WhereKey), trim(s.PreviewKey), trim(s.Preview)
    cfg.skipKey = s.SkipKey ~= nil and trim(s.SkipKey) or "SpaceBar"
    if cfg.skipKey ~= "" then cfg.skipKey = WaCa.ModKey("Cutscenes", "Skip", cfg.skipKey, "skip a cutscene") end
    defs = {}
    -- A PACK'S OWN BROUGHT-IN CAT ([Rogue.<Name>]): From = the cat whose look it starts from, then any of the game's
    -- own look fields (FurColorIdx, Pattern01ColorIdx, BodyValue, EyeValue ...) - Rogue:<Name> in a cast is then
    -- always that cat (library exercise 2026-11-01: a brought-in cat's coat couldn't be the writer's)
    local rogues = {}
    for section, sec in pairs(ini) do
        local name = type(sec) == "table" and section:match("^Rogue%.(.+)$")
        if name then
            local r = { from = sec.From and trim(sec.From) or nil, fields = {} }
            for _, k in ipairs(sec.__order or {}) do
                if k ~= "From" and k ~= "Off" then r.fields[#r.fields + 1] = { k, trim(sec[k]) } end
            end
            rogues[name] = r
        end
    end
    if Cast.SetRogues then Cast.SetRogues(rogues) end
    for section, sec in pairs(ini) do
        local name = type(sec) == "table" and section:match("^Cutscene%.(.+)$")
        if name and sec.Off ~= "1" then
            local d = { name = name, place = trim(sec.Place or "Here"), shape = trim(sec.Shape or "Facing"), groups = {},
                        beats = {}, mods = sec.__mods }
            -- (one of the game's own scenes, re-cast: Scene = RankUp, and its parts - every other key - see scenes.lua)
            if trim(sec.Scene) ~= "" then
                d.scene, d.roles = trim(sec.Scene), {}
                for _, k in ipairs(sec.__order or {}) do
                    if k ~= "Scene" and k ~= "Off" and trim(sec[k]) ~= "" then d.roles[k] = trim(sec[k]) end
                end
            end
            -- (Beat<number>, or Beat<number><letters> to slot one in between without renumbering - Beat2a comes
            -- after Beat2 at the same time; any other key is reported by the check - it was dropped without a word,
            -- library pre-work 2026-11-03)
            d.unknown = {}
            for _, k in ipairs(sec.__order or {}) do
                if k:match("^%u$") then d.groups[k] = split(sec[k], ",") end
                local n, sub = k:match("^Beat(%d+)(%a*)$")
                if n then
                    local b = parseBeat(sec[k])
                    if b then
                        b.key = k
                        b.n = tonumber(n) + (sub ~= "" and (sub:lower():byte(1) - 96) / 100 or 0)
                        d.beats[#d.beats + 1] = b
                    else
                        log("%s: can't read %s = %s", name, k, tostring(sec[k]))
                    end
                elseif not d.scene and not k:match("^%u$") and k ~= "Place" and k ~= "Shape" and k ~= "Scene" and k ~= "Off" then
                    d.unknown[#d.unknown + 1] = k
                end
            end
            table.sort(d.beats, function(a, b) if a.t ~= b.t then return a.t < b.t end return a.n < b.n end)
            defs[name] = d
        end
    end
    return ini["Camera"] or {}
end

-- CHECKED WHEN READ (library exercise 2026-11-02: a cutscene with Place = ReedBnak, Shape = Vigl, A = Leadr and
-- Camra: Wide loaded without a word - in play the place fell back to "here", the beat did nothing): every cutscene's
-- place, shape, cast and beats are checked against what exists; each problem logged ("cutscene check: ..."), a count
-- on screen. A cast name that isn't a part may be a cat's own name - only one a letter or two off a part is flagged.
local SHOTS = { Wide = true, High = true, Orbit = true, Portrait = true, Over = true, Two = true, Behind = true, Game = true }
local CASTPARTS = { "Player", "Leader", "Deputy", "MedicineCat", "Queen", "Kit", "Elder", "Apprentice", "Warrior",
                    "Mentor", "Nearest", "Rogue" }
local function near(a, b)              -- (edit distance <= 2, short words: a typo)
    a, b = a:lower(), b:lower()
    if math.abs(#a - #b) > 2 then return false end
    local prev = {}
    for j = 0, #b do prev[j] = j end
    for i = 1, #a do
        local cur = { [0] = i }
        for j = 1, #b do
            cur[j] = math.min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + ((a:sub(i, i) == b:sub(j, j)) and 0 or 1))
        end
        prev = cur
    end
    return prev[#b] <= 2
end
function Cutscenes.Check()
    local problems = {}
    local function problem(d, fmt, ...) problems[#problems + 1] = d.name .. ": " .. string.format(fmt, ...) end
    for _, d in pairs(defs) do
        if not d.scene then
            local pl = d.place
            if not (pl == "Here" or pl == "Pile" or pl:match("^Zone:") or places[pl] or pl:match("^[%-%d%.]+[%s,]+[%-%d%.]+[%s,]+[%-%d%.]+")) then
                problem(d, "no place '%s' (Here, Pile, Zone:<code>, X Y Z, or a places.ini [Place.<Name>])", pl)
            end
            if not shapes[d.shape] then problem(d, "no shape '%s'", d.shape) end
            for g, list in pairs(d.groups) do
                for i, spec in ipairs(list) do
                    local isPart = false
                    for _, p in ipairs(CASTPARTS) do if spec == p then isPart = true end end
                    if not isPart and not spec:match("^[ESR]%a*:") and not spec:match("^Clan:") then
                        for _, p in ipairs(CASTPARTS) do
                            if near(spec, p) then problem(d, "%s%d = %s - did you mean %s?", g, i, spec, p) break end
                        end
                    end
                end
            end
            for _, b in ipairs(d.beats) do
                if not ACTIONS[b.action] then
                    problem(d, "%s: no action '%s'", b.key or ("Beat" .. b.n), b.action)
                elseif b.action == "Camera" then
                    local shot = (b.who or ""):match("^(%a+)")
                    if shot and not SHOTS[shot] then problem(d, "%s: no camera shot '%s'", b.key or ("Beat" .. b.n), shot) end
                end
            end
            for _, k in ipairs(d.unknown or {}) do
                problem(d, "%s - not a key of a cutscene (Place, Shape, a cast group A-Z, Beat<number>[<letter>])", k)
            end
        end
    end
    table.sort(problems)
    for _, p in ipairs(problems) do log("cutscene check: %s", p) end
    if #problems > 0 then
        WaCa.Emit("ShowLine", string.format("WaCa Cutscenes: %d problem(s) in the cutscene files - see UE4SS.log (cutscene check)", #problems))
    end
    return problems
end

-- A RELOAD IN MID-SCENE (VM 2026-11-02: WaCa Cutscenes reloaded while a cutscene played - the new copy knew nothing
-- of it: the view stayed on the old scene's camera for good (later scenes even gave the view back to it), the cats
-- stayed on their marks, the other mods waited for a CutsceneEnded that never came. The story check's Watch = 1 reloads
-- this mod whenever a writer saves a story file.) While a scene plays, what it changed is kept in
-- Saved/WaCaCutsceneRunning.ini - its camera, the HUD, the cats' places; starting again with that file there, the mod
-- puts it all back and sends CutsceneEnded(name, "a reload").
local function runningPath() return WaCa.SaveDir() .. "/../WaCaCutsceneRunning.ini" end
keepRunning = function(run)
    local cats = {}
    for i, e in ipairs(Stage.Snapshot()) do
        cats["c" .. i] = string.format("%s|%.1f %.1f %.1f %.1f|%s|%s", e.path, e.x, e.y, e.z, e.yaw, e.kind, e.hidden and "1" or "0")
    end
    local cardPaths = {}
    for _, c in ipairs(cards) do cardPaths[#cardPaths + 1] = c.path end
    WaCa.WriteIni(runningPath(), { Run = { Name = run.name, Camera = Camera.Path() or "", Hud = hud or "",
        HudWas = tostring(run.hudWas or ""), Subtitle = subtitle or "", Cards = table.concat(cardPaths, ";"),
        __order = { "Name", "Camera", "Hud", "HudWas", "Subtitle", "Cards" } }, Cats = cats,
        __order = { "Run", "Cats" } }, "; WaCa Cutscenes - a cutscene is playing (put back if the mod reloads mid-scene)")
end
clearRunning = function()
    WaCa.WriteIni(runningPath(), { Run = { __order = {} }, __order = { "Run" } }, "; WaCa Cutscenes - no cutscene playing")
end
local function recoverRunning()
    local ini = WaCa.ReadIni(runningPath()) or {}
    local r = ini["Run"] or {}
    if (r.Name or "") == "" then return end
    local list = {}
    for k, v in pairs(ini["Cats"] or {}) do
        local path, x, y, z, yaw, kind, hidden = tostring(v):match("^(.-)|(%S+) (%S+) (%S+) (%S+)|(.-)|(%d)$")
        if k ~= "__order" and path then
            list[#list + 1] = { path = path, x = tonumber(x), y = tonumber(y), z = tonumber(z), yaw = tonumber(yaw),
                                kind = kind, hidden = hidden == "1" }
        end
    end
    local n = Stage.RestoreFrom(list)
    -- (its subtitle and cards off the screen)
    for path in ((r.Subtitle or "") .. ";" .. (r.Cards or "")):gmatch("[^;]+") do
        pcall(function() local w = StaticFindObject(path) if w and w:IsValid() then w:RemoveFromParent() end end)
    end
    local pc, pawn = Cast.Controller(), Cast.Pawn()
    -- (the view back to the game's own camera actor - the pawn only when there's none)
    pcall(function()
        local gameCam
        for _, c in ipairs(FindAllOf("BP_AdventureCamera_C") or {}) do if c:IsValid() then gameCam = c end end
        pc:SetViewTargetWithBlend(gameCam or pawn, 0, 0, 0, false)
    end)
    pcall(function() local c = (r.Camera or "") ~= "" and StaticFindObject(r.Camera) if c and c:IsValid() then c:K2_DestroyActor() end end)
    pcall(function()
        local o = (r.Hud or "") ~= "" and StaticFindObject(r.Hud)
        -- (a HUD that was collapsed when this scene began was another stuck scene's doing: shown - 4 - all the same)
        local was = tonumber(r.HudWas or "")
        if o and o:IsValid() then o:SetVisibility((was and was ~= 1) and was or 4) end
    end)
    -- (the engine counts ignore requests - a scene stuck before this one added its own: cleared, not counted down)
    pcall(function() pc:ResetIgnoreMoveInput() pc:ResetIgnoreLookInput() end)
    pcall(function() pc.PlayerCameraManager:StopCameraFade() end)
    clearRunning()
    log("%s: was playing when this mod reloaded - put back (%d cat(s), the view, the HUD, your keys)", r.Name, n)
    pcall(WaCa.Emit, "CutsceneEnded", r.Name, "a reload")
end

-- --- the place and the marks ---

local function placeOf(d)
    local pawn = Cast.Pawn()
    if not pawn then return nil end
    local p = pawn:K2_GetActorLocation()
    local camYaw = 0
    pcall(function() camYaw = Cast.Controller().PlayerCameraManager:GetCameraRotation().Yaw end)
    local function ahead(at, yaw) return v(at.X + math.cos(math.rad(yaw)) * cfg.ahead, at.Y + math.sin(math.rad(yaw)) * cfg.ahead, at.Z) end
    local from = v(p.X, p.Y, p.Z)
    -- (returns the middle, the way the scene faces, and how freely it may be fitted to the ground: "Here" - turned
    -- round your cat; "turn" - turned on the spot; "fixed" - a place with its own Yaw)
    local name = d.place
    if name == "Here" then return ahead(from, camYaw), camYaw, "Here", from end
    if name == "Pile" then
        local best, bd
        for _, a in ipairs(FindAllOf("BP_Quest_Giver_FreshKill_C") or {}) do
            pcall(function()
                local q = a:K2_GetActorLocation()
                local dd = (q.X - p.X) ^ 2 + (q.Y - p.Y) ^ 2
                if not bd or dd < bd then best, bd = v(q.X, q.Y, q.Z), dd end
            end)
        end
        if best then return best, Stage.YawTo(from, best), "turn", from end
        log("%s: no fresh-kill pile near - here instead", d.name)
        return ahead(from, camYaw), camYaw, "Here", from
    end
    -- (one of the game's own zones: Zone:I- the Island, Zone:R-05 the RiverClan camp - WaCa Core's ZonePlace)
    local zone = name:match("^Zone:%s*(.+)$")
    if zone then
        local at = WaCa.ZonePlace and WaCa.ZonePlace(zone)
        if at then return v(at.X, at.Y, at.Z), Stage.YawTo(from, at), "turn", from end
        log("%s: no zone %s in the world - here instead", d.name, zone)
        return ahead(from, camYaw), camYaw, "Here", from
    end
    local pl = places[name]
    if pl then return pl.at, pl.yaw or Stage.YawTo(from, pl.at), pl.yaw and "fixed" or "turn", from end
    local x, y, z, yaw = name:match("^([%-%d%.]+)[%s,]+([%-%d%.]+)[%s,]+([%-%d%.]+)[%s,]*([%-%d%.]*)$")
    if x then
        local at = v(tonumber(x), tonumber(y), tonumber(z))
        return at, tonumber(yaw) or Stage.YawTo(from, at), tonumber(yaw) and "fixed" or "turn", from
    end
    log("%s: no place %s - here instead", d.name, name)
    return ahead(from, camYaw), camYaw, "Here", from
end

-- the marks of the shape at the place: mark -> { spot, yaw }
local function marksOf(shape, mid, fwd)
    local f, r = math.rad(fwd), math.rad(fwd + 90)
    local out = {}
    for k, m in pairs(shape.marks) do
        out[k] = { spot = v(mid.X + math.cos(f) * m.fwd + math.cos(r) * m.side, mid.Y + math.sin(f) * m.fwd + math.sin(r) * m.side, mid.Z),
                   group = m.group }
    end
    local function middleOf(group)
        local x, y, n = 0, 0, 0
        for k, o in pairs(out) do if o.group == group then x, y, n = x + o.spot.X, y + o.spot.Y, n + 1 end end
        return n > 0 and v(x / n, y / n, mid.Z) or mid
    end
    for k, o in pairs(out) do
        local rule = shape.face[k] or shape.face[o.group] or "Middle"
        local target
        if rule == "Forward" then o.yaw = fwd
        elseif rule == "Camera" then o.yaw = fwd + 180
        elseif out[rule] then target = out[rule].spot
        elseif rule:match("^%u$") then target = middleOf(rule)
        else target = mid end
        if target then
            local same = math.abs(target.X - o.spot.X) + math.abs(target.Y - o.spot.Y) < 1
            o.yaw = same and (fwd + 180) or Stage.YawTo(o.spot, target)
        end
    end
    return out
end

-- THE SHAPE MUST FIT THE GROUND: each mark the cast stands on needs open ground about as high as the middle, with
-- nothing solid between it and the middle at knee height (a meeting set out 2.5 m in front of your cat put the leader
-- inside the river's rocks: VM 2026-10-30). Returns how many of the used marks fit, the first that doesn't, the
-- middle's ground height.
local function fitScore(shape, used, mid, fwd)
    local pawn = Cast.Pawn()
    local g0, wet0 = Stage.GroundAt(pawn, mid.X, mid.Y, mid.Z, 200)
    if not g0 then return 0, "the middle", nil end
    local marks = marksOf(shape, v(mid.X, mid.Y, g0), fwd)
    local n, bad = 0, wet0 and "the middle (water)" or nil
    for _, k in ipairs(used) do
        local m = marks[k]
        local g, wet
        if m then g, wet = Stage.GroundAt(pawn, m.spot.X, m.spot.Y, g0, 150) end
        local ok = g and not wet and math.abs(g - g0) <= 100
            and not Stage.Blocked(pawn, v(mid.X, mid.Y, g0 + 40), v(m.spot.X, m.spot.Y, g + 40))
        if ok then n = n + 1 else bad = bad or (wet and (k .. " (water)") or k) end
    end
    -- (a middle in the water counts against the whole shape)
    if wet0 then n = n - 1 end
    return n, bad, g0
end

-- ENCLOSED: how many of 8 short traces round a scene's middle (at a cat's head height) hit something - trunks, roots,
-- rocks. A scene staged inside a big tree's root zone has no good shot from any side: the leaves over the roots have no
-- collision, the camera can't see them (VM 2026-11-02, the camp's river edge: 7 of 12 hit, open camp 0)
local kismetFit
local function enclosure(mid)
    kismetFit = kismetFit or StaticFindObject("/Script/Engine.Default__KismetSystemLibrary")
    local at = v(mid.X, mid.Y, mid.Z + 60)
    local n = 0
    for a = 0, 315, 45 do
        local hit = {}
        local to = v(at.X + math.cos(math.rad(a)) * cfg.enclosedAt, at.Y + math.sin(math.rad(a)) * cfg.enclosedAt, at.Z)
        local ok, b = pcall(function()
            return kismetFit:LineTraceSingle(Cast.Pawn(), at, to, 1, true, {}, 0, hit, true,
                { R = 0, G = 0, B = 0, A = 0 }, { R = 0, G = 0, B = 0, A = 0 }, 0)
        end)
        if ok and b then n = n + 1 end
    end
    return n
end

-- where the shape fits best: Here - turned round your cat (the scene's middle nearer if it must be); turn - turned on
-- the spot; fixed - as it is (checked, logged)
local function fit(name, shape, used, mid, fwd, how, from)
    local turns = how == "fixed" and { 0 } or { 0, 45, -45, 90, -90, 135, -135, 180 }
    -- (Here: in front of your cat first; further out when the near spots are enclosed - EnclosedAt)
    local reach = how == "Here" and { cfg.ahead, cfg.ahead * 0.5, 0, cfg.ahead * 2, cfg.ahead * 3 } or { false }
    local pawn = Cast.Pawn()
    local best
    for _, dist in ipairs(reach) do
        for _, t in ipairs(turns) do
            local yaw = fwd + t
            local m = mid
            if dist then m = v(from.X + math.cos(math.rad(yaw)) * dist, from.Y + math.sin(math.rad(yaw)) * dist, from.Z) end
            -- (Here: a middle your cat can see - not behind a rock)
            if not (dist and dist > 0 and Stage.Blocked(pawn, from, m)) then
                local n, bad, g = fitScore(shape, used, m, yaw)
                -- (the marks first; among as good, the most open spot - Here only, where the spot is ours to pick)
                local closed = (g and how == "Here" and cfg.enclosedAt > 0) and enclosure(v(m.X, m.Y, g)) or 0
                local score = n * 10 - closed
                if g and (not best or score > best.score) then
                    best = { n = n, bad = bad, mid = v(m.X, m.Y, g), yaw = yaw, turn = t, dist = dist, closed = closed, score = score }
                end
                if best and best.n == #used and best.closed <= 2 then break end
            end
        end
        if best and best.n == #used and best.closed <= 2 then break end
    end
    -- (a place's middle with no room - the Island's zone marks its shore, water around it: VM 2026-10-31 - the nearest
    -- dry ground round it, 3 / 6 / 10 m out)
    if not best and how ~= "Here" then
        for _, ring in ipairs({ 300, 600, 1000 }) do
            for a = 0, 315, 45 do
                local m = v(mid.X + math.cos(math.rad(a)) * ring, mid.Y + math.sin(math.rad(a)) * ring, mid.Z)
                for _, t in ipairs(turns) do
                    local n, bad, g = fitScore(shape, used, m, fwd + t)
                    if g and (not best or n > best.n) then
                        best = { n = n, bad = bad, mid = v(m.X, m.Y, g), yaw = fwd + t, turn = t, moved = ring }
                    end
                    if best and best.n == #used then break end
                end
                if best and best.n == #used then break end
            end
            if best and best.n == #used then break end
        end
    end
    if not best then
        log("%s: no ground found for the scene - it plays where it is", name)
        return mid, fwd
    end
    local notes = {}
    if best.turn ~= 0 then notes[#notes + 1] = string.format("turned %d degrees", best.turn) end
    if best.moved then notes[#notes + 1] = string.format("moved %.0f m off its place (no room there)", best.moved / 100) end
    if best.dist and best.dist ~= cfg.ahead then notes[#notes + 1] = string.format("%.1f m from your cat", best.dist / 100) end
    if (best.closed or 0) > 2 then notes[#notes + 1] = string.format("enclosed on %d of 8 sides (no more open spot near)", best.closed) end
    if best.n < #used then
        notes[#notes + 1] = string.format("only %d of %d marks have room (%s is in the way)", best.n, #used, tostring(best.bad))
    end
    if #notes > 0 then log("%s: to fit the ground - %s", name, table.concat(notes, ", ")) end
    return best.mid, best.yaw
end

-- --- who ---

local function resolveWho(text, run)
    local out = {}
    for _, w in ipairs(split(text, ",&>")) do
        if w == "All" then
            for _, k in ipairs(run.order) do out[#out + 1] = run.cats[k] end
        elseif w == "Player" then
            local p = Cast.Pawn()
            if p then out[#out + 1] = p end
        elseif run.cats[w] then
            out[#out + 1] = run.cats[w]
        elseif run.shape.groups[w] then
            for _, k in ipairs(run.shape.groups[w]) do if run.cats[k] then out[#out + 1] = run.cats[k] end end
        end
    end
    return out
end

local function markOf(run, a)
    for k, cat in pairs(run.cats) do if cat:GetAddress() == a:GetAddress() then return k end end
end

local function nameOf(run, a)
    local k = markOf(run, a)
    return k and run.names[k] or Cast.NameOf(a) or "?"
end

local function pointOf(run, text)
    if text == "Middle" then return run.middle end
    if text == "Camera" then
        local ok, l = pcall(function() return Cast.Controller().PlayerCameraManager:GetCameraLocation() end)
        return ok and v(l.X, l.Y, l.Z) or nil
    end
    local a = resolveWho(text, run)[1]
    if a then local q = a:K2_GetActorLocation() return v(q.X, q.Y, q.Z) end
end

-- --- the screen: lines, the HUD, your keys ---

-- LINES ON SCREEN (Say): the game's centre message card made into a subtitle - its swirl, glow and particles hidden,
-- the text alone, low on the screen (the card as it is was too much for dialogue; the game's caption widget drew
-- nothing on its own; its GUI manager had no subtitle up: VM 2026-10-30). One per cutscene, each line replacing the
-- last. Card: <text> shows the card as it is. Both go by the cutscene's own clock (game time).
local SWIRL = { "CanvasBackground", "BackgroundBlur2", "mcGuiVfxWindPartRight", "mcGuiVfxWindPart", "mcGuiVfxFireflies",
                "mcGuiBaseSelected", "mcGuiBaseSelect1" }
-- (subtitle / cards: declared at the top - the reload file keeps them too)

local function makeCard()
    local class = WaCa.LoadAsset(CARD)
    local pc = Cast.Controller()
    local w = StaticFindObject("/Script/UMG.Default__WidgetBlueprintLibrary"):Create(pc, class, pc)
    w:AddToViewport(60)
    return w
end

-- a widget's own parts by name (the widgets of its widget tree)
local function partsOf(w)
    local tree = w.WidgetTree:GetFullName()
    local parts = {}
    for _, x in ipairs(FindAllOf("Widget") or {}) do
        pcall(function()
            local o = x:GetOuter()
            if o and o:IsValid() and o:GetFullName() == tree then parts[x:GetFName():ToString()] = x end
        end)
    end
    return parts
end

local function subtitleWidget()
    local o = subtitle and StaticFindObject(subtitle)
    if o and o:IsValid() then return o end
    local w = makeCard()
    local parts = partsOf(w)
    local hidden = 0
    for _, n in ipairs(SWIRL) do
        if parts[n] then parts[n]:SetVisibility(1) hidden = hidden + 1 end
    end
    pcall(function()
        local slot = parts.CanvasMessage.Slot
        local p = slot:GetPosition()
        slot:SetPosition({ X = p.X, Y = p.Y + cfg.lineOffset })
    end)
    subtitle = (w:GetFullName():gsub("^%S+ ", ""))
    if playing and playing.recorded then pcall(keepRunning, playing) end
    log("lines on screen: the game's message card as a subtitle (%d of its parts hidden)", hidden)
    return w
end

local function hideLine()
    local o = subtitle and StaticFindObject(subtitle)
    if o and o:IsValid() then pcall(function() o:SetVisibility(1) end) end
end

-- every line and card off the screen (the cutscene's end)
local function clearLines()
    local o = subtitle and StaticFindObject(subtitle)
    if o and o:IsValid() then pcall(function() o:RemoveFromParent() end) end
    subtitle = nil
    for _, c in ipairs(cards) do
        local w = StaticFindObject(c.path)
        if w and w:IsValid() then pcall(function() w:RemoveFromParent() end) end
    end
    cards = {}
end

local function showLine(text)
    local ok, err = pcall(function()
        local w = subtitleWidget()
        w.mcGuiTextInfo:SetText(FText(text))
        w:SetVisibility(4)                         -- (SelfHitTestInvisible: seen, never in the way)
    end)
    if not ok then log("can't show the line \"%s\" (%s)", text, tostring(err)) end
    return ok
end

local function showCard(text, till)
    local ok, err = pcall(function()
        local w = makeCard()
        w.mcGuiTextInfo:SetText(FText(text))       -- (after AddToViewport: its construct sets a string-table key)
        cards[#cards + 1] = { path = (w:GetFullName():gsub("^%S+ ", "")), till = till }
        if playing and playing.recorded then pcall(keepRunning, playing) end
    end)
    if not ok then log("can't show the card \"%s\" (%s)", text, tostring(err)) end
end

-- (each tick: lines and cards whose time is up go - by run.shown, the screen's clock, which runs on while the
-- timeline holds: a line said before a Wait: / Ask: stayed up the whole hold, over the question - VM 2026-11-02)
local function expireLines(run)
    run.shown = run.shown or 0
    if run.lineTill and run.shown >= run.lineTill then
        run.lineTill = nil
        hideLine()
    end
    for i = #cards, 1, -1 do
        if run.shown >= cards[i].till then
            local w = StaticFindObject(cards[i].path)
            if w and w:IsValid() then pcall(function() w:RemoveFromParent() end) end
            table.remove(cards, i)
        end
    end
end

local function setHud(visible, run)
    if not cfg.hideHud then return end
    -- (the cats' name plates too - WBP_GuiQuestNpcWidgetsContainer, one per cat, drawn apart from the HUD: they showed
    -- over a Gathering's cats, VM 2026-10-31)
    if not visible then
        run.platesWas = {}
        for _, w in ipairs(FindAllOf("WBP_GuiQuestNpcWidgetsContainer_C") or {}) do
            pcall(function()
                if w:IsValid() then
                    run.platesWas[#run.platesWas + 1] = { path = w:GetFullName():gsub("^%S+ ", ""), was = w:GetVisibility() }
                    w:SetVisibility(1)
                end
            end)
        end
    elseif run.platesWas then
        for _, e in ipairs(run.platesWas) do
            pcall(function()
                local w = StaticFindObject(e.path)
                if w and w:IsValid() then w:SetVisibility(e.was) end
            end)
        end
        run.platesWas = nil
    end
    local o = hud and StaticFindObject(hud)
    if not (o and o:IsValid()) then return end
    pcall(function()
        if not visible then
            run.hudWas = o:GetVisibility()
            o:SetVisibility(1)                     -- (Collapsed)
        elseif run.hudWas then
            o:SetVisibility(run.hudWas)
        end
    end)
end

local function setKeys(on)
    pcall(function()
        local pc = Cast.Controller()
        pc:SetIgnoreMoveInput(not on)
        pc:SetIgnoreLookInput(not on)
    end)
end

local function fade(from, to, seconds)
    pcall(function() Cast.Controller().PlayerCameraManager:StartCameraFade(from, to, seconds, { R = 0, G = 0, B = 0, A = 1 }, true, true) end)
end

local statics
local function gameNow()
    statics = statics or StaticFindObject("/Script/Engine.Default__GameplayStatics")
    local ok, t = pcall(function() return statics:GetTimeSeconds(Cast.Pawn()) end)
    return ok and t or os.clock()
end

-- --- the beats ---

local function sayFor(text) return cfg.sayBase + #text * cfg.sayPerChar end


function ACTIONS.WalkIn(run, b)
    for _, a in ipairs(resolveWho(b.who, run)) do
        local k = markOf(run, a)
        local m = k and run.marks[k]
        if m then Stage.Walk(a, m.spot, m.yaw) end
    end
end

function ACTIONS.Place(run, b)
    for _, a in ipairs(resolveWho(b.who, run)) do
        local k = markOf(run, a)
        local m = k and run.marks[k]
        if m then Stage.Place(a, m.spot, m.yaw) end
    end
end

function ACTIONS.Walk(run, b)
    local to = pointOf(run, b.what or "Middle")
    if not to then return log("%s: walk - no %s", run.name, tostring(b.what)) end
    for _, a in ipairs(resolveWho(b.who, run)) do
        local q = a:K2_GetActorLocation()
        local dx, dy = to.X - q.X, to.Y - q.Y
        local d = math.max(1, math.sqrt(dx * dx + dy * dy))
        local stop = (b.what == "Middle") and 0 or 110           -- (up to a cat, not into it)
        local spot = v(to.X - dx / d * stop, to.Y - dy / d * stop, to.Z)
        Stage.Walk(a, spot, Stage.YawTo(spot, to))
    end
end

function ACTIONS.Look(run, b)
    local to = pointOf(run, b.what or "Middle")
    if not to then return end
    for _, a in ipairs(resolveWho(b.who, run)) do Stage.Turn(a, Stage.YawTo(a:K2_GetActorLocation(), to)) end
end

function ACTIONS.Pose(run, b)
    local n = 0
    for _, a in ipairs(resolveWho(b.who, run)) do if Stage.Pose(a, b.what or "Stop") then n = n + 1 end end
    log("%s: pose %s - %d cat(s)", run.name, tostring(b.what), n)
end

-- a line's names: {PLAYER} = your cat's name (the game's own lines use it), {P1} / {B2} ... = the cat cast in that slot
-- (library exercise 2026-10-30: a writer's "{PLAYER}" showed as typed)
local function fillNames(run, text)
    return (tostring(text or ""):gsub("{(%w+)}", function(key)
        if key == "PLAYER" then return Cast.PlayerName() end
        local a = resolveWho(key, run)[1]
        return a and nameOf(run, a) or nil
    end))
end

-- a slot a line names but nobody plays ({A2} with no cat for A2), or nil (library pre-work 2026-11-03: "Sit with me, {A2}"
-- went on screen as typed when the newcomer for A2 was missing)
local function uncastName(text)
    return tostring(text or ""):match("{(%u%d+)}")
end

function ACTIONS.Say(run, b)
    local a = resolveWho(b.who, run)[1]
    local line = fillNames(run, b.what or "")
    if not a then return log("%s: %s isn't cast - its line is left out", run.name, b.who) end
    if uncastName(line) then return log("%s: a line names %s, who isn't cast - left out", run.name, uncastName(line)) end
    local name = nameOf(run, a)
    log("%s: %s says \"%s\"", run.name, name, line)
    if showLine(name .. ": " .. line) then run.lineTill = (run.shown or 0) + sayFor(line) end
end

-- Sound: <cue> [= <volume>] - one of the game's own sounds, 2D (library pre-work 2026-11-03: a scene had no sound of its
-- own - no music sting, no growl). <cue> = a full path (/Game/Audio/Cues/UI/S_Cue_ui_back) or the short form under the
-- game's cue folder (UI/S_Cue_ui_back); volume 1 = as the game plays it. The scene's sounds stop when it ends.
function ACTIONS.Sound(run, b)
    local name = trim(b.who or "")
    if name == "" then return log("%s: Sound needs a cue (UI/S_Cue_ui_back or a /Game/... path)", run.name) end
    local path = name:sub(1, 1) == "/" and name or ("/Game/Audio/Cues/" .. name)
    if not path:find("%.") then path = path .. "." .. path:match("([^/]+)$") end
    local volume = tonumber(trim(b.what or "")) or 1
    local ok, err = pcall(function()
        local cue = WaCa.Live(WaCa.LoadAsset(path))
        if not cue then error("no such sound asset") end
        local comp = StaticFindObject("/Script/Engine.Default__GameplayStatics"):SpawnSound2D(Cast.Pawn(), cue, volume, 1.0,
            0.0, nil, false, true)
        if WaCa.Live(comp) then
            run.sounds = run.sounds or {}
            run.sounds[#run.sounds + 1] = (comp:GetFullName():gsub("^%S+ ", ""))
            log("%s: sound %s (volume %.2f)%s", run.name, path, volume, comp:IsPlaying() and "" or " - not playing")
        else
            log("%s: sound %s - the engine gave no audio component", run.name, path)
        end
    end)
    if not ok then log("%s: sound %s failed (%s)", run.name, path, tostring(err)) end
end

function ACTIONS.Card(run, b)
    local text = fillNames(run, b.what and (b.who .. " = " .. b.what) or b.who)
    if uncastName(text) then return log("%s: a card names %s, who isn't cast - left out", run.name, uncastName(text)) end
    showCard(text, (run.shown or 0) + sayFor(text))
end

function ACTIONS.Camera(run, b)
    Camera.Shot(b.who, b.what and resolveWho(b.what, run) or {}, b.blend)
end

function ACTIONS.Fade(run, b) fade(0, 1, tonumber(b.who) or 1) end
function ACTIONS.FadeIn(run, b) fade(1, 0, tonumber(b.who) or 1) end
-- (Emit: <event> = <value> hands the value over first, as WaCa Clan Life's step does - library exercise 2026-11-02;
-- without one the cutscene's name, as before)
function ACTIONS.Emit(run, b)
    if b.what and b.what ~= "" then WaCa.Emit(b.who, b.what, run.name) else WaCa.Emit(b.who, run.name) end
end
-- Set: <story variable> = <value> - WaCa Clan Life's story variables, set at that moment of the scene (a scene can
-- remember what happened in it: Set: SawEnvoy = 1)
function ACTIONS.Set(run, b)
    if not (b.who and b.who ~= "" and b.what) then log("%s: Set needs <variable> = <value>", run.name) return end
    storyVars[b.who] = tonumber(b.what) or b.what
    WaCa.Emit("SetStoryVar", b.who, tonumber(b.what) or b.what)
end
function ACTIONS.End(run) run.ending = "its End beat" end

-- Ask: <var> = <question>; <answers> - library exercise 2026-11-02 (a cutscene couldn't ask the player anything, nor
-- go two ways): WaCa Clan Life's Choice asks (PlayScene); the timeline holds till its ChoiceAnswered event (not a
-- change of the variable - the same answer as last time changes nothing).
function ACTIONS.Ask(run, b)
    local var = trim(b.who)
    if var == "" or not b.what then return log("%s: Ask needs <variable> = <question>; <answer>; <answer>", run.name) end
    storyVars[var] = nil
    run.lineTill = nil
    hideLine()                                     -- (the question takes the line's place)
    run.hold = { ask = var, before = nil, since = 0, why = "the answer to " .. var }
    -- (library exercise 2026-11-03, the question on the game's answer menu: its {B1} names were left as typed, and the
    -- speaker's plate could only take a name typed in - the leader's differs per save. A cast slot before the question
    -- - "A1: Should {B1} stay?" - is the speaker: the plate shows the cat cast in it)
    local what = b.what
    local slot, rest = what:match("^%s*(%w+):%s*(.*)$")
    local speaker = slot and resolveWho(slot, run)[1]
    if speaker then what = nameOf(run, speaker) .. ": " .. rest end
    what = fillNames(run, what)
    WaCa.Emit("PlayScene", "Choice: " .. var .. " = " .. what)
    log("%s: asks %s - %s", run.name, var, what)
end

-- Wait: <who> - the timeline holds till those cats are on their marks (a walk takes what it takes: a writer can't
-- know how far out a cat starts, or the game's speed - library exercise 2026-11-01, a line said before its speaker
-- had walked in); at most WaitMax s. Wait: <seconds> - a plain pause.
function ACTIONS.Wait(run, b)
    local secs = tonumber(b.who or "")
    if secs then
        run.hold = { till = secs, since = 0, why = string.format("%.1f s", secs) }
        return
    end
    local cats = resolveWho(b.who, run)
    run.hold = { cats = cats, since = 0, why = tostring(b.who) }
end

-- --- playing one ---

local finish

local function tick()
    local run = playing
    if not run or run.over then return end
    local now = gameNow()
    local dt = math.max(0, math.min(1, now - (run.last or now)))
    run.last = now
    if run.started then run.shown = (run.shown or 0) + dt end
    if run.started and run.hold then
        -- (the timeline holds: Wait)
        local h = run.hold
        h.since = h.since + dt
        local done
        if h.ask then
            done = h.answer ~= nil
            if not done and h.since >= cfg.askMax then
                log("%s: no answer to %s in %.0f s (is WaCa Clan Life on?) - goes on", run.name, h.ask, h.since)
                done = true
            end
            if h.answer ~= nil then
                log("%s: %s answered %s - the timeline goes on", run.name, h.ask, tostring(h.answer))
            end
        elseif h.till then
            done = h.since >= h.till
        else
            done = true
            for _, a in ipairs(h.cats or {}) do
                local ok, walking = pcall(Stage.Walking, a)
                if ok and walking then done = false end
            end
            if not done and h.since >= cfg.waitMax then
                log("%s: waited %.0f s for %s - goes on", run.name, h.since, h.why)
                done = true
            end
        end
        if done then
            if not h.till and not h.ask then log("%s: %s on their marks (%.1f s) - the timeline goes on", run.name, h.why, h.since) end
            run.hold = nil
        end
    elseif run.started then
        run.t = run.t + dt
        while not run.hold and run.beats[run.next] and run.beats[run.next].t <= run.t do
            local b = run.beats[run.next]
            run.next = run.next + 1
            local fn = ACTIONS[b.action]
            if b.guard and not guardHolds(b.guard) then
                log("%s: beat at %.1f s (%s) skipped - [%s] doesn't hold", run.name, b.t, b.action, b.guard)
            elseif fn then
                local ok, err = pcall(fn, run, b)
                if not ok then log("%s: beat at %.1f s (%s) failed - %s", run.name, b.t, b.action, tostring(err)) end
            else
                log("%s: no action %s (beat at %.1f s)", run.name, tostring(b.action), b.t)
            end
        end
        local last = run.beats[#run.beats]
        if not run.ending and not run.beats[run.next] and run.t >= (last and last.t or 0) + cfg.endAfter then
            run.ending = "its last beat"
        end
        if not run.ending and run.t >= cfg.maxSeconds then run.ending = "MaxSeconds" end
    end
    pcall(Stage.Tick, dt)
    Camera.Tick(dt)
    pcall(expireLines, run)
    if not run.recorded and Camera.Path() then run.recorded = true pcall(keepRunning, run) end
    if run.ending then return finish(run.ending) end
    ExecuteInGameThreadWithDelay(50, tick)
end

finish = function(why)
    local run = playing
    if not run or run.over then return end
    run.over = true
    fade(0, 1, cfg.fade)
    ExecuteInGameThreadWithDelay(math.floor(cfg.fade * 1000) + 100, function()
        clearLines()
        -- (the scene's own sounds end with it - a music sting must not outlive the scene)
        for _, path in ipairs(run.sounds or {}) do
            pcall(function()
                local comp = WaCa.Live(StaticFindObject(path))
                if comp and comp:IsPlaying() then comp:Stop() end
            end)
        end
        local n = 0
        pcall(function() n = Stage.Release(cfg.putPlayerBack) end)
        -- (the scene took your cat far away: back to where it was, with PutPlayerBack)
        if cfg.putPlayerBack and run.cameFrom then
            pcall(function() Cast.Pawn():K2_SetActorLocation(run.cameFrom, false, {}, true) end)
        end
        pcall(Camera.End)
        setHud(true, run)
        setKeys(true)
        fade(1, 0, cfg.fade)
        log("%s: over (%s, %.1f s) - %d cat(s) back in their places", run.name, why, run.t, n)
        playing = nil
        pcall(clearRunning)
        pcall(WaCa.Emit, "CutsceneEnded", run.name, why)
        pcall(WaCa.Publish, "cutscene", { playing = false, name = run.name }, true)
        local nextName = table.remove(queue, 1)
        if nextName then ExecuteInGameThreadWithDelay(1000, function() Cutscenes.Play(nextName) end) end
    end)
end

function Cutscenes.Play(name)
    local d = defs[name]
    if not d then
        log("no cutscene %s (known: %s)", tostring(name), (function()
            local k = {} for n in pairs(defs) do k[#k + 1] = n end table.sort(k) return table.concat(k, ", ") end)())
        pcall(WaCa.Emit, "CutsceneEnded", tostring(name), "unknown")
        return false
    end
    if playing then
        table.insert(queue, name)
        log("%s: waits for %s", name, playing.name)
        pcall(WaCa.Emit, "CutsceneQueued", name, playing.name)
        return true
    end
    if not cfg.on then
        log("%s: cutscenes are off (cutscenes.ini On = 0)", name)
        pcall(WaCa.Emit, "CutsceneEnded", name, "off")
        return false
    end
    if d.scene then
        local run = { name = name, scene = true }
        playing = run
        local ok = Scenes.Play(d, function(why)
            if playing ~= run then return end
            playing = nil
            log("%s: over (%s)", name, why)
            pcall(WaCa.Emit, "CutsceneEnded", name, why)
            pcall(WaCa.Publish, "cutscene", { playing = false, name = name }, true)
            local nextName = table.remove(queue, 1)
            if nextName then ExecuteInGameThreadWithDelay(1000, function() Cutscenes.Play(nextName) end) end
        end)
        if not ok then
            playing = nil
            pcall(WaCa.Emit, "CutsceneEnded", name, "the game's scene didn't start")
            return false
        end
        pcall(WaCa.Emit, "CutsceneStarted", name)
        pcall(WaCa.Publish, "cutscene", { playing = true, name = name }, true)
        return true
    end
    local shape = shapes[d.shape]
    if not shape then
        log("%s: no shape %s", name, d.shape)
        pcall(WaCa.Emit, "CutsceneEnded", name, "no shape")
        return false
    end
    local mid, fwd, how, from = placeOf(d)
    if not mid then
        log("%s: not in the world", name)
        pcall(WaCa.Emit, "CutsceneEnded", name, "not in the world")
        return false
    end
    -- (a place far from your cat - the Island from your camp: its ground isn't loaded there, VM 2026-10-31 "no ground
    -- found" - so your cat goes there first and the scene starts once the world around it has come in)
    local far = (mid.X - from.X) ^ 2 + (mid.Y - from.Y) ^ 2 > cfg.farAway ^ 2
    if far and not farFrom[name] then
        farFrom[name] = from
        log("%s: its place is %.0f m away - your cat goes there first (the place loads)", name,
            math.sqrt((mid.X - from.X) ^ 2 + (mid.Y - from.Y) ^ 2) / 100)
        pcall(function() Cast.Pawn():K2_SetActorLocation(v(mid.X, mid.Y, mid.Z + 300), false, {}, true) end)
        ExecuteInGameThreadWithDelay(math.floor(cfg.farWait * 1000), function() Cutscenes.Play(name) end)
        return true
    end
    local cameFrom = farFrom[name]
    farFrom[name] = nil
    -- the cast, mark by mark (A1, A2, B1 ... in the shape's order)
    local order, specs = {}, {}
    for _, g in ipairs(shape.order) do
        for i, k in ipairs(shape.groups[g]) do
            local spec = d.groups[g] and d.groups[g][i]
            if spec then order[#order + 1] = k specs[#specs + 1] = spec end
        end
        if d.groups[g] and #d.groups[g] > #shape.groups[g] then
            log("%s: group %s names %d cats, the shape %s has %d marks - the rest stay out", name, g, #d.groups[g],
                d.shape, #shape.groups[g])
        end
    end
    local found = Cast.Fill(specs)
    local run = { name = name, shape = shape, middle = mid, forward = fwd, cats = {}, names = {}, order = {},
                  beats = d.beats, next = 1, t = 0, cameFrom = cameFrom }
    local lines = {}
    for i, k in ipairs(order) do
        local f = found[i]
        if f then
            run.cats[k], run.names[k] = f.actor, f.name
            run.order[#run.order + 1] = k
            run.kinds = run.kinds or {}
            run.kinds[k] = f.kind
            run.hidden = run.hidden or {}
            run.hidden[k] = f.hidden
            lines[#lines + 1] = string.format("%s = %s (%s)", k, f.name, specs[i])
        else
            lines[#lines + 1] = string.format("%s = nobody (%s)", k, specs[i])
        end
    end
    mid, fwd = fit(name, shape, run.order, mid, fwd, how, from)
    run.middle, run.forward = mid, fwd
    run.marks = marksOf(shape, mid, fwd)
    -- who walks in starts out of the shape: WalkFrom further out from the middle than its mark
    local walksIn = {}
    for _, b in ipairs(d.beats) do
        if b.action == "WalkIn" then for _, a in ipairs(resolveWho(b.who, run)) do walksIn[a:GetAddress()] = true end end
    end
    playing = run
    log("%s: begins - %s at %s (%.0f %.0f, facing %.0f); %s; %d beat(s)", name, d.shape, d.place, mid.X, mid.Y, fwd,
        table.concat(lines, ", "), #d.beats)
    -- (the cast's object paths go with it: other mods keep their own cats out of the scene - Clan Life's party)
    local castPaths = {}
    for _, k in ipairs(run.order) do pcall(function() castPaths[#castPaths + 1] = Cast.PathOf(run.cats[k]) end) end
    pcall(WaCa.Emit, "CutsceneStarted", name, castPaths)
    pcall(WaCa.Publish, "cutscene", { playing = true, name = name, cast = castPaths }, true)
    setKeys(false)
    fade(0, 1, cfg.fade)
    ExecuteInGameThreadWithDelay(math.floor(cfg.fade * 1000) + 100, function()
        local ok, err = pcall(function()
            for _, k in ipairs(run.order) do
                local a, m = run.cats[k], run.marks[k]
                Stage.Take(a, run.names[k], run.kinds[k], run.hidden and run.hidden[k])
                if walksIn[a:GetAddress()] then
                    local dx, dy = m.spot.X - mid.X, m.spot.Y - mid.Y
                    local len = math.sqrt(dx * dx + dy * dy)
                    if len < 1 then dx, dy, len = -math.cos(math.rad(fwd)), -math.sin(math.rad(fwd)), 1 end
                    -- (the farthest start with open ground and a clear way in: WalkFrom, two thirds, a third of it)
                    local start
                    for _, k2 in ipairs({ 1, 0.66, 0.33 }) do
                        local s = v(m.spot.X + dx / len * cfg.walkFrom * k2, m.spot.Y + dy / len * cfg.walkFrom * k2, m.spot.Z)
                        local g, wet = Stage.GroundAt(a, s.X, s.Y, m.spot.Z, 150)
                        if g and not wet and math.abs(g - m.spot.Z) <= 120
                            and not Stage.Blocked(a, v(m.spot.X, m.spot.Y, m.spot.Z + 40), v(s.X, s.Y, g + 40)) then
                            start = s
                            break
                        end
                    end
                    start = start or v(m.spot.X, m.spot.Y, m.spot.Z)
                    Stage.Place(a, start, Stage.YawTo(start, m.spot))
                else
                    Stage.Place(a, m.spot, m.yaw)
                end
            end
            setHud(false, run)
            Camera.Begin(mid, fwd)
            -- (the opening shot: the scene wide, unless the first beat at 0 s sets its own)
            local own = false
            for _, b in ipairs(d.beats) do if b.t == 0 and b.action == "Camera" then own = true end end
            if not own then Camera.Shot("Wide", {}, 0) end
        end)
        if not ok then log("%s: setting the scene failed - %s", name, tostring(err)) end
        fade(1, 0, cfg.fade)
        run.started = true
        run.last = gameNow()
        tick()
    end)
    return true
end

function Cutscenes.Playing() return playing and playing.name or nil end
-- the cutscenes and shapes read (name -> definition) - for other mods and tools; don't change them
function Cutscenes.Defs() return defs end
function Cutscenes.Shapes() return shapes end

function Cutscenes.Init(c)
    WaCa, log, modDir = c.WaCa, c.log, c.modDir
    Cast = require("cast")
    Stage = require("stage")
    Camera = require("camera")
    Scenes = require("scenes")
    readShapes()
    readPlaces()
    local camCfg = readCutscenes()
    Cast.Init({ WaCa = WaCa, log = log })
    Scenes.Init({ WaCa = WaCa, log = log, Cast = Cast })
    Stage.Init({ WaCa = WaCa, log = log, Cast = Cast, walkSpeed = cfg.walkSpeed })
    Camera.Init({ WaCa = WaCa, log = log, Stage = Stage, Cast = Cast, camera = {
        fov = camCfg.FOV, wideBack = camCfg.WideBack, wideUp = camCfg.WideUp, orbitRadius = camCfg.OrbitRadius,
        orbitSpeed = camCfg.OrbitSpeed, portrait = camCfg.Portrait, letterbox = camCfg.Letterbox, focus = camCfg.Focus,
        catGap = camCfg.CatGap, foliageRadius = camCfg.FoliageRadius } })
    local names, shapeNames = {}, {}
    for n in pairs(defs) do names[#names + 1] = n end
    for n in pairs(shapes) do shapeNames[#shapeNames + 1] = n end
    table.sort(names)
    table.sort(shapeNames)
    pcall(Cutscenes.Check)
    -- (a reload with the world up: a scene the copy before was playing is put back)
    ExecuteInGameThreadWithDelay(1500, function() if WaCa.CurrentSlot() then pcall(recoverRunning) end end)
    log("%s - %d cutscene(s): %s; shapes: %s", cfg.on and "on" or "off (cutscenes.ini On = 0)", #names,
        table.concat(names, ", "), table.concat(shapeNames, ", "))
    -- (for other mods - WaCa Clan Life's story check: every Cutscene: step names one of these)
    pcall(WaCa.Publish, "cutscenes.names", names, true)
    WaCa.On("ScreenShown", function(screen)
        local cls = screen:GetClass():GetFName():ToString()
        if cls:find("^WBP_GuiHudGame") then hud = (screen:GetFullName():gsub("^%S+ ", "")) end
        -- (the world going - a load, the main menu: a cutscene playing ends now, its cats go with the level)
        if playing and (cls:find("Loader") or cls:find("MainMenu") or cls:find("Transition")) then
            log("%s: the level is going - ended", playing.name)
            pcall(WaCa.Emit, "CutsceneEnded", playing.name, "level left")
            playing, queue = nil, {}
            pcall(Camera.End)
            setKeys(true)
        end
    end)
    -- (for writers: WhereKey logs where your cat stands as a places.ini entry; PreviewKey plays the Preview cutscene)
    WaCa.On("KeyDown", function(_, key)
        key = tostring(key)
        if key == cfg.whereKey and key ~= "" then
            pcall(function()
                local p = Cast.Pawn():K2_GetActorLocation()
                local yaw = Cast.Controller().PlayerCameraManager:GetCameraRotation().Yaw
                log("where you are - for places.ini: [Place.MyPlace] At = %.0f %.0f %.0f  Yaw = %.0f", p.X, p.Y, p.Z, yaw)
            end)
        elseif key == cfg.previewKey and key ~= "" and cfg.preview ~= "" then
            ExecuteInGameThread(function() pcall(Cutscenes.Play, cfg.preview) end)
        elseif cfg.skipKey ~= "" and WaCa.KeyIs(key, cfg.skipKey) and playing and not playing.over and not playing.scene then
            playing.ending = "skipped"
        end
    end)
    -- (a skip: the SkipKey, or any mod - WaCa.Emit("SkipCutscene"); it ends as at its End: fade, cats back, the game's
    -- camera and HUD; library follow-up (d), 2026-10-31)
    WaCa.On("SkipCutscene", function()
        if playing and not playing.over and not playing.scene then playing.ending = "skipped" end
    end)
    -- A LINE ON SCREEN FOR ANY MOD (library exercise 2026-10-30: Clan Life's hunt comments had nowhere to show a line
    -- outside a cutscene): WaCa.Emit("ShowLine", "<who>: <line>" [, seconds]) - the cutscenes' subtitle, gone after
    -- seconds (default: by its length). Left out while a cutscene plays (its own lines go first).
    local lineGen = 0
    WaCa.On("ShowLine", function(text, seconds)
        if playing or not text or text == "" then return end
        ExecuteInGameThread(function()
            lineGen = lineGen + 1
            local gen = lineGen
            if not showLine(tostring(text)) then return end
            log("line: %s", tostring(text))
            local t = tonumber(seconds) or sayFor(tostring(text))
            -- (gone for good, not just hidden: the line is the game's centre-message POPUP - left hidden on screen it kept
            -- taking the menu keys, and Esc could no longer close the pause menu: VM 2026-11-02, 'COMMAND 89 on
            -- WBP_GuiPopupCenterMessage_C' with the pause screen up. A cutscene's own lines are removed at its end.)
            ExecuteInGameThreadWithDelay(math.floor(t * 1000), function()
                if gen == lineGen and not playing then
                    local o = subtitle and StaticFindObject(subtitle)
                    if o and o:IsValid() then pcall(function() o:RemoveFromParent() end) end
                    subtitle = nil
                end
            end)
        end)
    end)
    WaCa.On("StoryVar", function(name, value) if name then storyVars[tostring(name)] = value end end)
    -- A CAMERA MOMENT outside a cutscene (library exercise 2026-11-03, item 5's "a nicer moment" when your cat joins a
    -- clanmate): WaCa.Emit("CameraMoment", shot, "<actor path>;<actor path>", seconds[, blend]) - the cutscene camera
    -- frames those cats with that shot (Two, Portrait, Over, Wide ...) for that many game seconds, then blends back to
    -- the game's camera. Your keys and the HUD stay; a cutscene starting (or one playing) wins.
    local moment
    WaCa.On("CameraMoment", function(shotName, who, seconds, blend)
        ExecuteInGameThread(function()
            if playing then log("camera moment: a cutscene is playing - none") return end
            local actors = {}
            for path in tostring(who or ""):gmatch("[^;]+") do
                local a = WaCa.Live(StaticFindObject(path))
                if a then actors[#actors + 1] = a end
            end
            if #actors == 0 then log("camera moment: none of '%s' is there", tostring(who)) return end
            local mid, fwd = v(0, 0, 0), 0
            for _, a in ipairs(actors) do
                local p = a:K2_GetActorLocation()
                mid = v(mid.X + p.X / #actors, mid.Y + p.Y / #actors, mid.Z + p.Z / #actors)
            end
            pcall(function() fwd = Cast.Pawn():K2_GetActorRotation().Yaw end)
            local mine = {}
            moment = mine
            Camera.Begin(mid, fwd)
            Camera.Shot(tostring(shotName or "Two"), actors, tonumber(blend) or 1)
            local started, last = gameNow(), gameNow()
            local function step()
                if moment ~= mine then return end
                if playing then moment = nil return end          -- (a cutscene took the camera)
                local now = gameNow()
                Camera.Tick(math.max(0, math.min(1, now - last)))
                last = now
                if now - started >= (tonumber(seconds) or 4) then
                    moment = nil
                    Camera.Shot("Game", {}, tonumber(blend) or 1)
                    ExecuteInGameThreadWithDelay(math.floor((tonumber(blend) or 1) * 1000) + 200, function()
                        if not playing and not moment then pcall(Camera.End) end
                    end)
                    log("camera moment: over (%.1f s)", now - started)
                    return
                end
                ExecuteInGameThreadWithDelay(50, step)
            end
            log("camera moment: %s on %d cat(s) for %.1f s", tostring(shotName), #actors, tonumber(seconds) or 4)
            step()
        end)
    end)
    WaCa.On("ChoiceAnswered", function(name, n)
        if not name then return end
        storyVars[tostring(name)] = n
        local h = playing and playing.hold
        if h and h.ask == tostring(name) then h.answer = n end
    end)
    WaCa.On("PlayCutscene", function(name)
        ExecuteInGameThread(function()
            local ok, err = pcall(Cutscenes.Play, trim(name))
            if not ok then log("playing %s failed - %s", tostring(name), tostring(err)) end
        end)
    end)
end

return Cutscenes
