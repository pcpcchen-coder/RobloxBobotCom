--!strict
-- RoboPush Arena / CombatRules.lua
-- Pure combat geometry and validation helpers (ARCHITECTURE 4, 8; SKILLS 0).
-- Works on plain numbers so it runs outside Studio; CombatService converts
-- to/from Vector3. Horizontal plane is X/Z, up is Y.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ArenaMath = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("ArenaMath"))

local CombatRules = {}

local EPSILON = 1e-6

local function isFiniteNumber(value: any): boolean
    return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end
CombatRules.isFiniteNumber = isFiniteNumber

-- Horizontal unit vector (x, z); returns nil when the vector is ~zero.
function CombatRules.horizontalUnit(x: number, z: number): (number?, number?)
    local length = math.sqrt(x * x + z * z)
    if length < EPSILON then
        return nil, nil
    end
    return x / length, z / length
end

-- Front-arc proximity test used by Dash (GDD 6.1): target within `radius`
-- (horizontal), inside the `arcDegrees` cone around the attacker's look
-- direction and within `maxDy` height difference.
function CombatRules.isInFrontArc(
    ax: number,
    ay: number,
    az: number,
    lookX: number,
    lookZ: number,
    tx: number,
    ty: number,
    tz: number,
    radius: number,
    arcDegrees: number,
    maxDy: number
): boolean
    if math.abs(ty - ay) > maxDy then
        return false
    end
    local dx, dz = tx - ax, tz - az
    local distance = math.sqrt(dx * dx + dz * dz)
    if distance > radius then
        return false
    end
    if distance < EPSILON then
        return true -- overlapping robots always count as contact
    end
    local lx, lz = CombatRules.horizontalUnit(lookX, lookZ)
    if not lx or not lz then
        return false
    end
    local cosAngle = (dx * lx + dz * lz) / distance
    local halfArc = math.rad(arcDegrees / 2)
    return cosAngle >= math.cos(halfArc) - EPSILON
end

-- Radial proximity test used by Rocket Pop and Side Burst.
function CombatRules.isInRadius(
    ax: number,
    ay: number,
    az: number,
    tx: number,
    ty: number,
    tz: number,
    radius: number,
    maxDy: number
): boolean
    if math.abs(ty - ay) > maxDy then
        return false
    end
    local dx, dz = tx - ax, tz - az
    return dx * dx + dz * dz <= radius * radius
end

-- Knockback velocity delta pushing the target away from the source.
-- Falls back to (fallbackX, fallbackZ) when the two are overlapping.
-- Returns vx, vy, vz in studs/s; impulse = assemblyMass * delta.
function CombatRules.knockbackVelocity(
    sourceX: number,
    sourceZ: number,
    targetX: number,
    targetZ: number,
    fallbackX: number,
    fallbackZ: number,
    horizontal: number,
    vertical: number
): (number, number, number)
    local ux, uz = CombatRules.horizontalUnit(targetX - sourceX, targetZ - sourceZ)
    if not ux or not uz then
        ux, uz = CombatRules.horizontalUnit(fallbackX, fallbackZ)
    end
    if not ux or not uz then
        ux, uz = 1, 0
    end
    return (ux :: number) * horizontal, vertical, (uz :: number) * horizontal
end

-- Side Burst side selection (SKILLS 4): project the client's movement hint on
-- the character's right vector. Returns 1 (right) or -1 (left).
function CombatRules.chooseSide(rightX: number, rightZ: number, hintX: number?, hintZ: number?, defaultSide: number): number
    if hintX and hintZ then
        local dot = hintX * rightX + hintZ * rightZ
        if dot > 0.2 then
            return 1
        elseif dot < -0.2 then
            return -1
        end
    end
    return if defaultSide < 0 then -1 else 1
end

-- How an incoming impact interacts with the target's Counter Shield (SKILLS 6).
--   "rebound": ram (dash / side burst) into an active shield -> attacker bounced
--   "blocked": non-ram effect (rocket pop / ground slam shockwave, magnet pull) -> nothing happens
--   "hit":     no shield -> normal knockback
-- Shield is always evaluated before the hit (same-frame priority rule).
function CombatRules.resolveImpact(isRam: boolean, targetShieldActive: boolean): string
    if targetShieldActive then
        return if isRam then "rebound" else "blocked"
    end
    return "hit"
end

-- Validate a skill id from the network: must be a string listed as selectable.
function CombatRules.isValidSkill(config: any, skillId: any): boolean
    if type(skillId) ~= "string" or #skillId > 32 then
        return false
    end
    return table.find(config.Skills.Selectable, skillId) ~= nil
end

-- Pull velocity toward the caster (Magnet Pull): same as knockback but the
-- direction points from the target to the source. Returns vx, vy, vz.
function CombatRules.pullVelocity(
    sourceX: number,
    sourceZ: number,
    targetX: number,
    targetZ: number,
    horizontal: number,
    vertical: number
): (number, number, number)
    local ux, uz = CombatRules.horizontalUnit(sourceX - targetX, sourceZ - targetZ)
    if not ux or not uz then
        return 0, vertical, 0
    end
    return ux * horizontal, vertical, uz * horizontal
end

-- Validate a direction hint already decomposed into numbers.
function CombatRules.isValidHint(config: any, x: any, y: any, z: any): boolean
    if not (isFiniteNumber(x) and isFiniteNumber(y) and isFiniteNumber(z)) then
        return false
    end
    local magnitude = math.sqrt(x * x + y * y + z * z)
    return magnitude <= config.Net.MaxDirectionHintMagnitude
end

-- Rescue Claw eligibility (SKILLS 8): only while falling off / at the edge and
-- before the fall threshold. Returns ok, reason.
function CombatRules.canRescue(config: any, arenaSize: number, x: number, y: number, z: number): (boolean, string?)
    local arena = config.Arena
    local claw = config.Skills.rescue_claw
    if ArenaMath.isFallen(arena, y) then
        return false, "already_fallen"
    end
    if y > arena.PlatformTopY + claw.MaxHeightAboveTop then
        return false, "too_high"
    end
    if ArenaMath.edgeDistance(arena, arenaSize, x, z) > claw.TriggerEdgeDistance then
        return false, "not_at_edge"
    end
    return true, nil
end

-- ------------------------------------------------------------- rate limiter

local RateLimiter = {}
RateLimiter.__index = RateLimiter

export type RateLimiter = typeof(setmetatable(
    {} :: { rate: number, burst: number, buckets: { [number]: { tokens: number, at: number } } },
    RateLimiter
))

function RateLimiter.new(ratePerSecond: number, burst: number): RateLimiter
    return setmetatable({ rate = ratePerSecond, burst = burst, buckets = {} }, RateLimiter)
end

-- Token bucket: returns true if the request may proceed.
function RateLimiter.allow(self: RateLimiter, key: number, now: number): boolean
    local bucket = self.buckets[key]
    if not bucket then
        bucket = { tokens = self.burst, at = now }
        self.buckets[key] = bucket
    end
    bucket.tokens = math.min(self.burst, bucket.tokens + (now - bucket.at) * self.rate)
    bucket.at = now
    if bucket.tokens >= 1 then
        bucket.tokens -= 1
        return true
    end
    return false
end

function RateLimiter.forget(self: RateLimiter, key: number)
    self.buckets[key] = nil
end

CombatRules.RateLimiter = RateLimiter

return CombatRules
