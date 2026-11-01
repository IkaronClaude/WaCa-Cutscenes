-- THE CAST: which cat plays a part. A cutscene's slots are filled from words a writer knows:
--   Player                       your cat
--   Leader, Deputy, MedicineCat, Queen, Kit, Elder, Apprentice, Warrior, Mentor ...
--                                the cat with that part in your clan (its quest-giver role or its story role), nearest first
--                                - your own cat when it holds that rank (you are the deputy: Deputy = your cat)
--   E:<role>                     one of the game's story roles exactly (ENarrativeRole: E:RiverClanDeputy, E:TheLoner)
--   S:<role>                     a mod's own role - the cat WaCa Clan Life cast for it (events.ini [Cast], a story pack's
--                                content/events.ini: S:herbalist = Mossfeather), from its sticky topic "roles.cast"
--   <a name>                     the cat with that name (Lionstar, Troutwing ...)
--   Nearest                      the nearest clanmate not cast yet
-- The cats are the ones the game shows: the camp's named cats (its quest cats) and, when they're about, its walking cats
-- - of your clan, unless asked for by name or story role. A cat is cast once per cutscene.
local Cast = {}

local WaCa, log
local enumCache = {}

-- the packs' own brought-in cats ([Rogue.<Name>] in cutscenes.ini): name -> { from, fields = { {key, value} } }
local rogueLooks = {}
function Cast.SetRogues(t) rogueLooks = t or {} end

-- a look text with some of the game's look fields set ("(ClanType=RiverClan,...,FurColorIdx=11,...)")
local function withFields(look, fields)
    for _, f in ipairs(fields or {}) do
        local k, v = f[1], f[2]
        local n
        look, n = look:gsub("([,(])" .. k .. "=[^,()]*", "%1" .. k .. "=" .. v)
        if n == 0 then look = look:gsub("%)%s*$", "," .. k .. "=" .. v .. ")") end
    end
    return look
end

local function enumName(path, value)
    local cache = enumCache[path]
    if not cache then
        cache = {}
        enumCache[path] = cache
        pcall(function()
            StaticFindObject(path):ForEachName(function(n, v) cache[v] = n:ToString():gsub("^.*::", "") end)
        end)
    end
    return cache[value]
end

function Cast.PathOf(o) return (o:GetFullName():gsub("^%S+ ", "")) end

function Cast.Controller()
    for _, c in ipairs(FindAllOf("SwtPlayerController") or {}) do
        if c:IsValid() and c.Player then return c end
    end
end

function Cast.Pawn()
    local pc = Cast.Controller()
    local p = pc and pc.Pawn
    return (p and p:IsValid()) and p or nil
end

