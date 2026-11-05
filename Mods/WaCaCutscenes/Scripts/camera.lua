-- THE CAMERA: a camera of the cutscene's own (an engine CameraActor, spawned for it) the view switches to, and back to
-- the game's camera at the end. Shots by name - the writer never gives coordinates:
--   Wide                    the whole scene from behind your side, a little above
--   High                    from high above the scene
--   Orbit [= <who>]         slowly round the scene (or round a cat)
--   Portrait = <who>        a cat's face, from in front
--   Over = <who> > <who>    over the first cat's shoulder at the second
--   Two = <who> & <who>     both cats from the side
--   Behind = <who>          behind a cat and a little above, looking where it goes - it follows a cat that walks
--                           (library pre-work 2026-11-03: a cat walking off could only be watched from in front / aside)
--   Game                    back to the game's own camera
-- A shot cuts; "~<seconds>" after it moves there instead (Camera: Portrait = B1 ~2).
local Camera = {}

local WaCa, log, Stage, Cast
local cfg = { fov = 60, wideBack = 700, wideUp = 300, highBack = 300, highUp = 1100, orbitRadius = 650, orbitUp = 260,
              orbitSpeed = 9, portrait = 170, over = 130, twoMin = 280, behind = 260, behindUp = 70, behindAhead = 300, letterbox = 0, focus = 0, catGap = 60, foliageRadius = 30 }
local cam, before                  -- the camera actor; the view target before the cutscene
local shot                         -- { pose = fn() -> loc, look; from = {loc, rot}; blend; t }
local scene                        -- { middle, forward (yaw) } of the cutscene playing

local function v(x, y, z) return { X = x, Y = y, Z = z } end
local function add(a, b, k) k = k or 1 return v(a.X + b.X * k, a.Y + b.Y * k, a.Z + b.Z * k) end
local function dirOf(yaw) local r = math.rad(yaw) return v(math.cos(r), math.sin(r), 0) end
local function rightOf(yaw) return dirOf(yaw + 90) end

local function lookRot(from, to)
    local dx, dy, dz = to.X - from.X, to.Y - from.Y, to.Z - from.Z
    return { pitch = math.deg(math.atan(dz, math.sqrt(dx * dx + dy * dy))), Yaw = math.deg(math.atan(dy, dx)), Roll = 0 }
end

local function spawn()
    if cam and cam:IsValid() then return cam end
    local pc = Cast.Controller()
    local statics = StaticFindObject("/Script/Engine.Default__GameplayStatics")
    local class = StaticFindObject("/Script/Engine.CameraActor")
    local at = pc.PlayerCameraManager:GetCameraLocation()
    local t = { Rotation = { X = 0, Y = 0, Z = 0, W = 1 }, Translation = v(at.X, at.Y, at.Z), Scale3D = v(1, 1, 1) }
    local a = statics:BeginDeferredActorSpawnFromClass(pc, class, t, 1, nil, 0)
    statics:FinishSpawningActor(a, t, 0)
    pcall(function()
        local c = a.CameraComponent
        c.FieldOfView = cfg.fov
        -- (A FILM'S LOOK - [Camera] Letterbox / Focus, library exercise 2026-11-02, off by default: black bars at that
        -- aspect ratio - the engine's own constrained aspect - and depth of field at that f-stop, the focus kept on
        -- what each shot looks at)
        c.bConstrainAspectRatio = (cfg.letterbox or 0) > 0
        if (cfg.letterbox or 0) > 0 then c.AspectRatio = cfg.letterbox end
        if (cfg.focus or 0) > 0 then
            local pp = c.PostProcessSettings
            pp.bOverride_DepthOfFieldFstop = true
            pp.DepthOfFieldFstop = cfg.focus
            pp.bOverride_DepthOfFieldFocalDistance = true
            c.PostProcessBlendWeight = 1.0
        end
    end)
    cam = a
    return a
end

