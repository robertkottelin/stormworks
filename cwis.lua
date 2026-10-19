-- ============================================================
-- Stormworks CIWS - Full Automatic System
-- Features:
--   - Search radar (wide FOV) + Track radar (narrow FOV) + Upward radar
--   - Automatic Search → Slew → Track
--   - Closest target priority (all 8 targets)
--   - Radar → World conversion (full orientation)
--   - Alpha-beta filter + ballistic lead
--   - Ownship velocity compensation
--   - Self-fire angle limit
-- ============================================================

local PI  = math.pi
local TAU = PI * 2
local DT  = 1/60

-- ===================== CONFIG =====================
local PROJECTILE_SPEED = 800          -- m/s (change to your gun)
local MAX_LEAD_TIME    = 8
local FILTER_ALPHA     = 0.35
local FILTER_BETA      = 0.12
local MIN_RANGE        = 50
local MAX_RANGE        = 15000
local MIN_FIRE_RANGE   = 40

-- Self-fire angle limits (turns). Adjust to your turret position.
local SAFE_AZ_MIN = -0.30
local SAFE_AZ_MAX =  0.30
-- ==================================================

-- Track state
local track = {
    valid = false,
    x = 0, y = 0, z = 0,
    vx = 0, vy = 0, vz = 0,
    age = 0
}

-- Mode: 0 = search/sweep, 1 = slew, 2 = track
local mode = 0

