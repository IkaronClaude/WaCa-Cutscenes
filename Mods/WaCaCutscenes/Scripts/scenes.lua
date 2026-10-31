-- THE GAME'S OWN SCENES, RE-CAST (tickets.md "Cutscenes from text", TYPES: "the game's own cutscene kinds turned
-- generic" - the ceremony first). A cutscene with a Scene plays one of the game's own cinematics - placed, framed and
-- animated the game's way - with its cats dressed as the cats you name:
--   [Cutscene.NewDeputy]
--   Scene = RankUp               the clan's rank-up ceremony in your camp (RankUp.Leader: the leader's at the Moonpool;
--                                Prophecy.Closure: StarClan's cats at the end of a prophecy). Music = <event>: another
--                                music than the scene's own
--   Leader = Freezesong          who the clan's leader is in it: any cast spec (a name, a part, E: / S: roles)
--   Warrior.2 = S:mentor         the scene's second warrior (its cats by the game's clan jobs, numbered)
-- How: the scene's cats are the game's stand-ins (one per clan job, numbered: BP_WrcSK_Customization_Cat), dressed by
-- the game as the clan's own cats when the scene starts; right after, each one you name is dressed again as your cast
-- cat (WaCa Core's CopyLook) - the next scene dresses them back itself. Your cat plays your cat. Only the scene runs:
-- the game's promotion is its quest task's, never touched (WaCa Core's PlaySequence binds no rank-up end).
local Scenes = {}

local WaCa, log, Cast
local TYPE_NARRATIVE = 3            -- ESwtEngineSequencerType: the rank-up ceremonies' table
-- a scene -> its tag and music as the game plays it (the game state's rank-up / prophecy start, traced in the exe)
local SCENES = {
    RankUp = function(clan) return "Gameplay.Narrative.RankUp." .. clan, "mus_cutscene_rankup_" .. clan end,
    ["RankUp.Leader"] = function() return "Gameplay.Narrative.RankUp.Leader", "mus_cutscene_rankup_leader" end,
    ["Prophecy.Closure"] = function(clan) return "Gameplay.Narrative.Prophecy.Closure." .. clan, "mus_moonpool_a" end,
}
local current                       -- { name, tag, slots = { key -> { actor, name } }, clan, done, dressed }

local function enumName(path, value)
    local name
    pcall(function()
        StaticFindObject(path):ForEachName(function(n, v)
            if v == value then name = (n:ToString():gsub("^.*::", "")) end
        end)
    end)
    return name
end

local function enumValue(path, name)
    local value
    pcall(function()
        StaticFindObject(path):ForEachName(function(n, v)
            if (n:ToString():gsub("^.*::", "")) == name then value = v end
        end)
    end)
    return value
end

-- the scene's stand-ins: "<Job>.<n>" (the n-th by the game's index) and "<Job>" (the first) -> actor. A job comes from
-- your clan's stand-ins when it has any, else from any clan's (StarClan's cats at a prophecy's end are not yours)
local function standIns(clan)
    local clanValue = enumValue("/Script/SwtQuest.EClanType", clan)
    local mine, any = {}, {}
    for _, s in ipairs(FindAllOf("WrcCatSkeletalMeshWithCustomization") or {}) do
        pcall(function()
            if not s:IsValid() or s.bIsPlayer or s:GetClass():GetFName():ToString():find("Player") then return end
            local job = enumName("/Script/SwtQuest.EGiverRole", s.GiverRole)
            if not job or not WaCa.CatComponent(s) then return end
            local e = { actor = s, index = s.Index, clan = s.Clan }
            any[job] = any[job] or {}
            table.insert(any[job], e)
            if clanValue and s.Clan == clanValue then
                mine[job] = mine[job] or {}
                table.insert(mine[job], e)
            end
        end)
    end
    local out, byJob = {}, {}
    for job, list in pairs(any) do
        local use = mine[job] or list
        table.sort(use, function(a, b)
            if a.clan ~= b.clan then return a.clan < b.clan end
            return a.index < b.index
        end)
        for i, e in ipairs(use) do out[job .. "." .. i] = e.actor end
        out[job] = use[1].actor
        byJob[job] = use
    end
    return out, byJob
end

local dressing = false               -- our own CopyLook is building looks (its CatLookPart events are ours)
local MAX_PASSES = 20

local function dress(why)
    local run = current
    if not run then return end
    run.passes = (run.passes or 0) + 1
    if run.passes > MAX_PASSES then
        if run.passes == MAX_PASSES + 1 then log("%s: the game keeps rebuilding the scene's cats - left as they are", run.name) end
        return
    end
    local stands, byJob = standIns(run.clan)
    local done, missing = {}, {}
    dressing = true
    for key, cat in pairs(run.slots) do
        local s = stands[key]
        if s and WaCa.CopyLook(s, cat.actor) then
            done[#done + 1] = string.format("%s = %s", key, cat.name)
        else
            missing[#missing + 1] = key
        end
    end
    dressing = false
    table.sort(done)
    local before = run.lastDone
    run.lastDone = table.concat(done, ", ")
    if before ~= run.lastDone or (not run.dressed and #missing > 0) then
        local jobs = {}
        for job, list in pairs(byJob) do jobs[#jobs + 1] = string.format("%s x%d", job, #list) end
        table.sort(jobs)
        log("%s: %s - dressed %s%s", run.name, why, #done > 0 and table.concat(done, ", ") or "nobody",
            #missing > 0 and ("; no stand-in for " .. table.concat(missing, ", ") .. " (the scene's: " .. table.concat(jobs, ", ") .. ")") or "")
    end
    if #done > 0 then run.dressed = true end
end

-- d = the cutscene (d.scene, d.roles: key -> cast spec); done(why) when it is over. False when it can't play.
function Scenes.Play(d, done)
    local clan = WaCa.PlayerClan and WaCa.PlayerClan() or nil
    local make = SCENES[d.scene]
    if not make then
        local known = {}
        for k in pairs(SCENES) do known[#known + 1] = k end
        table.sort(known)
        log("%s: no scene %s (known: %s)", d.name, tostring(d.scene), table.concat(known, ", "))
        return false
    end
    if not clan then
        log("%s: your clan isn't known yet - the scene can't be chosen", d.name)
        return false
    end
    local manager = FindFirstOf("SwtQuestSequencerManager")
    if not WaCaNative_PlaySequence or not manager or not manager:IsValid() then
        log("%s: the game's scenes can't be played (WaCa Core's native part, the sequencer manager)", d.name)
        return false
    end
    local keys, specs = {}, {}
    for k in pairs(d.roles) do if k ~= "Music" then keys[#keys + 1] = k end end
    table.sort(keys)
    for i, k in ipairs(keys) do specs[i] = d.roles[k] end
    local found = Cast.Fill(specs)
    local slots, lines = {}, {}
    for i, k in ipairs(keys) do
        if found[i] then
            slots[k] = { actor = found[i].actor, name = found[i].name }
            lines[#lines + 1] = string.format("%s = %s (%s)", k, found[i].name, specs[i])
        else
            lines[#lines + 1] = string.format("%s = nobody (%s)", k, specs[i])
        end
    end
    local tag, music = make(clan)
    music = d.roles.Music or music
    current = { name = d.name, tag = tag, slots = slots, clan = clan, done = done }
    log("%s: begins - the game's scene %s (%s); %s", d.name, d.scene, tag, #lines > 0 and table.concat(lines, ", ") or "its own cats")
    if not WaCaNative_PlaySequence(manager:GetAddress(), tag, TYPE_NARRATIVE, "", music) then
        log("%s: the game's scene didn't start (WaCa Core's log: [sequences])", d.name)
        current = nil
        return false
    end
    return true
end

function Scenes.Playing() return current and current.name or nil end

function Scenes.Init(c)
    WaCa, log, Cast = c.WaCa, c.log, c.Cast
    -- (the scene's cats are dressed by the game as its scene loads them - their looks built: WaCa Core's CatLookPart.
    -- Each time the game builds a stand-in's look while ours plays, ours goes on again just after; the builds our own
    -- dressing makes are ours. The skip prompt (the scene starting) is a first try. SequencerStarted / Finished are
    -- the manager's delegates, not functions - nothing to hook: VM 2026-10-31)
    local queued = false
    local function soon(why)
        local run = current
        if not run or queued then return end
        queued = true
        ExecuteInGameThreadWithDelay(100, function()
            queued = false
            if current == run then dress(why) end
        end)
    end
    WaCa.On("CatLookPart", function(comp)
        if dressing or not current or queued then return end
        local ok, isStandIn = pcall(function()
            return comp:GetOwner():IsA(StaticFindObject("/Script/Wrc.WrcCatSkeletalMeshWithCustomization"))
        end)
        if ok and isStandIn then soon("the game dressed the scene's cats") end
    end)
    WaCa.On("ScreenShown", function(screen)
        local ok, cls = pcall(function() return screen:GetClass():GetFName():ToString() end)
        if ok and current and cls:find("^WBP_GuiPopupSkip") then soon("the scene starts") end
    end)
    -- (the end: the manager's OnSequenceFinished - any scene's; ours is over when its tag has left the active ones)
    local function active(tag)
        local found = false
        pcall(function()
            FindFirstOf("SwtQuestSequencerManager").ActiveSequences:ForEach(function(k)
                if k:get().TagName:ToString() == tag then found = true end
            end)
        end)
        return found
    end
    local ok = pcall(RegisterHook, "/Script/SwtEngine.SwtSequencerManager:OnSequenceFinished", function()
        local run = current
        if not run then return end
        ExecuteInGameThreadWithDelay(200, function()
            if current ~= run or active(run.tag) then return end
            current = nil
            log("%s: the game's scene is over", run.name)
            if run.done then pcall(run.done, "the scene's end") end
        end)
    end)
    log("the game's scenes: %s", ok and "on" or "the sequencer manager's OnSequenceFinished can't be hooked - off")
    return ok
end

return Scenes