-- the name your cat goes by: the HUD's own label first (it shows a name WaCa Looks gave it), else the save's
function Cast.PlayerName()
    if WaCa.PlayerName then return WaCa.PlayerName() end
    local name
    for _, w in ipairs(FindAllOf("GuiExplorationCharacterSlot") or {}) do
        pcall(function()
            local t = w:IsValid() and w.mcGuiTextName and w.mcGuiTextName:GetText():ToString()
            if t and t ~= "" then name = t end
        end)
        if name then break end
    end
    if not name then pcall(function() local c = WaCa.SaveCharacter() if c and c.Name then name = c.Name end end) end
    if name and name == name:upper() then name = name:sub(1, 1) .. name:sub(2):lower() end   -- (the HUD's capitals)
    return name or "You"
end

-- a cat's name as the game shows it (its name ids -> the text table)
function Cast.NameOf(cat)
    if WaCa.CatName then return WaCa.CatName(cat) end
    local name
    pcall(function()
        local cd = WaCa.CustomData(cat)
        if not cd then return end
        name = WaCa.GetText(cd.PrefixNameId:ToString() .. cd.SuffixNameId:ToString())
    end)
    return (name and name ~= "") and name or nil
end

local function shown(a)
    local ok, yes = pcall(function()
        if a.bHidden then return false end
        local mesh = a.SkeletalMeshComponent or a.Mesh
        return not mesh or not mesh:IsValid() or mesh:IsVisible()
    end)
    return ok and yes
end

-- every cat that could play a part: { actor, name, clan, giver, story } - nearest to your cat first
local function candidates()
    if WaCa.Cats then return WaCa.Cats() end       -- (WaCa Core's - the same cats, shared with Clan Life)
    local pawn = Cast.Pawn()
    local at = pawn and pawn:K2_GetActorLocation()
    local out = {}
    local function add(a, giver, story, kind)
        local q = a:K2_GetActorLocation()
        -- (a quest cat says its clan itself; a walking cat in its look)
        local clan
        pcall(function() clan = a.ClanType end)
        if type(clan) ~= "number" then pcall(function() local cd = WaCa.CustomData(a) if cd then clan = cd.ClanType end end) end
        out[#out + 1] = {
            actor = a, name = Cast.NameOf(a) or a:GetFName():ToString(),
            clan = type(clan) == "number" and enumName("/Script/SwtQuest.EClanType", clan) or nil,
            giver = giver or "", story = story or "", kind = kind,
            dist = at and math.sqrt((q.X - at.X) ^ 2 + (q.Y - at.Y) ^ 2) or 0,
        }
    end
    for _, a in ipairs(FindAllOf("SwtAdventureQuestActor") or {}) do
        pcall(function()
            if a:IsValid() and shown(a) then
                add(a, enumName("/Script/SwtQuest.EGiverRole", a.GiverRole), enumName("/Script/SwtQuest.ENarrativeRole", a.narrativeRole), "quest")
            end
        end)
    end
    for _, a in ipairs(FindAllOf("SwtAdventureWalkingNPC") or {}) do
        pcall(function() if a:IsValid() and shown(a) then add(a, "", "", "walker") end end)
    end
    table.sort(out, function(x, y) return x.dist < y.dist end)
    return out
end

local PARTS = { Leader = true, Deputy = true, MedicineCat = true, Queen = true, Kit = true, Elder = true,
                Apprentice = true, Warrior = true, Mentor = true }

-- does this cat have that part? (its quest-giver role - Leader, Deputy, MedicineCat ... - or its story role ends in it:
-- RiverClanDeputy, ThunderClanWarrior)
local function hasPart(c, part)
    if c.giver == part then return true end
    if c.story ~= "" and c.story:sub(-#part) == part then return true end
    return false
end

-- fill the slots: specs = { "Player", "Deputy", "Nearest" ... } -> { { actor, name, spec, kind } or false ... }
-- (kind: "player", "quest" - a camp named cat, "walker" - a walking AI cat)
function Cast.Fill(specs)
    local pool = candidates()
    local myClan = WaCa.PlayerClan and WaCa.PlayerClan() or nil
    local taken = {}
    local pawn = Cast.Pawn()
    local function take(c, spec)
        taken[Cast.PathOf(c.actor)] = true
        return { actor = c.actor, name = c.name, spec = spec, kind = c.kind }
    end
    local function free(c) return not taken[Cast.PathOf(c.actor)] end
    local function mine(c) return not (myClan and c.clan and c.clan ~= myClan) end
    local out = {}
    local missed = false
    -- (Player first, then named parts, Nearest last: "Nearest" must not take the deputy a later slot asks for)
    local function rank(spec) return spec == "Player" and 1 or (spec == "Nearest" and 3 or 2) end
    local order = {}
    for i in ipairs(specs) do order[#order + 1] = i end
    table.sort(order, function(a, b)
        local ra, rb = rank(specs[a]), rank(specs[b])
        if ra ~= rb then return ra < rb end
        return a < b
    end)
    -- (your cat holds a part too: the deputy, when you are the deputy)
    local myPart = ({ "Apprentice", "Warrior", "Deputy", "Leader" })[WaCa.PlayerRank and WaCa.PlayerRank() or 0]
    local playerCast = false
    for _, i in ipairs(order) do
        local spec = specs[i]
        local found
        -- (a mod's own role played by a cat who isn't in the world - [Cast] S:loner = Rogue:Quill, = Clan:ShadowClan:
        -- brought in for the scene like the spec itself. Library exercise 2026-11-01: a visiting loner had no way in)
        if spec:match("^S:.+$") then
            local specs2 = WaCa.Latest and WaCa.Latest("roles.specs")
            local to = type(specs2) == "table" and specs2[spec] or nil
            if to and (to:match("^Rogue") or to:match("^Clan:")) then
                log("cast: %s is played by %s - brought in for the scene", spec, to)
                spec = to
            end
        end
        if spec == "Player" or (spec == myPart and not playerCast) then
            if pawn and not playerCast then
                found = { actor = pawn, name = Cast.PlayerName(), spec = spec, kind = "player" }
                playerCast = true
                if spec ~= "Player" then log("cast: %s = your cat (you are the %s)", spec, spec:lower()) end
            end
        else
            local kind = spec:match("^E:(.+)$")
            -- a mod's own role: the cat cast for it (WaCa Clan Life's [Cast], topic roles.cast - its object path)
            local sPath
            if spec:match("^S:.+$") then
                local cast = WaCa.Latest and WaCa.Latest("roles.cast")
                sPath = type(cast) == "table" and cast[spec] or nil
                if not sPath then log("cast: nobody is cast as %s (WaCa Clan Life's [Cast])", spec) end
            end
            for _, c in ipairs(pool) do
                if free(c) then
                    local ok
                    if spec:match("^S:") then ok = sPath ~= nil and Cast.PathOf(c.actor) == sPath
                    elseif kind then ok = c.story == kind
                    elseif spec == "Nearest" then ok = mine(c)
                    elseif PARTS[spec] then ok = mine(c) and hasPart(c, spec)
                    else ok = c.name:lower() == spec:lower() end
                    if ok then found = take(c, spec) break end
                end
            end
        end
        -- (ANOTHER CLAN'S CAT - Clan:ShadowClan.Leader, Clan:WindClan - brought in for the scene: the save's story cat of
        -- that clan and part when it has one, else a cat made up from the save's cats' looks and names, its clan set;
        -- spawned (WaCa Core's SpawnCat), gone again at the scene's end. A Gathering's other Clans - VM 2026-10-31)
        local clan, part = spec:match("^Clan:(%w+)%.?(%w*)$")
        if not found and clan and WaCa.SpawnCat then
            local pick
            for _, c in ipairs(WaCa.StoryCats(clan, part ~= "" and part or nil)) do
                if not pick and not taken["story:" .. c.key] then pick = c end
            end
            if not pick then
                local all = WaCa.StoryCats()
                -- (its name: a prefix of one cat, the suffix its part takes - "star" a leader's, "paw" / "kit" - else a
                -- warrior's of another; never a name the save or the scene already has: "Sunstar" twice, VM 2026-10-31)
                local special = { Leader = "_STAR", Apprentice = "_PAW", Kit = "_KIT" }
                local used = {}
                for _, c in ipairs(all) do used[c.name] = true end
                for _, f in pairs(out) do if f then used[f.name] = true end end
                local suffixes = {}
                for _, c in ipairs(all) do
                    local sfx = c.look:match('SuffixNameId="([^"]*)"') or ""
                    if sfx ~= "" and sfx ~= "_STAR" and sfx ~= "_PAW" and sfx ~= "_KIT" then suffixes[#suffixes + 1] = sfx end
                end
                for _ = 1, 16 do
                    if pick or #all == 0 or (#suffixes == 0 and not special[part]) then break end
                    local a = all[math.random(#all)]
                    local prefix = a.look:match('PrefixNameId="([^"]*)"') or ""
                    local suffix = special[part] or suffixes[math.random(#suffixes)]
                    local name = WaCa.GetText(prefix .. suffix)
                    if prefix ~= "" and name ~= "" and not name:find("^STR_") and not used[name] then
                        local look = a.look:gsub("ClanType=%w+", "ClanType=" .. clan)
                        if not look:find("ClanType=") then look = look:gsub("^%(", "(ClanType=" .. clan .. ",") end
                        if part ~= "" then look = look:gsub("Role=%w+", "Role=" .. part) end
                        look = look:gsub('SuffixNameId="[^"]*"', 'SuffixNameId="' .. suffix .. '"')
                        pick = { key = "made:" .. tostring(i), name = name, look = look, made = true }
                    end
                end
            end
            if pick then
                local p = pawn and pawn:K2_GetActorLocation() or { X = 0, Y = 0, Z = 0 }
                local cat = WaCa.SpawnCat(pick.look, { X = p.X, Y = p.Y, Z = p.Z - 3000 }, 0)
                if cat then
                    taken["story:" .. pick.key] = true
                    found = take({ actor = cat, name = pick.name }, spec)
                    found.kind = "spawned"
                    log("cast: %s = %s - %s, brought in for the scene", spec, pick.name,
                        pick.made and ("a " .. clan .. " cat made up from this save's cats") or ("the save's " .. clan .. " cat"))
                end
            end
        end
        -- (A ROGUE - Rogue, Rogue:Slash - a clanless cat brought in for the scene, dressed from one of the save's cats; its
        -- name the writer's, else one of the game's own rogue names (Tiger, Fox ...); gone again
        -- at the scene's end. Library exercise 2026-11-01: a raid on the camp had no way to cast its rogues)
        local rogueName = spec:match("^Rogue:(.+)$")
        if not found and (spec == "Rogue" or rogueName) and WaCa.SpawnCat then
            local all = WaCa.StoryCats()
            -- (a NAMED rogue always looks the same: its look is from the cat its name picks - the list sorted, the save's
            -- order isn't stable - a writer's recurring Quill was another cat in every scene: library exercise
            -- 2026-11-01)
            table.sort(all, function(x, y) return tostring(x.name) < tostring(y.name) end)
            local seed = 0
            for ch in tostring(rogueName or ""):gmatch(".") do seed = (seed * 31 + ch:byte()) % 2147483647 end
            local tries = 0
            local used = {}
            for _, c in ipairs(all) do used[c.name] = true end
            for _, f in pairs(out) do if f then used[f.name] = true end end
            local pick
            for _ = 1, 16 do
                if pick or #all == 0 then break end
                local a = rogueName and all[(seed + tries) % #all + 1] or all[math.random(#all)]
                -- (the pack's own look for this rogue: From = a cat of the save)
                local own = rogueName and rogueLooks[rogueName]
                if own and own.from and tries == 0 then
                    for _, c in ipairs(all) do if c.name == own.from then a = c break end end
                end
                tries = tries + 1
                local prefix = a.look:match('PrefixNameId="([^"]*)"') or ""
                -- (the game's own rogue names first - WrcNPCGenerationManager.RemainingRogueNames: Tiger, Fox, Fury ...
                -- by their text key; else a cat's kit name less "kit" - a prefix alone has no text: "Mosskit" -> "Moss")
                local word
                if not rogueName then
                    local names = {}
                    pcall(function()
                        FindFirstOf("WrcNPCGenerationManager").RemainingRogueNames:ForEach(function(_, e)
                            local r = e:get()
                            local t = WaCa.GetText(r.PrefixID:ToString())
                            if t == "" or t:find("^STR_") then t = r.Name:ToString() end
                            if t ~= "" and not used[t] then names[#names + 1] = t end
                        end)
                    end)
                    word = #names > 0 and names[math.random(#names)] or nil
                    if not word then
                        local kit = prefix ~= "" and WaCa.GetText(prefix .. "_KIT") or ""
                        word = kit:match("^(.-)kit$") or ""
                    end
                end
                local name = rogueName or word
                if name ~= "" and not name:find("^STR_") and not used[name] then
                    local look = a.look:gsub("Role=%w+", "Role=Warrior")
                    local own = rogueName and rogueLooks[rogueName]
                    if own and #own.fields > 0 then look = withFields(look, own.fields) end
                    pick = { name = name, look = look, from = a.name .. ((own and #own.fields > 0) and (" + " .. #own.fields .. " field(s) of its pack") or "") }
                end
            end
            if pick then
                local p = pawn and pawn:K2_GetActorLocation() or { X = 0, Y = 0, Z = 0 }
                local cat = WaCa.SpawnCat(pick.look, { X = p.X, Y = p.Y, Z = p.Z - 3000 }, 0)
                if cat then
                    found = take({ actor = cat, name = pick.name }, spec)
                    found.kind = "spawned"
                    log("cast: %s = %s - a rogue, brought in for the scene (looks like %s)", spec, pick.name, tostring(pick.from))
                end
            end
        end
        -- (a named / part / story cat the game doesn't draw right now - far off, Lionstar at the river: VM 2026-10-30 -
        -- is cast all the same and shown for the cutscene; follow-up (e). Quest givers only: a parked filler copy is never
        -- moved - moving one crashed the game, VM 2026-10-31)
        if not found and spec ~= "Nearest" and spec ~= "Player" then
            for _, a in ipairs(FindAllOf("SwtAdventureQuestActor") or {}) do
                if found then break end
                pcall(function()
                    if not a:IsValid() or shown(a) or taken[Cast.PathOf(a)] then return end
                    if a:GetClass():GetFName():ToString():find("Filler") then return end
                    local c = { actor = a, name = Cast.NameOf(a) or "", giver = enumName("/Script/SwtQuest.EGiverRole", a.GiverRole) or "",
                                story = enumName("/Script/SwtQuest.ENarrativeRole", a.narrativeRole) or "", kind = "quest" }
                    pcall(function() c.clan = enumName("/Script/SwtQuest.EClanType", a.ClanType) end)
                    local kind = spec:match("^E:(.+)$")
                    local ok
                    if spec:match("^S:") then
                        local cast = WaCa.Latest and WaCa.Latest("roles.cast")
                        ok = type(cast) == "table" and cast[spec] == Cast.PathOf(a)
                    elseif kind then ok = c.story == kind
                    elseif PARTS[spec] then ok = mine(c) and hasPart(c, spec)
                    else ok = c.name:lower() == spec:lower() end
                    if ok then
                        found = take(c, spec)
                        found.hidden = true
                        log("cast: %s = %s - not drawn where it is; it is brought in and shown", spec, c.name)
                    end
                end)
            end
        end
        out[i] = found or false
        -- (nobody with that part: the parts the cats about do have - a writer sees what there is to ask for)
        if not found and PARTS[spec] and not missed then
            missed = true
            local seen = {}
            for _, c in ipairs(pool) do
                if #seen < 12 then
                    seen[#seen + 1] = string.format("%s (%s%s%s%s)", c.name, c.giver ~= "" and c.giver or "-",
                        c.story ~= "" and ("/" .. c.story) or "", c.clan and (", " .. c.clan) or "", mine(c) and "" or ", not your clan")
                end
            end
            log("cast: nobody is %s - the cats about: %s", spec, #seen > 0 and table.concat(seen, ", ") or "none")
        end
    end
    return out
end

function Cast.Init(c) WaCa, log = c.WaCa, c.log end


return Cast
