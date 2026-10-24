--!strict
-- RoboPush Arena / CombatService.lua
-- Server-authoritative Dash + MVP specials (Rocket Pop, Side Burst, Counter
-- Shield). Clients send intent only; hits, knockback and cooldowns are
-- decided here from server-side positions (ARCHITECTURE 4, 8).
--
-- Interface
--   CombatService.init(deps)          -- connect RemoteEvents
--   CombatService.onRespawn(player)   -- new life: drop windows, push SkillState
--   CombatService.onMatchReset()      -- new match: clear cooldowns/windows
--   CombatService.clearWindows()      -- RESULT / WAITING: stop all active moves
--   CombatService.removePlayer(player)
--   CombatService.destroy()
--
-- Lifecycle: a Heartbeat connection exists only while at least one hit window
-- is active and is disconnected as soon as the last window closes.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameTypes = require(Shared:WaitForChild("GameTypes"))
local Maid = require(Shared:WaitForChild("Maid"))

local Logic = script.Parent.Parent:WaitForChild("Logic")
local CombatRules = require(Logic:WaitForChild("CombatRules"))
local CombatState = require(Logic:WaitForChild("CombatState"))

local Logger = require(script.Parent:WaitForChild("Logger"))
local CharacterService = require(script.Parent:WaitForChild("CharacterService"))

local EffectType = GameTypes.EffectType

export type Deps = {
    config: any,
    model: any, -- MatchModel
    remotes: { [string]: RemoteEvent },
}

type Window = {
    kind: string, -- "dash" | "side_burst"
    attacker: Player,
    matchId: string,
    lifeId: number,
    endsAt: number,
    hit: { [number]: boolean },
    motion: Instance?, -- LinearVelocity driving the move
    -- hit shape
    radius: number,
    maxDy: number,
    arcDegrees: number?, -- nil = radial test
    knockH: number,
    knockV: number,
    hitEffect: string,
}

local CombatService = {}

local config: any = nil
local model: any = nil
local remotes: { [string]: RemoteEvent } = {}
local combat: CombatState.CombatState = nil :: any
local limiter: CombatRules.RateLimiter = nil :: any
local maid = Maid.new()
local windows: { Window } = {}
local windowConnection: RBXScriptConnection? = nil
local knockToken: { [number]: number } = {}

local function now(): number
    return workspace:GetServerTimeNow()
end

-- ----------------------------------------------------------------- helpers

-- availableAt is server time; 0 means "ready" (never used this match).
local function sendSkillState(player: Player)
    local userId = player.UserId
    local selected = combat:getSelected(userId)
    local dashReady = math.max(0, combat:readyAt(userId, CombatState.DASH_KEY))
    local skillReady = math.max(0, combat:readyAt(userId, selected))
    remotes.SkillState:FireClient(player, CombatState.DASH_KEY, dashReady, selected)
    remotes.SkillState:FireClient(player, selected, skillReady, selected)
end

local function broadcastEffect(effectType: string, source: Player?, target: Player?, position: Vector3?)
    remotes.CombatEffect:FireAllClients(effectType, source and source.UserId, target and target.UserId, position)
end

local function opponentPlayer(player: Player): Player?
    local opponentId = model:opponentOf(player.UserId)
    return if opponentId then Players:GetPlayerByUserId(opponentId) else nil
end

-- Live root part for the player's *current* life, or nil.
local function liveRoot(player: Player): (BasePart?, Humanoid?)
    local humanoid, root = CharacterService.getParts(player)
    if not humanoid or not root or humanoid.Health <= 0 then
        return nil, nil
    end
    return root, humanoid
end

local function flatLook(root: BasePart): Vector3
    local look = root.CFrame.LookVector
    local flat = Vector3.new(look.X, 0, look.Z)
    if flat.Magnitude < 1e-3 then
        return Vector3.new(0, 0, -1)
    end
    return flat.Unit
end

-- Server-side ground check (a client-owned Humanoid's FloorMaterial is not
-- something the server should trust).
local function isGrounded(root: BasePart): boolean
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    params.FilterDescendantsInstances = { root.Parent :: Instance }
    local distance = config.Skills.rocket_pop.GroundCheckDistance
    return workspace:Raycast(root.Position, Vector3.new(0, -distance, 0), params) ~= nil
end

