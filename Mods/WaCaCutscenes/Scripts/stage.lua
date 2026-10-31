-- THE STAGE: the cast's cats set on their marks, walked, turned, posed - and put back where they were at the end.
-- Three kinds of cat, moved each its own way:
--   the camp's named cats (quest actors - placed scenery with a body): moved a step each tick on the ground, playing
--     the game's own walk animation (their body's single-node animation; back to their animation blueprint after);
--   the game's walking cats (AI characters): their AI held while cast (it would walk them off), moved the same way;
--   your cat: walked by its own movement (forced input - your keys are off during a cutscene), so its own animation
--     plays.
local Stage = {}

local WaCa, log, Cast
local cfg = { speed = 120, reach = 12 }
local WALK = "/Game/Art/Characters/CatMaster/Animations/A_CatMaster_Walk_1.A_CatMaster_Walk_1"
local MONTAGES = "/Game/Art/Characters/CatMaster/Animations/"

-- the poses a writer names (the game's own montages), or any montage's object path
local POSES = {
    Sit = "Montages/AM_CatMaster_SimpleSit", Lie = "Montages/AM_Interact_Sleep_1", Sleep = "Montages/AM_Interact_Sleep_2",
    Eat = "Montages/AM_Interact_Bite_1", Sniff = "Montages/AM_Interact_Sniffing", Meow = "Montages/AM_Meow",
    Play = "Montages/AM_Interact_Play", Dig = "Montages/AM_Interact_Dig", Groom = "Montages/AM_Interact_Sharpen",
    Win = "Montages/AM_Win", Hit = "Montages/AM_Hit_1",
    Hiss = "Combat/TrickStance/Montages/AM_TC_Loud_Hissing", Growl = "Combat/DefensiveStance/Montages/AM_SC_Warning_Growl",
    TailUp = "Combat/OffensiveStance/Montages/AM_CatMaster_Tail_Pose",
}
Stage.POSES = POSES

local actors = {}       -- path -> { name, kind = "quest"|"walker"|"player", from = {loc, rot}, lift, walk = {...} }

local function copyLoc(v) return { X = v.X, Y = v.Y, Z = v.Z } end
local function copyRot(r) return { pitch = r.pitch, Yaw = r.Yaw, Roll = r.Roll } end   -- (FRotator: lower-case pitch here)

local function bodyOf(a)
    local e = actors[Cast.PathOf(a)]
    local ok, m = pcall(function()
        if e and e.kind == "quest" then return a.SkeletalMeshComponent end
        return a.Mesh
    end)
    return ok and m or nil
end

-- THE GROUND under a point: terrain and rocks only (world static), traced from knee height down - from higher up it
-- found branches overhead (Clan Life's walkers, VM 2026-10-29)
local kismet

-- WATER: the game has no swimming - water is a floor type of its physical material (Water / DeepWater; WaCa Hunting's
-- wading reads the same). The hit's own material first, else its mesh's. (A meeting fitted to "open ground" stood in
-- the river: the riverbed is ground to a trace - VM 2026-10-30.)
local FLOOR_DEEP, FLOOR_WATER = 3, 4          -- EAdventurePhysicalFloorType
local physClass
local function floorType(hit)
    physClass = physClass or StaticFindObject("/Script/SwtAdventure.AdventurePhysicalMaterial")
    if not physClass then return nil end
    local function deref(x)
        if x and tostring(x):match("^FWeakObjectPtr") then return x:Get() end
        return x
    end
    local function typeOf(pm)
        pm = deref(pm)
        if pm and pm:IsValid() and pm:IsA(physClass) then return pm.FloorType end
    end
    local ok, t = pcall(typeOf, hit.PhysMaterial)
    if ok and t then return t end
    ok, t = pcall(function()
        local comp = deref(hit.Component)
        return comp and comp:IsValid() and typeOf(comp:GetMaterial(0):GetPhysicalMaterial()) or nil
    end)
    return ok and t or nil
end

-- the ground's height at x, y (traced from up above z, default 50 cm) and whether it is water
function Stage.GroundAt(a, x, y, z, up)
    kismet = kismet or StaticFindObject("/Script/Engine.Default__KismetSystemLibrary")
    local hit = {}
    local ok, yes = pcall(function()
        return kismet:LineTraceSingleForObjects(a, { X = x, Y = y, Z = z + (up or 50) }, { X = x, Y = y, Z = z - 400 }, { 0 },
            false, { a }, 0, hit, true, { R = 0, G = 0, B = 0, A = 0 }, { R = 0, G = 0, B = 0, A = 0 }, 0)
    end)
    if not (ok and yes) then return nil end
    local gz
    pcall(function() gz = hit.ImpactPoint.Z end)
    if not gz then return nil end
    local t = floorType(hit)
    return gz, t == FLOOR_WATER or t == FLOOR_DEEP
end

-- something solid of the world (terrain, a rock, a den wall, a tree) between two points?
function Stage.Blocked(a, from, to)
    kismet = kismet or StaticFindObject("/Script/Engine.Default__KismetSystemLibrary")
    local hit = {}
    local ok, yes = pcall(function()
        return kismet:LineTraceSingleForObjects(a, from, to, { 0 }, false, { a }, 0, hit, true,
            { R = 0, G = 0, B = 0, A = 0 }, { R = 0, G = 0, B = 0, A = 0 }, 0)
    end)
    return ok and yes == true
end

-- a cat's height above the ground where it stands (its feet or its capsule's middle - whatever its actor's origin is)
local function liftOf(e, a)
    if e.lift == nil then
        local q = a:K2_GetActorLocation()
        local g = Stage.GroundAt(a, q.X, q.Y, q.Z)
        e.lift = g and (q.Z - g) or false
    end
    return e.lift
end

-- where a cat stands at x, y: on the ground there (near height z), at its own height above it
function Stage.Feet(a, x, y, z)
    local e = actors[Cast.PathOf(a)]
    local lift = e and liftOf(e, a)
    local g = Stage.GroundAt(a, x, y, z)
    if g and lift then return g + lift end
    return z
end

local function playWalk(a, on)
    local e = actors[Cast.PathOf(a)]
    if not (e and e.kind ~= "player") then return end
    pcall(function()
        local mesh = bodyOf(a)
        if on then
            local anim = WaCa.LoadAsset(WALK)
            if anim then mesh:PlayAnimation(anim, true) end
        else
            mesh:SetAnimationMode(0, true)                 -- (its own animation blueprint again)
        end
    end)
end

-- an AI cat's brain and movement held (it would walk off) / let go
local function holdAI(a, on)
    pcall(function()
        local ctl = a.Controller
        if not (ctl and ctl:IsValid()) then return end
        if on then
            ctl:StopMovement()
            ctl.BrainComponent:StopLogic("WaCa cutscene")
        else
            ctl.BrainComponent:RestartLogic()
        end
    end)
    pcall(function()
        local m = a.CharacterMovement
        if on then m:StopMovementImmediately() m:DisableMovement() else m:SetMovementMode(1, 0) end
    end)
end

-- take a cat into the cutscene (remember where it was; hold its AI)
function Stage.Take(a, name, kind, hidden)
    local path = Cast.PathOf(a)
    if actors[path] then return end
    actors[path] = { name = name, kind = kind, hidden = hidden,
                     from = { loc = copyLoc(a:K2_GetActorLocation()), rot = copyRot(a:K2_GetActorRotation()) } }
    -- (a cat the game wasn't drawing: shown for the cutscene, hidden again at its end)
    if hidden then pcall(function() a.SkeletalMeshComponent:SetVisibility(true, true) end) end
    liftOf(actors[path], a)
    if kind == "walker" then holdAI(a, true) end
end

local function yawTo(from, to) return math.deg(math.atan(to.Y - from.Y, to.X - from.X)) end
Stage.YawTo = yawTo

-- set down on a spot now, facing yaw
function Stage.Place(a, spot, yaw)
    local z = Stage.Feet(a, spot.X, spot.Y, spot.Z)
    pcall(function() a:K2_SetActorLocationAndRotation({ X = spot.X, Y = spot.Y, Z = z }, { pitch = 0, Yaw = yaw or 0, Roll = 0 }, false, {}, true) end)
end

function Stage.Turn(a, yaw)
    pcall(function() a:K2_SetActorRotation({ pitch = 0, Yaw = yaw, Roll = 0 }, true) end)
end

-- walk to a spot (then face yaw); onArrive() when there
function Stage.Walk(a, spot, yaw, onArrive)
    local e = actors[Cast.PathOf(a)]
    if not e then return onArrive and onArrive() end
    e.walk = { to = copyLoc(spot), yaw = yaw, onArrive = onArrive, since = 0 }
    if e.kind ~= "player" then playWalk(a, true) end
end

-- the cast's cats (actors) - e.g. for traces that should look past them
function Stage.Actors()
    local out = {}
    for path in pairs(actors) do
        local a = StaticFindObject(path)
        if a and a:IsValid() then out[#out + 1] = a end
    end
    return out
end

function Stage.Walking(a)
    local e = actors[Cast.PathOf(a)]
    return e ~= nil and e.walk ~= nil
end

local function arrive(a, e)
    local w = e.walk
    e.walk = nil
    if e.kind ~= "player" then playWalk(a, false) end
    if w.yaw then Stage.Turn(a, w.yaw) end
    if w.onArrive then pcall(w.onArrive) end
end

-- one tick of every walk (dt game seconds)
function Stage.Tick(dt)
    for path, e in pairs(actors) do
        local w = e.walk
        local a = w and StaticFindObject(path)
        if w and not (a and a:IsValid()) then
            e.walk = nil
        elseif w then
            w.since = w.since + dt
            local q = a:K2_GetActorLocation()
            local dx, dy = w.to.X - q.X, w.to.Y - q.Y
            local dist = math.sqrt(dx * dx + dy * dy)
            if e.kind == "player" then
                -- (its own movement: input forced past the cutscene's ignore; far too long (blocked) -> set down)
                if dist <= 40 then
                    arrive(a, e)
                elseif w.since > dist / 60 + 8 then
                    Stage.Place(a, w.to, w.yaw)
                    log("stage: %s didn't get there in time - set down", e.name)
                    arrive(a, e)
                else
                    pcall(function() a:AddMovementInput({ X = dx / dist, Y = dy / dist, Z = 0 }, 0.6, true) end)
                end
            else
                local step = cfg.speed * dt
                if dist <= math.max(step, cfg.reach) then
                    Stage.Place(a, w.to, w.yaw)
                    arrive(a, e)
                elseif step > 0 then
                    local f = step / dist
                    local nx, ny = q.X + dx * f, q.Y + dy * f
                    local nz = Stage.Feet(a, nx, ny, q.Z)
                    pcall(function()
                        a:K2_SetActorLocationAndRotation({ X = nx, Y = ny, Z = nz }, { pitch = 0, Yaw = math.deg(math.atan(dy, dx)), Roll = 0 },
                            false, {}, true)
                    end)
                end
            end
        end
    end
end

-- a pose: a writer's name (Sit, Hiss ...) or a montage path; Stop / Idle ends one
local meshClass
function Stage.Pose(a, pose)
    if pose == "Stop" or pose == "Idle" then
        if pcall(function() a:StopAnimMontage(nil) end) then return true end
        return pcall(function() bodyOf(a):GetAnimInstance():Montage_Stop(0.25, nil) end)
    end
    local path = POSES[pose] and (MONTAGES .. POSES[pose]) or pose
    if not path:find("%.") then path = path .. "." .. path:match("([^/]+)$") end
    local ok, m = pcall(WaCa.LoadAsset, path)
    if not (ok and m and m:IsValid()) then
        log("stage: no pose %s (%s)", tostring(pose), path)
        return false
    end
    -- (it may still walk: the body's walk animation stops for the montage)
    local e = actors[Cast.PathOf(a)]
    if e and e.kind ~= "player" then playWalk(a, false) end
    if pcall(function() a:PlayAnimMontage(m, 1.0, FName("None")) end) then return true end
    meshClass = meshClass or StaticFindObject("/Script/Engine.SkeletalMeshComponent")
    return pcall(function() a:GetComponentByClass(meshClass):GetAnimInstance():Montage_Play(m, 1.0, 0, 0.0, true) end)
end

-- a cat's head: its body's head bone when it has one (cat skeletons name it differently - tried in turn), else a little
-- above its middle
local HEAD = { "head", "Head", "Bip01-Head", "neck", "Neck" }
local headBone = {}
function Stage.Head(a)
    local mesh = bodyOf(a)
    local path = Cast.PathOf(a)
    if mesh and headBone[path] ~= false then
        for _, b in ipairs(headBone[path] and { headBone[path] } or HEAD) do
            local ok, p = pcall(function() return mesh:GetSocketLocation(FName(b)) end)
            if ok and p and (p.X ~= 0 or p.Y ~= 0 or p.Z ~= 0) then
                if not headBone[path] then
                    headBone[path] = b
                    log("stage: %s - head bone %s", (actors[path] and actors[path].name) or path:match("[^.:]+$"), b)
                end
                return copyLoc(p)
            end
        end
        headBone[path] = false
    end
    local q = a:K2_GetActorLocation()
    local e = actors[path]
    local lift = e and e.lift or 0
    return { X = q.X, Y = q.Y, Z = q.Z - (lift or 0) + 45 }
end

-- everyone back where they were (your cat stays where the cutscene left it unless putPlayerBack)
function Stage.Release(putPlayerBack)
    local n = 0
    for path, e in pairs(actors) do
        local a = StaticFindObject(path)
        if a and a:IsValid() then
            Stage.Pose(a, "Stop")
            if e.kind ~= "player" then playWalk(a, false) end
            if e.kind ~= "player" or putPlayerBack then
                pcall(function() a:K2_SetActorLocationAndRotation(e.from.loc, e.from.rot, false, {}, true) end)
                n = n + 1
            end
            if e.kind == "walker" then holdAI(a, false) end
            if e.hidden then pcall(function() a.SkeletalMeshComponent:SetVisibility(false, true) end) end
        end
    end
    actors = {}
    return n
end

function Stage.Init(c)
    WaCa, log, Cast = c.WaCa, c.log, c.Cast
    cfg.speed = c.walkSpeed or cfg.speed
end

return Stage