function onTick()
    -- ================= INPUTS =================
    -- Track radar (narrow FOV, on turret) - composite channels 1-32
    -- Search radar found / az / el
    local searchFound = input.getBool(2)
    local searchAz    = input.getNumber(15)
    local searchEl    = input.getNumber(16)

    -- Upward radar found / az / el
    local upFound = input.getBool(3)
    local upAz    = input.getNumber(18)
    local upEl    = input.getNumber(19)

    -- Physics sensor
    local posX, posY, posZ = input.getNumber(5), input.getNumber(6), input.getNumber(7)
    local eulX, eulY, eulZ = input.getNumber(8), input.getNumber(9), input.getNumber(10)
    local ownVx, ownVy, ownVz = input.getNumber(11), input.getNumber(12), input.getNumber(13)

    -- Optional sweep time (or use a counter)
    local time = input.getNumber(20) or 0

    -- ========== CLOSEST TARGET FROM TRACK RADAR ==========
    local bestDist = math.huge
    local bestAz, bestEl = 0, 0
    local trackFound = false

    for i = 0, 7 do
        local base = i * 4
        local d  = input.getNumber(1 + base)
        local az = input.getNumber(2 + base)
        local el = input.getNumber(3 + base)

        if d > MIN_RANGE and d < MAX_RANGE and d < bestDist then
            bestDist = d
            bestAz = az
            bestEl = el
            trackFound = true
        end
    end

    local dist, az, el = bestDist, bestAz, bestEl

    -- ========== MODE SELECTION (priority) ==========
    local slewAz, slewEl = 0, 0

    if trackFound then
        mode = 2
    elseif upFound then
        mode = 1
        slewAz, slewEl = upAz, upEl
    elseif searchFound then
        mode = 1
        slewAz, slewEl = searchAz, searchEl
    else
        mode = 0
    end

    -- ========== TRACK MODE: Filter + Lead ==========
    local aimAz, aimEl = 0, 0
    local canFire = false

    if mode == 2 and trackFound then
        -- Radar local vector
        local azR = az * TAU
        local elR = el * TAU
        local cosEl = math.cos(elR)
        local localX = dist * math.sin(azR) * cosEl
        local localY = dist * math.cos(azR) * cosEl
        local localZ = dist * math.sin(elR)

        -- Orientation matrix from physics sensor
        local cx, sx = math.cos(eulX), math.sin(eulX)
        local cy, sy = math.cos(eulY), math.sin(eulY)
        local cz, sz = math.cos(eulZ), math.sin(eulZ)

        local right = {x = cx*cz,             y = sx*sy - cx*cy*sz, z = cy*sx + cx*sz*sy}
        local fwd   = {x = sx,                y = cz*cy,            z = -cz*sy}
        local up    = {x = -cz*sx,            y = cx*sy + cy*sx*sz, z = cx*cy - sx*sz*sy}

        -- World position
        local worldX = posX + right.x*localX + fwd.x*localY + up.x*localZ
        local worldY = posY + right.y*localX + fwd.y*localY + up.y*localZ
        local worldZ = posZ + right.z*localX + fwd.z*localY + up.z*localZ

        -- Alpha-beta filter
        if not track.valid or track.age > 15 then
            track.x, track.y, track.z = worldX, worldY, worldZ
            track.vx, track.vy, track.vz = 0, 0, 0
            track.valid = true
            track.age = 0
        else
            local predX = track.x + track.vx * DT
            local predY = track.y + track.vy * DT
            local predZ = track.z + track.vz * DT

            local rx = worldX - predX
            local ry = worldY - predY
            local rz = worldZ - predZ

            track.x = predX + FILTER_ALPHA * rx
            track.y = predY + FILTER_ALPHA * ry
            track.z = predZ + FILTER_ALPHA * rz

            track.vx = track.vx + (FILTER_BETA / DT) * rx
            track.vy = track.vy + (FILTER_BETA / DT) * ry
            track.vz = track.vz + (FILTER_BETA / DT) * rz
            track.age = 0
        end

        -- Relative velocity (target - ownship)
        local relVx = track.vx - ownVx
        local relVy = track.vy - ownVy
        local relVz = track.vz - ownVz

        -- Iterative lead
        local tx = track.x - posX
        local ty = track.y - posY
        local tz = track.z - posZ
        local t = math.sqrt(tx*tx + ty*ty + tz*tz) / PROJECTILE_SPEED

        for i = 1, 4 do
            local leadX = tx + relVx * t
            local leadY = ty + relVy * t
            local leadZ = tz + relVz * t
            local distLead = math.sqrt(leadX*leadX + leadY*leadY + leadZ*leadZ)
            t = distLead / PROJECTILE_SPEED
            if t > MAX_LEAD_TIME then t = MAX_LEAD_TIME end
        end

        local aimX = track.x + relVx * t
        local aimY = track.y + relVy * t
        local aimZ = track.z + relVz * t

        -- Convert aim point to local angles
        local dx = aimX - posX
        local dy = aimY - posY
        local dz = aimZ - posZ

        local localAimX = dx*right.x + dy*right.y + dz*right.z
        local localAimY = dx*fwd.x   + dy*fwd.y   + dz*fwd.z
        local localAimZ = dx*up.x    + dy*up.y    + dz*up.z

        local aimDist = math.sqrt(localAimX^2 + localAimY^2 + localAimZ^2)
        aimAz = math.atan(localAimX, localAimY) / TAU
        aimEl = math.asin(localAimZ / math.max(aimDist, 0.001)) / TAU

        -- Self-fire angle limit + min range
        local rangeToTarget = math.sqrt(tx*tx + ty*ty + tz*tz)
        canFire = (aimAz >= SAFE_AZ_MIN) and (aimAz <= SAFE_AZ_MAX) and (rangeToTarget >= MIN_FIRE_RANGE)
    else
        track.age = track.age + 1
        if track.age > 30 then track.valid = false end
    end

    -- ========== OUTPUT ==========
    if mode == 2 then
        output.setNumber(1, aimAz)
        output.setNumber(2, aimEl)
        output.setBool(1, canFire)
    elseif mode == 1 then
        -- Slew toward search or upward radar
        output.setNumber(1, slewAz)
        output.setNumber(2, slewEl)
        output.setBool(1, false)
    else
        -- Idle sweep
        local sweep = math.sin(time * 0.4) * 0.4
        output.setNumber(1, sweep)
        output.setNumber(2, 0.05)
        output.setBool(1, false)
    end

    -- Extra debug outputs
    output.setNumber(3, mode)
    output.setNumber(4, bestDist)
    output.setBool(2, track.valid)
end