-- Owner-simulated self motion: a LinearVelocity on the client-owned root is
-- replicated and simulated by the owning client, so the mover sees no lag.
local function applySelfMotion(root: BasePart, velocity: Vector3, duration: number, verticalOnly: boolean): Instance
    local attachment = Instance.new("Attachment")
    attachment.Name = "RoboPushMotionAttachment"
    attachment.Parent = root

    local motion = Instance.new("LinearVelocity")
    motion.Name = "RoboPushMotion"
    motion.Attachment0 = attachment
    motion.RelativeTo = Enum.ActuatorRelativeTo.World
    if verticalOnly then
        motion.ForceLimitMode = Enum.ForceLimitMode.PerAxis
        motion.MaxAxesForce = Vector3.new(0, config.Physics.MotionMaxForce, 0)
    else
        -- Horizontal moves: do not fight gravity.
        motion.ForceLimitMode = Enum.ForceLimitMode.PerAxis
        motion.MaxAxesForce = Vector3.new(config.Physics.MotionMaxForce, 0, config.Physics.MotionMaxForce)
    end
    motion.VectorVelocity = velocity
    motion.Parent = attachment

    task.delay(duration, function()
        attachment:Destroy()
    end)
    return attachment
end

-- Authoritative knockback: take network ownership, apply mass-scaled impulse,
-- hand ownership back later (needs two-client tuning, T04).
local function applyKnockback(target: Player, delta: Vector3)
    local root, humanoid = liveRoot(target)
    if not root or not humanoid then
        return
    end
    local userId = target.UserId
    knockToken[userId] = (knockToken[userId] or 0) + 1
    local token = knockToken[userId]

    pcall(function()
        root:SetNetworkOwner(nil)
    end)
    humanoid.PlatformStand = true
    root:ApplyImpulse(delta * root.AssemblyMass)

    task.delay(config.Physics.KnockbackOwnershipSeconds, function()
        if knockToken[userId] ~= token then
            return -- a newer knockback owns the restore
        end
        if humanoid.Parent then
            humanoid.PlatformStand = false
        end
        if root.Parent and target.Parent == Players then
            pcall(function()
                root:SetNetworkOwner(target)
            end)
        end
    end)
end

local function stopWindowMotion(window: Window)
    if window.motion then
        window.motion:Destroy()
        window.motion = nil
    end
end

-- --------------------------------------------------------- impact resolution

-- Shield is evaluated first (same-frame priority rule, SKILLS 6).
local function resolveImpact(
    attacker: Player,
    target: Player,
    isRam: boolean,
    knockH: number,
    knockV: number,
    hitEffect: string,
    window: Window?
)
    local t = now()
    local attackerRoot = liveRoot(attacker)
    local targetRoot = liveRoot(target)
    if not attackerRoot or not targetRoot then
        return
    end
    if model:isProtected(target.UserId, t) then
        Logger.log("impact_ignored", { reason = "target_protected", attacker = attacker.UserId, target = target.UserId })
        return
    end

    local shieldActive = combat:isShieldActive(target.UserId, t)
    local outcome = CombatRules.resolveImpact(isRam, shieldActive)
    local a, b = attackerRoot.Position, targetRoot.Position

    if outcome == "rebound" then
        combat:consumeShield(target.UserId, t)
        if window then
            stopWindowMotion(window)
            window.endsAt = t -- rammer's move ends on rebound
        end
        if combat:canBeKnockedBack(attacker.UserId, t) then
            local shield = config.Skills.counter_shield
            local look = flatLook(attackerRoot)
            local vx, vy, vz =
                CombatRules.knockbackVelocity(b.X, b.Z, a.X, a.Z, -look.X, -look.Z, shield.ReboundHorizontal, shield.ReboundVertical)
            applyKnockback(attacker, Vector3.new(vx, vy, vz))
            combat:markKnockedBack(attacker.UserId, t)
        end
        broadcastEffect(EffectType.SHIELD_REBOUND, target, attacker, b)
        Logger.log("shield_rebound", { matchId = model.matchId, defender = target.UserId, rammer = attacker.UserId })
    elseif outcome == "blocked" then
        combat:consumeShield(target.UserId, t)
        broadcastEffect(EffectType.SHIELD_BLOCK, target, attacker, b)
        Logger.log("shield_block", { matchId = model.matchId, defender = target.UserId, attacker = attacker.UserId })
    else
        if not combat:canBeKnockedBack(target.UserId, t) then
            Logger.log("impact_ignored", { reason = "knockback_resist", attacker = attacker.UserId, target = target.UserId })
            return
        end
        local look = flatLook(attackerRoot)
        local vx, vy, vz = CombatRules.knockbackVelocity(a.X, a.Z, b.X, b.Z, look.X, look.Z, knockH, knockV)
        applyKnockback(target, Vector3.new(vx, vy, vz))
        combat:markKnockedBack(target.UserId, t)
        broadcastEffect(hitEffect, attacker, target, b)
        Logger.log("hit", { matchId = model.matchId, kind = hitEffect, attacker = attacker.UserId, target = target.UserId })
    end