-- NOTHING IN THE WAY: the camera kept in front of what stands between it and what it looks at - like the game's own
-- camera arm (the engine's Camera trace channel; the cast's cats don't count). A camera 9 m back in the camp's
-- undergrowth showed only leaves (VM 2026-10-30).
local kismet
-- (A CAST CAT IN THE WAY - VM 2026-11-02: the cast's cats are left out of the trace, so a Portrait of Lionstar, who
-- was looking at your cat, put the camera 45 cm from your cat - inside its fur: a screen of blurred grey. A cast cat
-- other than what the shot looks at, closer than CatGap to the line between, blocks the way like a wall.)
local function catInWay(look, loc, actors)
    local sx, sy, sz = loc.X - look.X, loc.Y - look.Y, loc.Z - look.Z
    local len2 = sx * sx + sy * sy + sz * sz
    if len2 < 1 then return false end
    for _, a in ipairs(actors) do
        local ok, p = pcall(function() return a:K2_GetActorLocation() end)
        if ok and p then
            local px, py, pz = p.X - look.X, p.Y - look.Y, p.Z + 30 - look.Z
            local fromLook = math.sqrt(px * px + py * py + pz * pz)
            if fromLook > cfg.catGap then                -- (not what the shot looks at)
                local t = math.max(0, math.min(1, (px * sx + py * sy + pz * sz) / len2))
                local dx, dy, dz = px - sx * t, py - sy * t, pz - sz * t
                if math.sqrt(dx * dx + dy * dy + dz * dz) < cfg.catGap then return true end
            end
        end
    end
    return false
end
-- (PLANTS WITHOUT COLLISION - VM 2026-11-02: reeds stood between the camera and Lionstar; a trace through them hits
-- nothing on any channel, simple or complex. Foliage meshes with collision off are found by their instances' bounds
-- instead - points along the line, FoliageRadius round each; the components listed again every 30 s. 721
-- components x 4 points took 0.04 s on the VM.)
local plants, plantsAt = {}, -1000
local function plantsNow()
    if os.time() - plantsAt < 30 then return plants end
    plants, plantsAt = {}, os.time()
    for _, c in ipairs(FindAllOf("InstancedStaticMeshComponent") or {}) do
        local ok, off = pcall(function() return c:IsValid() and c:GetCollisionEnabled() == 0 end)
        if ok and off then plants[#plants + 1] = c end
    end
    return plants
end
-- (an instance's bounding SPHERE caught every candidate - the ground moss is everywhere, all 21 shots '15% clear', VM;
-- so each instance found is checked against its own box: the mesh's bounds x the instance's scale - flat moss blocks
-- only a point inside it, a reed (~20 cm wide, ~1 m tall) a point among its stems)
local meshBounds = {}
local function inPlant(c, idx, p, r)
    local key = c:GetFullName()
    local b = meshBounds[key]
    if b == nil then
        b = false
        pcall(function()
            local mb = c.StaticMesh:GetBounds()
            b = { oz = mb.Origin.Z, ex = math.max(mb.BoxExtent.X, mb.BoxExtent.Y), ez = mb.BoxExtent.Z }
        end)
        meshBounds[key] = b
    end
    if not b then return true end
    local t = {}
    if not pcall(function() c:GetInstanceTransform(idx, t, true) end) then return true end
    local at, sc = t.Translation, t.Scale3D
    local lo, hi = at.Z + (b.oz - b.ez) * sc.Z, at.Z + (b.oz + b.ez) * sc.Z
    if p.Z < lo - r or p.Z > hi + r then return false end
    local dx, dy = p.X - at.X, p.Y - at.Y
    return math.sqrt(dx * dx + dy * dy) <= b.ex * math.max(sc.X, sc.Y) + r
end
-- the fraction of the way from what is looked at to the camera that is free of plants (1 = none)
local function plantFree(look, loc)
    if (cfg.foliageRadius or 0) <= 0 then return 1 end
    local list = plantsNow()
    for _, f in ipairs({ 0.35, 0.55, 0.75, 0.95 }) do
        local p = v(look.X + (loc.X - look.X) * f, look.Y + (loc.Y - look.Y) * f, look.Z + (loc.Z - look.Z) * f)
        for _, c in ipairs(list) do
            -- (the list is up to 30 s old: a level streamed out since - a cutscene moving your cat to its place, or
            -- just walking - FREES its foliage components, and a call on one read freed memory: the game crashed in
            -- UE4SS, which a pcall can't catch - 3 crashes 2026-11-03/04, pinned by a guarded UE4SS build's traceback
            -- to this line, 40 times in one sweep. IsValid looks the pointer up without touching the object.)
            local ok, r = false, nil
            if WaCa.Live(c) then ok, r = pcall(function() return c:GetInstancesOverlappingSphere(p, cfg.foliageRadius, true) end) end
            if ok and r then
                for _, idx in ipairs(r) do
                    if type(idx) ~= "number" then pcall(function() idx = idx:get() end) end
                    local okIn, inside = pcall(inPlant, c, idx, p, cfg.foliageRadius)
                    if okIn and inside then return f - 0.2 end
                end
            end
        end
    end
    return 1
end
local function clear(look, loc)
    kismet = kismet or StaticFindObject("/Script/Engine.Default__KismetSystemLibrary")
    local hit = {}
    local ignore = Stage.Actors()
    if catInWay(look, loc, ignore) then return loc, 0 end
    local free = plantFree(look, loc)
    if free < 1 then return loc, math.max(0, free) end
    local ok, blocked = pcall(function()
        return kismet:LineTraceSingle(Cast.Pawn(), look, loc, 1, true, ignore, 0, hit, true,
            { R = 0, G = 0, B = 0, A = 0 }, { R = 0, G = 0, B = 0, A = 0 }, 0)
    end)
    if not (ok and blocked) then return loc, 1 end
    local p
    pcall(function() p = v(hit.Location.X, hit.Location.Y, hit.Location.Z) end)
    if not p then return loc, 1 end
    local dx, dy, dz = look.X - p.X, look.Y - p.Y, look.Z - p.Z
    local d = math.max(1, math.sqrt(dx * dx + dy * dy + dz * dz))
    local full = math.sqrt((loc.X - look.X) ^ 2 + (loc.Y - look.Y) ^ 2 + (loc.Z - look.Z) ^ 2)
    local pulled = v(p.X + dx / d * 30, p.Y + dy / d * 30, p.Z + dz / d * 30)
    return pulled, math.max(0, d - 30) / math.max(1, full)
end

-- a shot from around a point: the clearest of a few directions round the wanted one (the wanted one if it is clear).
-- A shot that follows its cats keeps the direction it found first (shotTurn) - a camera hopping between directions
-- from tick to tick would jump about. (A portrait's camera was pulled to 0.2 m from Lionstar's head - something stood
-- between: VM 2026-10-30.)
local CANDIDATES = {}                  -- { turn deg, rise cm }, by how far from the wanted shot (35 deg ~ 100 cm)
for _, off in ipairs({ 0, 35, -35, 70, -70, 110, -110 }) do
    for _, rise in ipairs({ 0, 150, 300 }) do CANDIDATES[#CANDIDATES + 1] = { off, rise, math.abs(off) / 35 + rise / 100 } end
end
table.sort(CANDIDATES, function(a, b) if a[3] ~= b[3] then return a[3] < b[3] end return a[1] > b[1] end)
local shotTurn, shotRise
local orbitPhase, orbitLast            -- (an orbit's start turn - its first open direction - and its last good spot)
-- (alsoSee: the heads the shot frames - a spot is only as clear as its worst sightline to them too. Library exercise
-- 2026-11-05: a Two shot by the reeds turned to a spot '100% clear' to the point between the cats, and a rock hid the
-- queen - only my cat showed, in a corner)
local function seesAll(loc, k, alsoSee)
    for _, p in ipairs(alsoSee or {}) do
        local _, kp = clear(p, loc)
        if kp < k then k = kp end
    end
    return k
end
local function bestAround(look, yaw, back, up, keep, alsoSee)
    if keep and shotTurn then
        return (clear(look, add(add(look, dirOf(yaw + shotTurn), -back), v(0, 0, 1), up + (shotRise or 0))))
    end
    -- (each direction also a little higher - rising over the roots / the bank beats pulling in to 1.7 m: follow-up (a),
    -- VM 2026-10-30 riverbank; a shot's own height first, then its own direction)
    -- (the candidates nearest the wanted shot first - a 35 deg turn before a 1.5 m rise: going up every height in the
    -- wanted direction first made a Portrait blocked by a cat in front a 3 m bird's-eye shot through the branches, VM
    -- 2026-11-02)
    local best, bestK, bestOff, bestRise
    for _, c in ipairs(CANDIDATES) do
        local off, rise = c[1], c[2]
        local want = add(add(look, dirOf(yaw + off), -back), v(0, 0, 1), up + rise)
        local loc, k = clear(look, want)
        if alsoSee and k >= 0.9 then k = seesAll(want, k, alsoSee) end
        if k >= 0.9 then best, bestK, bestOff, bestRise = loc, k, off, rise break end
        if not bestK or k > bestK + 0.05 then best, bestK, bestOff, bestRise = loc, k, off, rise end
    end
    if bestOff ~= 0 or bestRise ~= 0 or bestK < 0.9 then
        log("camera: the shot's way was blocked - turned %d deg, %d cm higher, %.0f%% of its distance clear", bestOff,
            bestRise, bestK * 100)
        -- (for the writer: no spot round the place frames this shot - a cramped place, rocks / a tree's crown about it;
        -- library exercise 2026-11-05 by the reeds - the Two shot had no view of both cats)
        if bestK < 0.6 and scene and scene.middle then
            log("camera: NOTE for the writer - no open view round %.0f %.0f for this shot (at best %.0f%%): a more open "
                .. "place for this cutscene (cutscenes.ini Place) frames it better", scene.middle.X, scene.middle.Y, bestK * 100)
        end
    end
    if keep then shotTurn, shotRise = bestOff, bestRise end
    return best
end

-- HOW OPEN A PLACE IS for a wide shot - the best clear fraction of the candidate spots round it (1 = a clear view), no
-- log: the place check before play (cutscenes.lua - library exercise 2026-11-05, a cutscene by the reeds where no spot
-- framed its cats)
function Camera.OpenView(middle, forward)
    local look = v(middle.X, middle.Y, middle.Z + 40)
    local best = 0
    for _, c in ipairs(CANDIDATES) do
        local want = add(add(look, dirOf(forward + c[1]), -cfg.wideBack), v(0, 0, 1), cfg.wideUp + c[2])
        local _, k = clear(look, want)
        if k > best then best = k end
        if best >= 0.9 then break end
    end
    return best
end

-- the shot's camera place and the point it looks at, now (moving shots change every tick)
local function resolve(name, targets, t)
    local mid, fwd = scene.middle, scene.forward
    local A, B = targets[1], targets[2]
    if name == "Wide" then
        local look = v(mid.X, mid.Y, mid.Z + 40)
        return bestAround(look, fwd, cfg.wideBack, cfg.wideUp), look
    elseif name == "High" then
        local look = v(mid.X, mid.Y, mid.Z)
        return bestAround(look, fwd, cfg.highBack, cfg.highUp), look
    elseif name == "Orbit" then
        local c = A and Stage.Head(A) or v(mid.X, mid.Y, mid.Z + 40)
        local r = A and cfg.orbitRadius * 0.45 or cfg.orbitRadius
        local up = A and cfg.orbitUp * 0.3 or cfg.orbitUp
        -- (it starts from the first open direction round the scene - a place hemmed in by rocks on half its sides began
        -- the circle 0.5 m from a rock: the reed bank, VM 2026-11-02)
        if not orbitPhase then
            orbitPhase = 0
            for _, off in ipairs({ 0, 30, -30, 60, -60, 90, -90, 120, -120, 150, -150, 180 }) do
                local _, k = clear(c, add(add(c, dirOf(fwd + 180 + off), r), v(0, 0, 1), up))
                if k >= 0.8 then orbitPhase = off break end
            end
            if orbitPhase ~= 0 then log("camera: Orbit starts %d deg round - the first open direction", orbitPhase) end
        end
        local yaw = fwd + 180 + orbitPhase + t * cfg.orbitSpeed
        -- (something in the orbit's way - a rock, a trunk: rise over it rather than pull in to it - the orbit was pulled to
        -- 0.2 m behind a cat, looking at a rock: library exercise 2026-11-02, a vigil by the reeds. The height found
        -- only ever rises within a shot - a camera bobbing up and down as it circles would be worse)
        local rise0 = shotRise or 0
        local best, bestK, bestRise
        for _, extra in ipairs({ 0, 150, 300, 450 }) do
            local rise = rise0 + extra
            local loc, k = clear(c, add(add(c, dirOf(yaw), r), v(0, 0, 1), up + rise))
            if not bestK or k > bestK + 0.05 then best, bestK, bestRise = loc, k, rise end
            if k >= 0.8 then break end
        end
        if bestRise > rise0 then
            shotRise = bestRise
            log("camera: Orbit - its way blocked, %d cm higher now (%.0f%% of its distance clear)", bestRise, bestK * 100)
        end
        -- (behind a rock even so: it waits at its last good spot till its way is open again, rather than dive in)
        if bestK < 0.5 and orbitLast then return orbitLast, c end
        if bestK >= 0.5 then orbitLast = best end
        return best, c
    elseif name == "Portrait" and A then
        local head = Stage.Head(A)
        local yaw = A:K2_GetActorRotation().Yaw
        return bestAround(head, yaw + 180, cfg.portrait, 10, true), head
    elseif name == "Over" and A and B then
        local ha, hb = Stage.Head(A), Stage.Head(B)
        local yaw = Stage.YawTo(ha, hb)
        return (clear(hb, add(add(add(ha, dirOf(yaw), -cfg.over), rightOf(yaw), 45), v(0, 0, 1), 25))), hb
    elseif name == "Behind" and A then
        local head = Stage.Head(A)
        local yaw = A:K2_GetActorRotation().Yaw
        return bestAround(head, yaw, cfg.behind, cfg.behindUp, true), add(head, dirOf(yaw), cfg.behindAhead)
    elseif name == "Two" and A and B then
        local ha, hb = Stage.Head(A), Stage.Head(B)
        local m = v((ha.X + hb.X) / 2, (ha.Y + hb.Y) / 2, (ha.Z + hb.Z) / 2)
        local d = math.sqrt((ha.X - hb.X) ^ 2 + (ha.Y - hb.Y) ^ 2)
        -- (from the side of the line the scene is watched from)
        local side = rightOf(Stage.YawTo(ha, hb))
        local back = dirOf(fwd)
        if side.X * back.X + side.Y * back.Y > 0 then side = v(-side.X, -side.Y, 0) end
        local sideYaw = math.deg(math.atan(side.Y, side.X))
        return bestAround(m, sideYaw + 180, math.max(cfg.twoMin, d * 1.3), 30, true, { ha, hb }), m
    end
    return nil
end

-- (Wide / High stand still: found once per shot - seven traces a tick for a camera that doesn't move is waste)
local STILL = { Wide = true, High = true }
local stillCache
local function place(name, targets, t)
    if STILL[name] and stillCache and stillCache.name == name then return stillCache.loc, stillCache.look end
    local loc, look = resolve(name, targets, t)
    if STILL[name] and loc then stillCache = { name = name, loc = loc, look = look } end
    return loc, look
end

local function ease(x) return x < 0.5 and 2 * x * x or 1 - (-2 * x + 2) ^ 2 / 2 end
local function lerpAngle(a, b, k)
    local d = (b - a + 540) % 360 - 180
    return a + d * k
end

-- point the camera for this tick
local function apply(dt)
    if not (shot and cam and cam:IsValid()) then return end
    shot.t = shot.t + dt
    local loc, look = place(shot.name, shot.targets, shot.t)
    if not loc then return end
    local rot = lookRot(loc, look)
    if shot.blend and shot.blend > 0 and shot.t < shot.blend and shot.from then
        local k = ease(shot.t / shot.blend)
        local f = shot.from
        loc = v(f.loc.X + (loc.X - f.loc.X) * k, f.loc.Y + (loc.Y - f.loc.Y) * k, f.loc.Z + (loc.Z - f.loc.Z) * k)
        rot = { pitch = lerpAngle(f.rot.pitch, rot.pitch, k), Yaw = lerpAngle(f.rot.Yaw, rot.Yaw, k), Roll = 0 }
    end
    pcall(function() cam:K2_SetActorLocationAndRotation(loc, rot, false, {}, true) end)
    if (cfg.focus or 0) > 0 then
        pcall(function()
            cam.CameraComponent.PostProcessSettings.DepthOfFieldFocalDistance =
                math.sqrt((look.X - loc.X) ^ 2 + (look.Y - loc.Y) ^ 2 + (look.Z - loc.Z) ^ 2)
        end)
    end
end

function Camera.Begin(middle, forward)
    scene = { middle = middle, forward = forward }
    shot = nil
end

-- a shot: name, targets (cat actors), blend seconds (0 = cut)
function Camera.Shot(name, targets, blend)
    local pc = Cast.Controller()
    if not pc then return end
    if name == "Game" then
        shot = nil
        if before and before:IsValid() then pc:SetViewTargetWithBlend(before, blend or 0, 4, 2, false) end
        log("camera: the game's camera%s", (blend or 0) > 0 and string.format(" (%.1f s)", blend) or "")
        return
    end
    stillCache, shotTurn, shotRise, orbitPhase, orbitLast = nil, nil, nil, nil, nil
    if not place(name, targets, 0) then
        -- (say what was wrong: no such shot, or too few cats for it - 'Low' read "can't frame Low with 0 cat(s)")
        local need = ({ Wide = 0, High = 0, Orbit = 0, Portrait = 1, Behind = 1, Over = 2, Two = 2 })[tostring(name)]
        if not need then
            log("camera: no shot '%s' (Wide, High, Orbit, Portrait, Over, Two, Behind, Game) - the shot stays", tostring(name))
        else
            log("camera: %s needs %d cat(s), it got %d - the shot stays", tostring(name), need, #targets)
        end
        return
    end
    local first = not (cam and cam:IsValid())
    local ok, err = pcall(spawn)
    if not ok then log("camera: no camera of its own (%s)", tostring(err)) return end
    local from
    pcall(function()
        local l, r = cam:K2_GetActorLocation(), cam:K2_GetActorRotation()
        from = { loc = v(l.X, l.Y, l.Z), rot = { pitch = r.pitch, Yaw = r.Yaw, Roll = 0 } }
    end)
    local current = pc:GetViewTarget()
    local onCam = current and current:IsValid() and current:GetAddress() == cam:GetAddress()
    if not onCam and (not before or first) then before = current end
    -- (from the game's camera: the move starts where the game's camera is)
    if not onCam then
        pcall(function()
            local l, r = pc.PlayerCameraManager:GetCameraLocation(), pc.PlayerCameraManager:GetCameraRotation()
            from = { loc = v(l.X, l.Y, l.Z), rot = { pitch = r.pitch, Yaw = r.Yaw, Roll = 0 } }
        end)
    end
    shot = { name = name, targets = targets, blend = blend or 0, t = 0, from = from }
    if not onCam then
        if (blend or 0) > 0 and from then pcall(function() cam:K2_SetActorLocationAndRotation(from.loc, from.rot, false, {}, true) end) end
        apply(0)
        pc:SetViewTargetWithBlend(cam, 0, 0, 0, false)
    else
        apply(0)
    end
    local names = {}
    for _, a in ipairs(targets) do names[#names + 1] = (pcall(function() return a:GetFName() end)) and (Cast.NameOf(a) or a:GetFName():ToString()) or "?" end
    local far = ""
    local okFar, errFar = pcall(function()
        local loc, look = place(name, targets, 0)
        far = string.format(", %.1f m from what it looks at", math.sqrt((loc.X - look.X) ^ 2 + (loc.Y - look.Y) ^ 2 + (loc.Z - look.Z) ^ 2) / 100)
    end)
    if not okFar then far = " (distance: " .. tostring(errFar) .. ")" end
    log("camera: %s%s%s%s", name, #names > 0 and (" - " .. table.concat(names, ", ")) or "",
        (blend or 0) > 0 and string.format(" (moving there %.1f s)", blend) or "", far)
end

function Camera.Tick(dt) pcall(apply, dt) end

-- back to the game's camera, the cutscene's own gone
function Camera.End()
    local pc = Cast.Controller()
    shot, scene = nil, nil
    if pc and before and before:IsValid() then pcall(function() pc:SetViewTargetWithBlend(before, 0, 0, 0, false) end) end
    if cam and cam:IsValid() then pcall(function() cam:K2_DestroyActor() end) end
    cam, before = nil, nil
end

function Camera.Path() return cam and cam:IsValid() and (cam:GetFullName():gsub("^%S+ ", "")) or nil end

function Camera.Init(c)
    WaCa, log, Stage, Cast = c.WaCa, c.log, c.Stage, c.Cast
    for k, val in pairs(c.camera or {}) do if cfg[k] ~= nil then cfg[k] = tonumber(val) or cfg[k] end end
end

return Camera
