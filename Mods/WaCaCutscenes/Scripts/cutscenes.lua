-- CUTSCENES FROM TEXT (tickets: "what a writer would need to truly build their own story"). A cutscene is a section
-- of config/cutscenes.ini - or of any enabled mod's content/cutscenes.ini:
--   [Cutscene.RogueStandoff]
--   Place = Here                 where it plays: Here (in front of your cat), Pile (the fresh-kill pile), a place
--                                from places.ini, or "X Y Z [yaw]"
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
-- Who: a mark (A1, B2), a group (B), All, Player. Actions:
--   WalkIn: <who>                the cats walk onto their marks (they start a few metres out - WalkFrom)
--   Walk: <who> = <who>          walk up to another cat (or Middle), facing it
--   Place: <who>                 onto their marks at once
--   Look: <who> = <who>          turn to a cat (or Middle, Camera)
--   Pose: <who> = <pose>         Sit, Lie, Sleep, Eat, Sniff, Meow, Play, Dig, Groom, Win, Hit, Hiss, Growl, TailUp,
--                                Stop - or a montage's path
--   Say: <who> = <line>          the line on screen with the cat's name
--   Card: <text>                 a line on screen without a name
--   Camera: <shot> [= <who> ...] [~<seconds>]   see camera.lua
--   Fade: <seconds> / FadeIn: <seconds>
--   Emit: <event>                another mod's code runs here (WaCa.Emit)
--   End                          the cutscene is over (else 2 s after the last beat)
-- While one plays: your keys and the HUD are off, the cast's cats are held; at the end the cats go back where they
-- were, the game's camera comes back. Events for other mods: PlayCutscene(name) plays one (queued if one is on);
-- CutsceneStarted(name), CutsceneEnded(name, why).
local Cutscenes = {}

local WaCa, log, modDir
local Cast, Stage, Camera
local CARD = "/Game/Art/UXD/Blueprints/Popups/WBP_GuiPopupCenterMessage.WBP_GuiPopupCenterMessage_C"
local cfg = { on = true, ahead = 250, walkFrom = 600, fade = 0.6, maxSeconds = 180, endAfter = 2, hideHud = true,
              putPlayerBack = false, sayBase = 2, sayPerChar = 0.07, lineOffset = 380 }
local defs, shapes, places = {}, {}, {}
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

-- a beat: "<seconds> <Action>[: <who> [= <what>]]"
local function parseBeat(text)
    local t, action, rest = tostring(text):match("^%s*([%d%.]+)%s+(%a+)%s*:?%s*(.-)%s*$")
    if not t then return nil end
    local blend
    local body, b = rest:match("^(.-)%s*~%s*([%d%.]+)$")
    if body then rest, blend = body, tonumber(b) end
    local who, what = rest:match("^(.-)%s*=%s*(.-)$")
    if not who then who, what = rest, nil end
    return { t = tonumber(t), action = action, who = trim(who), what = what and trim(what) or nil, blend = blend }
end