end

-- ------------------------------------------------------------- hit windows

local function windowStillValid(window: Window, t: number): boolean
    if t > window.endsAt then
        return false
    end
    if window.attacker.Parent ~= Players then
        return false
    end
    if model.matchId ~= window.matchId or not GameTypes.isCombatState(model.state) then
        return false
    end
    return model:currentLifeId(window.attacker.UserId) == window.lifeId
end

local function stepWindows()
    local t = now()
    local remaining: { Window } = {}
    for _, window in windows do
        if windowStillValid(window, t) then
            local attackerRoot = liveRoot(window.attacker)
            local target = opponentPlayer(window.attacker)
            local targetRoot = target and liveRoot(target)
            if attackerRoot and target and targetRoot and not window.hit[target.UserId] and model:isAlive(target.UserId) then
                local a, b = attackerRoot.Position, targetRoot.Position
                local inside
                if window.arcDegrees then
                    local look = flatLook(attackerRoot)
                    inside = CombatRules.isInFrontArc(
                        a.X,
                        a.Y,
                        a.Z,
                        look.X,
                        look.Z,
                        b.X,
                        b.Y,
                        b.Z,
                        window.radius,
                        window.arcDegrees,
                        window.maxDy
                    )
                else
                    inside = CombatRules.isInRadius(a.X, a.Y, a.Z, b.X, b.Y, b.Z, window.radius, window.maxDy)
                end
                if inside then
                    -- MaxHitsPerTargetPerUse = 1: mark before resolving.
                    window.hit[target.UserId] = true
                    resolveImpact(window.attacker, target, true, window.knockH, window.knockV, window.hitEffect, window)
                end
            end
            if t <= window.endsAt then
                table.insert(remaining, window)
            else
                stopWindowMotion(window)
            end
        else
            stopWindowMotion(window)
        end
    end
    windows = remaining
    if #windows == 0 and windowConnection then
        windowConnection:Disconnect()
        windowConnection = nil
    end
end

local function addWindow(window: Window)
    table.insert(windows, window)
    if not windowConnection then
        windowConnection = RunService.Heartbeat:Connect(stepWindows)
    end
end

-- --------------------------------------------------------------- requests

-- Shared gate for every combat request. Returns root/humanoid/lifeId if OK.
local function gate(player: Player, action: string): (BasePart?, Humanoid?, number?)
    local t = now()
    if not limiter:allow(player.UserId, t) then
        Logger.anomaly(player, "rate_limited", { action = action })
        return nil, nil, nil
    end
    local ok, reason = model:canAct(player.UserId, t)
    if not ok then
        Logger.log("request_rejected", { userId = player.UserId, action = action, reason = reason })
        return nil, nil, nil
    end
    local root, humanoid = liveRoot(player)
    if not root or not humanoid then
        return nil, nil, nil
    end
    return root, humanoid, model:currentLifeId(player.UserId)
end

