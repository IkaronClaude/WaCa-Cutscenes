-- THE CAMERA: a camera of the cutscene's own (an engine CameraActor, spawned for it) the view switches to, and back to
-- the game's camera at the end. Shots by name - the writer never gives coordinates:
--   Wide                    the whole scene from behind your side, a little above
--   High                    from high above the scene
--   Orbit [= <who>]         slowly round the scene (or round a cat)
--   Portrait = <who>        a cat's face, from in front
--   Over = <who> > <who>    over the first cat's shoulder at the second
--   Two = <who> & <who>     both cats from the side
--   Game                    back to the game's own camera
-- A shot cuts; "~<seconds>" after it moves there instead (Camera: Portrait = B1 ~2).
local Camera = {}

local WaCa, log, Stage, Cast
local cfg = { fov = 60, wideBack = 700, wideUp = 300, highBack = 300, highUp = 1100, orbitRadius = 650, orbitUp = 260,
              orbitSpeed = 9, portrait = 170, over = 130, twoMin = 280, seenCheck = 1.0, waterClear = 60 }
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
        c.bConstrainAspectRatio = false
    end)
    cam = a
    return a
end

-- NOTHING IN THE WAY: the camera kept in front of what stands between it and what it looks at - like the game's own
-- camera arm (the engine's Camera trace channel; the cast's cats don't count). A camera 9 m back in the camp's
-- undergrowth showed only leaves (VM 2026-10-30).
local kismet
local function clear(look, loc)
    kismet = kismet or StaticFindObject("/Script/Engine.Default__KismetSystemLibrary")
    local hit = {}
    local ignore = Stage.Actors()
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
local shotTurn, shotRise
-- (a shot whose cats weren't on screen after it settled: turned round further - Camera's seen check)
local forcedTurn = nil
local function bestAround(look, yaw, back, up, keep)
    yaw = yaw + (forcedTurn or 0)
    if keep and shotTurn then
        return (clear(look, add(add(look, dirOf(yaw + shotTurn), -back), v(0, 0, 1), up + (shotRise or 0))))
    end
    -- (each direction also a little higher - rising over the roots / the bank beats pulling in to 1.7 m: follow-up (a),
    -- VM 2026-10-30 riverbank; a shot's own height first, then its own direction)
    local best, bestK, bestOff, bestRise
    for _, off in ipairs({ 0, 35, -35, 70, -70, 110, -110 }) do
        for _, rise in ipairs({ 0, 150, 300 }) do
            local want = add(add(look, dirOf(yaw + off), -back), v(0, 0, 1), up + rise)
            local loc, k = clear(look, want)
            if k >= 0.9 then best, bestK, bestOff, bestRise = loc, k, off, rise break end
            if not bestK or k > bestK + 0.05 then best, bestK, bestOff, bestRise = loc, k, off, rise end
        end
        if bestK and bestK >= 0.9 then break end
    end
    if bestOff ~= 0 or bestRise ~= 0 or bestK < 0.9 then
        log("camera: the shot's way was blocked - turned %d deg, %d cm higher, %.0f%% of its distance clear", bestOff,
            bestRise, bestK * 100)
    end
    if keep then shotTurn, shotRise = bestOff, bestRise end
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
        local yaw = fwd + 180 + t * cfg.orbitSpeed
        local r = A and cfg.orbitRadius * 0.45 or cfg.orbitRadius
        return (clear(c, add(add(c, dirOf(yaw), r), v(0, 0, 1), A and cfg.orbitUp * 0.3 or cfg.orbitUp))), c
    elseif name == "Portrait" and A then
        local head = Stage.Head(A)
        local yaw = A:K2_GetActorRotation().Yaw
        return bestAround(head, yaw + 180, cfg.portrait, 10, true), head
    elseif name == "Over" and A and B then
        local ha, hb = Stage.Head(A), Stage.Head(B)
        local yaw = Stage.YawTo(ha, hb)
        return (clear(hb, add(add(add(ha, dirOf(yaw), -cfg.over), rightOf(yaw), 45), v(0, 0, 1), 25))), hb
    elseif name == "Two" and A and B then
        local ha, hb = Stage.Head(A), Stage.Head(B)
        local m = v((ha.X + hb.X) / 2, (ha.Y + hb.Y) / 2, (ha.Z + hb.Z) / 2)
        local d = math.sqrt((ha.X - hb.X) ^ 2 + (ha.Y - hb.Y) ^ 2)
        -- (from the side of the line the scene is watched from)
        local side = rightOf(Stage.YawTo(ha, hb))
        local back = dirOf(fwd)
        if side.X * back.X + side.Y * back.Y > 0 then side = v(-side.X, -side.Y, 0) end
        local sideYaw = math.deg(math.atan(side.Y, side.X))
        return bestAround(m, sideYaw + 180, math.max(cfg.twoMin, d * 1.3), 30, true), m
    end
    return nil
end

-- (Wide / High stand still: found once per shot - seven traces a tick for a camera that doesn't move is waste)
local STILL = { Wide = true, High = true }
local stillCache
-- ABOVE THE WATER: a camera at or under a water surface sees a flat pale plane (the river edge's Two shot, VM
-- 2026-11-01 - water has no collision for the sight trace). The water planes answer object queries (made so at the
-- cutscene's start - as WaCa Hunting's wading does); a shot over water is held WaterClear cm above its surface.
local function waterUnder(loc)
    kismet = kismet or StaticFindObject("/Script/Engine.Default__KismetSystemLibrary")
    local hit = {}
    local ok, yes = pcall(function()
        return kismet:LineTraceSingleForObjects(Cast.Pawn(), v(loc.X, loc.Y, loc.Z + 800), v(loc.X, loc.Y, loc.Z - 100), { 0 }, true,
            Stage.Actors(), 0, hit, true, { R = 0, G = 0, B = 0, A = 0 }, { R = 0, G = 0, B = 0, A = 0 }, 0)
    end)
    if not (ok and yes) then return nil end
    local name = WaCa.HitMaterialName and WaCa.HitMaterialName(hit) or nil
    if not (name and name:find("^MI_WC_Water")) then return nil end
    local z
    pcall(function() z = hit.ImpactPoint.Z end)
    return z
end
local function aboveWater(loc)
    if not loc or cfg.waterClear <= 0 then return loc end
    local z = waterUnder(loc)
    if z and loc.Z < z + cfg.waterClear then
        if not (shot and shot.overWater) then
            if shot then shot.overWater = true end
            log("camera: over water - held %.0f cm above its surface (was %.0f cm)", cfg.waterClear, loc.Z - z)
        end
        return v(loc.X, loc.Y, z + cfg.waterClear)
    end
    return loc
end
function Camera.ReadyWater()
    local n = 0
    for _, c in ipairs(FindAllOf("StaticMeshComponent") or {}) do
        pcall(function()
            local m = c:GetMaterial(0)
            if m and m:IsValid() and m:GetFName():ToString():find("^MI_WC_Water") then
                if c:GetCollisionEnabled() == 0 then
                    c:SetCollisionResponseToAllChannels(0)
                    c:SetCollisionEnabled(1)
                end
                n = n + 1
            end
        end)
    end
    return n
end

local function place(name, targets, t)
    if STILL[name] and stillCache and stillCache.name == name then return stillCache.loc, stillCache.look end
    local loc, look = resolve(name, targets, t)
    loc = aboveWater(loc)
    if STILL[name] and loc then stillCache = { name = name, loc = loc, look = look } end
    return loc, look
end

local AROUND = { Wide = true, High = true, Portrait = true, Two = true }
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
    -- SEEN CHECK: a moment after the shot settles, is any of its cats on screen? Scenery the sight trace can't see
    -- (a rock without collision on the Camera channel) hid both cats of a Two shot at the camp's river edge (VM
    -- 2026-11-01, 'blocked' never logged) - then the shot turns round (90 deg, at most twice)
    -- (the shots that look round for a clear way - Wide, High, Portrait, Two; Over / Orbit keep their geometry)
    if cfg.seenCheck > 0 and AROUND[shot.name] and not shot.seen and #shot.targets > 0 and shot.t >= (shot.blend or 0) + cfg.seenCheck then
        shot.seen = true
        local any = false
        for _, a in ipairs(shot.targets) do
            local ok, r = pcall(function() return a:WasRecentlyRendered(cfg.seenCheck) end)
            if not ok or r then any = true end
        end
        if not any and (shot.turns or 0) < 2 then
            shot.turns = (shot.turns or 0) + 1
            forcedTurn = (forcedTurn or 0) + 90
            stillCache, shotTurn, shotRise = nil, nil, nil
            shot.seen = false
            shot.t = shot.blend or 0
            log("camera: %s - its cats weren't on screen (something in the way the trace can't see?) - turned %d deg",
                shot.name, forcedTurn)
        end
    end
end

function Camera.Begin(middle, forward)
    scene = { middle = middle, forward = forward }
    shot = nil
    if cfg.waterClear > 0 then pcall(Camera.ReadyWater) end
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
    stillCache, shotTurn, shotRise, forcedTurn = nil, nil, nil, nil
    if not place(name, targets, 0) then
        log("camera: can't frame %s with %d cat(s) - the shot stays", tostring(name), #targets)
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

function Camera.Init(c)
    WaCa, log, Stage, Cast = c.WaCa, c.log, c.Stage, c.Cast
    for k, val in pairs(c.camera or {}) do if cfg[k] ~= nil then cfg[k] = tonumber(val) or cfg[k] end end
end

return Camera