local function readCutscenes()
    local ini = WaCa.ReadContent(modDir .. "/config/cutscenes.ini", "cutscenes") or {}
    local s = ini["Cutscenes"] or {}
    cfg.on = (s.On or "1") ~= "0"
    cfg.ahead = tonumber(s.Ahead or "") or cfg.ahead
    cfg.walkFrom = tonumber(s.WalkFrom or "") or cfg.walkFrom
    cfg.walkSpeed = tonumber(s.WalkSpeed or "")
    cfg.maxSeconds = tonumber(s.MaxSeconds or "") or cfg.maxSeconds
    cfg.hideHud = (s.HideHud or "1") ~= "0"
    cfg.lineOffset = tonumber(s.LineOffset or "") or cfg.lineOffset
    cfg.putPlayerBack = (s.PutPlayerBack or "0") == "1"
    cfg.whereKey, cfg.previewKey, cfg.preview = trim(s.WhereKey), trim(s.PreviewKey), trim(s.Preview)
    defs = {}
    for section, sec in pairs(ini) do
        local name = type(sec) == "table" and section:match("^Cutscene%.(.+)$")
        if name and sec.Off ~= "1" then
            local d = { name = name, place = trim(sec.Place or "Here"), shape = trim(sec.Shape or "Facing"), groups = {},
                        beats = {}, mods = sec.__mods }
            for _, k in ipairs(sec.__order or {}) do
                if k:match("^%u$") then d.groups[k] = split(sec[k], ",") end
                local n = k:match("^Beat(%d+)$")
                if n then
                    local b = parseBeat(sec[k])
                    if b then b.n = tonumber(n) d.beats[#d.beats + 1] = b
                    else log("%s: can't read %s = %s", name, k, tostring(sec[k])) end
                end
            end
            table.sort(d.beats, function(a, b) if a.t ~= b.t then return a.t < b.t end return a.n < b.n end)
            defs[name] = d
        end
    end
    return ini["Camera"] or {}
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

-- where the shape fits best: Here - turned round your cat (the scene's middle nearer if it must be); turn - turned on
-- the spot; fixed - as it is (checked, logged)
local function fit(name, shape, used, mid, fwd, how, from)
    local turns = how == "fixed" and { 0 } or { 0, 45, -45, 90, -90, 135, -135, 180 }
    local reach = how == "Here" and { cfg.ahead, cfg.ahead * 0.5, 0 } or { false }
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
                if g and (not best or n > best.n) then best = { n = n, bad = bad, mid = v(m.X, m.Y, g), yaw = yaw, turn = t, dist = dist } end
                if best and best.n == #used then break end
            end
        end
        if best and best.n == #used then break end
    end
    if not best then
        log("%s: no ground found for the scene - it plays where it is", name)
        return mid, fwd
    end
    local notes = {}
    if best.turn ~= 0 then notes[#notes + 1] = string.format("turned %d degrees", best.turn) end
    if best.dist and best.dist < cfg.ahead then notes[#notes + 1] = string.format("%.1f m in front of your cat", best.dist / 100) end
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
local subtitle                      -- the cutscene's subtitle widget (its object path)
local cards = {}                    -- Card: widgets up now: { path, till (cutscene seconds) }

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
    end)
    if not ok then log("can't show the card \"%s\" (%s)", text, tostring(err)) end
end

-- (each tick: lines and cards whose time is up go)
local function expireLines(run)
    if run.lineTill and run.t >= run.lineTill then
        run.lineTill = nil
        hideLine()
    end
    for i = #cards, 1, -1 do
        if run.t >= cards[i].till then
            local w = StaticFindObject(cards[i].path)
            if w and w:IsValid() then pcall(function() w:RemoveFromParent() end) end
            table.remove(cards, i)
        end
    end
end

local function setHud(visible, run)
    if not cfg.hideHud then return end
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

local ACTIONS = {}

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

function ACTIONS.Say(run, b)
    local a = resolveWho(b.who, run)[1]
    local line = b.what or ""
    if not a then return log("%s: %s isn't cast - its line is left out", run.name, b.who) end
    local name = nameOf(run, a)
    log("%s: %s says \"%s\"", run.name, name, line)
    if showLine(name .. ": " .. line) then run.lineTill = run.t + sayFor(line) end
end

function ACTIONS.Card(run, b)
    local text = b.what and (b.who .. " = " .. b.what) or b.who
    showCard(text, run.t + sayFor(text))
end

function ACTIONS.Camera(run, b)
    Camera.Shot(b.who, b.what and resolveWho(b.what, run) or {}, b.blend)
end

function ACTIONS.Fade(run, b) fade(0, 1, tonumber(b.who) or 1) end
function ACTIONS.FadeIn(run, b) fade(1, 0, tonumber(b.who) or 1) end
function ACTIONS.Emit(run, b) WaCa.Emit(b.who, run.name) end
function ACTIONS.End(run) run.ending = "its End beat" end

-- --- playing one ---

local finish

local function tick()
    local run = playing
    if not run or run.over then return end
    local now = gameNow()
    local dt = math.max(0, math.min(1, now - (run.last or now)))
    run.last = now
    if run.started then
        run.t = run.t + dt
        while run.beats[run.next] and run.beats[run.next].t <= run.t do
            local b = run.beats[run.next]
            run.next = run.next + 1
            local fn = ACTIONS[b.action]
            if fn then
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
        local n = 0
        pcall(function() n = Stage.Release(cfg.putPlayerBack) end)
        pcall(Camera.End)
        setHud(true, run)
        setKeys(true)
        fade(1, 0, cfg.fade)
        log("%s: over (%s, %.1f s) - %d cat(s) back in their places", run.name, why, run.t, n)
        playing = nil
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
                  beats = d.beats, next = 1, t = 0 }
    local lines = {}
    for i, k in ipairs(order) do
        local f = found[i]
        if f then
            run.cats[k], run.names[k] = f.actor, f.name
            run.order[#run.order + 1] = k
            run.kinds = run.kinds or {}
            run.kinds[k] = f.kind
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
    pcall(WaCa.Emit, "CutsceneStarted", name)
    pcall(WaCa.Publish, "cutscene", { playing = true, name = name }, true)
    setKeys(false)
    fade(0, 1, cfg.fade)
    ExecuteInGameThreadWithDelay(math.floor(cfg.fade * 1000) + 100, function()
        local ok, err = pcall(function()
            for _, k in ipairs(run.order) do
                local a, m = run.cats[k], run.marks[k]
                Stage.Take(a, run.names[k], run.kinds[k])
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
    readShapes()
    readPlaces()
    local camCfg = readCutscenes()
    Cast.Init({ WaCa = WaCa, log = log })
    Stage.Init({ WaCa = WaCa, log = log, Cast = Cast, walkSpeed = cfg.walkSpeed })
    Camera.Init({ WaCa = WaCa, log = log, Stage = Stage, Cast = Cast, camera = {
        fov = camCfg.FOV, wideBack = camCfg.WideBack, wideUp = camCfg.WideUp, orbitRadius = camCfg.OrbitRadius,
        orbitSpeed = camCfg.OrbitSpeed, portrait = camCfg.Portrait } })
    local names, shapeNames = {}, {}
    for n in pairs(defs) do names[#names + 1] = n end
    for n in pairs(shapes) do shapeNames[#shapeNames + 1] = n end
    table.sort(names)
    table.sort(shapeNames)
    log("%s - %d cutscene(s): %s; shapes: %s", cfg.on and "on" or "off (cutscenes.ini On = 0)", #names,
        table.concat(names, ", "), table.concat(shapeNames, ", "))
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
        end
    end)
    WaCa.On("PlayCutscene", function(name)
        ExecuteInGameThread(function()
            local ok, err = pcall(Cutscenes.Play, trim(name))
            if not ok then log("playing %s failed - %s", tostring(name), tostring(err)) end
        end)
    end)
end

return Cutscenes
