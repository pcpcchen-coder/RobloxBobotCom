--!strict
-- RoboPush Arena / ArenaMath.lua
-- Pure arena geometry and shrink schedule (GDD 3). No Roblox APIs.

local ArenaMath = {}

type ArenaConfig = {
    InitialSize: number,
    CenterX: number,
    CenterZ: number,
    PlatformTopY: number,
    FallHeight: number,
    ShrinkWarning: number,
    ShrinkSteps: { { Time: number, Size: number } },
    SuddenDeathSize: number,
    SpawnOffsetMax: number,
    SpawnOffsetDivisor: number,
    SpawnHeightAboveTop: number,
}

-- Platform size that should be in effect `elapsed` seconds into regulation.
function ArenaMath.sizeAtElapsed(arena: ArenaConfig, elapsed: number): number
    local size = arena.InitialSize
    for _, step in arena.ShrinkSteps do
        if elapsed >= step.Time then
            size = step.Size
        end
    end
    return size
end

-- Symmetric spawn offset for the current size: min(12, size / 4) (GDD 3.2).
function ArenaMath.spawnOffset(arena: ArenaConfig, size: number): number
    return math.min(arena.SpawnOffsetMax, size / arena.SpawnOffsetDivisor)
end

-- Spawn position for slot 1 (negative X) or slot 2 (positive X). Returns x, y, z.
function ArenaMath.spawnPosition(arena: ArenaConfig, size: number, slot: number): (number, number, number)
    local sign = if slot == 1 then -1 else 1
    local offset = ArenaMath.spawnOffset(arena, size)
    return arena.CenterX + sign * offset, arena.PlatformTopY + arena.SpawnHeightAboveTop, arena.CenterZ
end

-- True when a root part height counts as a fall (strictly below FallHeight).
function ArenaMath.isFallen(arena: ArenaConfig, rootY: number): boolean
    return rootY < arena.FallHeight
end

-- True when (x, z) is over the current platform footprint.
function ArenaMath.isOverPlatform(arena: ArenaConfig, size: number, x: number, z: number): boolean
    local half = size / 2
    return math.abs(x - arena.CenterX) <= half and math.abs(z - arena.CenterZ) <= half
end

-- Horizontal distance from (x, z) to the nearest platform edge: positive when
-- over the platform, negative when outside it.
function ArenaMath.edgeDistance(arena: ArenaConfig, size: number, x: number, z: number): number
    local half = size / 2
    local dx = half - math.abs(x - arena.CenterX)
    local dz = half - math.abs(z - arena.CenterZ)
    return math.min(dx, dz)
end

-- Clamp (x, z) to at least `inset` studs inside the platform edge (Rescue
-- Claw landing point). Returns x, z.
function ArenaMath.clampInside(arena: ArenaConfig, size: number, x: number, z: number, inset: number): (number, number)
    local limit = math.max(0, size / 2 - inset)
    local cx = math.clamp(x - arena.CenterX, -limit, limit)
    local cz = math.clamp(z - arena.CenterZ, -limit, limit)
    return arena.CenterX + cx, arena.CenterZ + cz
end

return ArenaMath