local function onRequestDash(player: Player, _clientSequence: any)
    local root, _humanoid, lifeId = gate(player, "dash")
    if not root or not lifeId then
        return
    end
    local t = now()
    local ok, reason = combat:tryUseDash(player.UserId, t)
    if not ok then
        Logger.log("request_rejected", { userId = player.UserId, action = "dash", reason = reason })
        sendSkillState(player)
        return
    end
    local dash = config.Dash
    local motion = applySelfMotion(root, flatLook(root) * dash.Speed, dash.Duration, false)
    addWindow({
        kind = "dash",
        attacker = player,
        matchId = model.matchId,
        lifeId = lifeId,
        endsAt = t + dash.Duration,
        hit = {},
        motion = motion,
        radius = dash.HitRadius,
        maxDy = dash.MaxHeightDifference,
        arcDegrees = dash.FrontArcDegrees,
        knockH = dash.KnockbackHorizontal,
        knockV = dash.KnockbackVertical,
        hitEffect = EffectType.DASH_HIT,
    })
    sendSkillState(player)
    broadcastEffect(EffectType.DASH, player, nil, root.Position)
    Logger.log("dash", { matchId = model.matchId, userId = player.UserId, lifeId = lifeId })
end

local function castRocketPop(player: Player, lifeId: number, matchId: string)
    local skill = config.Skills.rocket_pop
    broadcastEffect(EffectType.ROCKET_POP, player, nil, nil) -- visible startup cue
    task.delay(skill.Startup, function()
        if model.matchId ~= matchId or model:currentLifeId(player.UserId) ~= lifeId or not GameTypes.isCombatState(model.state) then
            return -- cancelled by fall, respawn or match end
        end
        local root = liveRoot(player)
        if not root then
            return
        end
        applySelfMotion(root, Vector3.new(0, skill.LaunchVerticalSpeed, 0), skill.LaunchDuration, true)
        -- Launch shockwave: one radial check, at most one hit per target.
        local target = opponentPlayer(player)
        local targetRoot = target and liveRoot(target)
        if target and targetRoot and model:isAlive(target.UserId) then
            local a, b = root.Position, targetRoot.Position
            if CombatRules.isInRadius(a.X, a.Y, a.Z, b.X, b.Y, b.Z, skill.HitRadius, skill.MaxHeightDifference) then
                resolveImpact(player, target, false, skill.KnockbackHorizontal, skill.KnockbackVertical, EffectType.ROCKET_HIT, nil)
            end
        end
        Logger.log("rocket_pop", { matchId = matchId, userId = player.UserId, lifeId = lifeId })
    end)
end

local function castSideBurst(player: Player, root: BasePart, lifeId: number, hint: any)
    local skill = config.Skills.side_burst
    local hintX, hintZ = nil, nil
    if typeof(hint) == "Vector3" then
        hintX, hintZ = hint.X, hint.Z
    end
    local right = root.CFrame.RightVector
    local side = CombatRules.chooseSide(right.X, right.Z, hintX, hintZ, skill.DefaultSide)
    local flatRight = Vector3.new(right.X, 0, right.Z)
    flatRight = if flatRight.Magnitude > 1e-3 then flatRight.Unit else Vector3.new(1, 0, 0)
    local speed = skill.SideDistance / skill.Duration
    -- No edge protection on purpose: bursting off the platform is a real risk (SKILLS 4).
    local motion = applySelfMotion(root, flatRight * side * speed, skill.Duration, false)
    addWindow({
        kind = "side_burst",
        attacker = player,
        matchId = model.matchId,
        lifeId = lifeId,
        endsAt = now() + skill.Duration,
        hit = {},
        motion = motion,
        radius = skill.HitRadius,
        maxDy = skill.MaxHeightDifference,
        arcDegrees = nil,
        knockH = skill.KnockbackHorizontal,
        knockV = skill.KnockbackVertical,
        hitEffect = EffectType.SIDE_HIT,
    })
    broadcastEffect(EffectType.SIDE_BURST, player, nil, root.Position)
    Logger.log("side_burst", { matchId = model.matchId, userId = player.UserId, side = side })
end

local function castCounterShield(player: Player, root: BasePart)
    local skill = config.Skills.counter_shield
    -- Server-side visual so both clients see the same window.
    local bubble = Instance.new("Part")
    bubble.Name = "CounterShield"
    bubble.Shape = Enum.PartType.Ball
    bubble.Size = Vector3.new(7, 7, 7)
    bubble.Material = Enum.Material.ForceField
    bubble.Color = Color3.fromRGB(120, 220, 255)
    bubble.Transparency = 0.2
    bubble.CanCollide = false
    bubble.CanQuery = false
    bubble.CanTouch = false
    bubble.Massless = true
    bubble.CFrame = root.CFrame
    local weld = Instance.new("WeldConstraint")
    weld.Part0 = bubble
    weld.Part1 = root
    weld.Parent = bubble
    bubble.Parent = root.Parent
    task.delay(skill.ActiveDuration, function()
        bubble:Destroy()
    end)
    broadcastEffect(EffectType.SHIELD_UP, player, nil, root.Position)
    Logger.log("shield_up", { matchId = model.matchId, userId = player.UserId })
end

local function onRequestSpecial(player: Player, skillId: any, directionHint: any)
    local root, humanoid, lifeId = gate(player, "special")
    if not root or not humanoid or not lifeId then
        return
    end
    if not CombatRules.isValidMvpSkill(config, skillId) then
        Logger.anomaly(player, "invalid_skill", { skillId = tostring(skillId) })
        return
    end
    if directionHint ~= nil then
        if typeof(directionHint) ~= "Vector3" or not CombatRules.isValidHint(config, directionHint.X, directionHint.Y, directionHint.Z) then
            Logger.anomaly(player, "invalid_direction_hint", { hint = tostring(directionHint) })
            return
        end
    end
    -- Rocket Pop cannot be re-cast while airborne (SKILLS 2). Checked before
    -- spending the cooldown so a rejected cast is not charged.
    if skillId == "rocket_pop" and not isGrounded(root) then
        Logger.log("request_rejected", { userId = player.UserId, action = skillId, reason = "airborne" })
        return
    end
    local t = now()
    local ok, reason = combat:tryUseSpecial(player.UserId, skillId, t)
    if not ok then
        Logger.log("request_rejected", { userId = player.UserId, action = skillId, reason = reason })
        sendSkillState(player)
        return
    end
    if skillId == "rocket_pop" then
        castRocketPop(player, lifeId, model.matchId)
    elseif skillId == "side_burst" then
        castSideBurst(player, root, lifeId, directionHint)
    elseif skillId == "counter_shield" then
        castCounterShield(player, root)
    end
    sendSkillState(player)
end

local function onSelectSkill(player: Player, skillId: any)
    local t = now()
    if not limiter:allow(player.UserId, t) then
        Logger.anomaly(player, "rate_limited", { action = "select" })
        return
    end
    local ok, reason = combat:selectSkill(player.UserId, skillId, GameTypes.isSkillSelectState(model.state))
    if not ok then
        Logger.log("select_rejected", { userId = player.UserId, reason = reason, skillId = tostring(skillId) })
    else
        Logger.log("skill_selected", { userId = player.UserId, skillId = skillId })
    end
    sendSkillState(player)
end

-- ---------------------------------------------------------------- lifecycle

function CombatService.init(deps: Deps)
    config = deps.config
    model = deps.model
    remotes = deps.remotes
    combat = CombatState.new(config)
    limiter = CombatRules.RateLimiter.new(config.Net.MaxRequestsPerSecond, config.Net.BurstRequests)

    maid:give(remotes.RequestDash.OnServerEvent:Connect(onRequestDash))
    maid:give(remotes.RequestSpecial.OnServerEvent:Connect(onRequestSpecial))
    maid:give(remotes.SelectSkill.OnServerEvent:Connect(onSelectSkill))
end

function CombatService.clearWindows()
    for _, window in windows do
        stopWindowMotion(window)
    end
    windows = {}
    if windowConnection then
        windowConnection:Disconnect()
        windowConnection = nil
    end
end

function CombatService.onRespawn(player: Player)
    combat:onRespawn(player.UserId)
    local remaining = {}
    for _, window in windows do
        if window.attacker ~= player then
            table.insert(remaining, window)
        else
            stopWindowMotion(window)
        end
    end
    windows = remaining
    sendSkillState(player)
end

function CombatService.onMatchReset()
    CombatService.clearWindows()
    combat:onMatchReset()
    for _, player in Players:GetPlayers() do
        sendSkillState(player)
    end
end

function CombatService.sendSkillState(player: Player)
    sendSkillState(player)
end

function CombatService.removePlayer(player: Player)
    combat:removePlayer(player.UserId)
    limiter:forget(player.UserId)
    knockToken[player.UserId] = nil
    local remaining = {}
    for _, window in windows do
        if window.attacker ~= player then
            table.insert(remaining, window)
        end
    end
    windows = remaining
end

function CombatService.destroy()
    CombatService.clearWindows()
    maid:cleanup()
end

return CombatService
