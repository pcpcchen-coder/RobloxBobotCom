--!strict
-- RoboPush Arena / MatchService.lua
-- Roblox adapter around the pure MatchModel: player join/leave, server clock,
-- fall detection, serialized spawning, and translating model events into
-- ArenaService / CharacterService / CombatService calls and RemoteEvents.
--
-- Interface
--   MatchService.start(deps)  -- connect Players events, start the match loop
--   MatchService.stop()       -- disconnect everything (BindToClose / tests)
--
-- Lifecycle: the Heartbeat loop runs only while at least one player is on the
-- server; per-life connections (Humanoid.Died) live in a per-player Maid that
-- is cleaned on respawn and on PlayerRemoving.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameTypes = require(Shared:WaitForChild("GameTypes"))
local ArenaMath = require(Shared:WaitForChild("ArenaMath"))
local Maid = require(Shared:WaitForChild("Maid"))

local Logic = script.Parent.Parent:WaitForChild("Logic")
local MatchModel = require(Logic:WaitForChild("MatchModel"))

local Logger = require(script.Parent:WaitForChild("Logger"))
local ArenaService = require(script.Parent:WaitForChild("ArenaService"))
local CharacterService = require(script.Parent:WaitForChild("CharacterService"))
local CombatService = require(script.Parent:WaitForChild("CombatService"))

local MatchState = GameTypes.MatchState

export type Deps = {
    config: any,
    remotes: { [string]: RemoteEvent },
}

type SpawnRequest = { slot: number, token: number, at: number }

local MatchService = {}

local config: any = nil
local remotes: { [string]: RemoteEvent } = {}
local model: MatchModel.MatchModel = nil :: any
local serviceMaid = Maid.new()
local loopConnection: RBXScriptConnection? = nil
local lifeMaids: { [number]: Maid.Maid } = {}
local spawnQueue: { [number]: SpawnRequest } = {}
local spawnWorkers: { [number]: boolean } = {}
local lastSnapshotAt: { [number]: number } = {}

local function now(): number
    return workspace:GetServerTimeNow()
end

local function playerOf(userId: number): Player?
    return Players:GetPlayerByUserId(userId)
end

local applyEvents: (events: { any }) -> ()

-- ---------------------------------------------------------------- spawning

local function onLifeStarted(player: Player, character: Model, humanoid: Humanoid, lifeId: number)
    local userId = player.UserId
    if lifeMaids[userId] then
        lifeMaids[userId]:cleanup()
    end
    local lifeMaid = Maid.new()
    lifeMaids[userId] = lifeMaid

    -- Resetting / dying counts as a fall for this life (deduped by lifeId).
    lifeMaid:give(humanoid.Died:Connect(function()
        applyEvents(model:reportFall(userId, lifeId, now()))
    end))

    CombatService.onRespawn(player)
    CharacterService.setFrozen(player, model.state == MatchState.COUNTDOWN)
    CharacterService.showProtection(character, config.Match.SpawnProtection)
    Logger.log("life_started", { matchId = model.matchId, userId = userId, lifeId = lifeId })
end

-- One worker per player so overlapping SpawnPlayer requests can never race
-- LoadCharacter; only the newest token is honoured.
local function runSpawnWorker(userId: number)
    if spawnWorkers[userId] then
        return
    end
    spawnWorkers[userId] = true
    task.spawn(function()
        while spawnQueue[userId] do
            local request = spawnQueue[userId] :: SpawnRequest
            local delaySeconds = request.at - now()
            if delaySeconds > 0 then
                task.wait(delaySeconds)
            end
            if spawnQueue[userId] ~= request then
                continue -- superseded while waiting
            end
            spawnQueue[userId] = nil
            local player = playerOf(userId)
            if player and model.spawnToken[userId] == request.token then
                -- Drop the old life's Died listener before LoadCharacter replaces the body.
                if lifeMaids[userId] then
                    lifeMaids[userId]:cleanup()
                    lifeMaids[userId] = nil
                end
                local cframe = ArenaService.spawnCFrame(model.arenaSize, request.slot)
                local character, humanoid = CharacterService.spawn(player, cframe, request.slot)
                if character and humanoid then
                    local lifeId = model:beginLife(userId, request.token, now())
                    if lifeId then
                        onLifeStarted(player, character, humanoid, lifeId)
                    end
                end
            end
        end
        spawnWorkers[userId] = nil
    end)
end

local function requestSpawn(userId: number, slot: number, delay: number, token: number)
    spawnQueue[userId] = { slot = slot, token = token, at = now() + delay }
    runSpawnWorker(userId)
end

-- ------------------------------------------------------------ event mapping

local function onStateChanged(event: any)
    local state = event.state
    remotes.MatchChanged:FireAllClients(event.matchId, state, event.endsAt)
    Logger.log("state", { matchId = event.matchId, state = state, endsAt = event.endsAt })

    for _, userId in model.players do
        local player = playerOf(userId)
        if player then
            CharacterService.setFrozen(player, state == MatchState.COUNTDOWN)
        end
    end

    if state == MatchState.COUNTDOWN or state == MatchState.WAITING then
        -- Participants may have changed: push a full snapshot to everyone.
        remotes.MatchSnapshot:FireAllClients(model:snapshot(now()))
    end
    if state == MatchState.COUNTDOWN then
        CombatService.onMatchReset()
    elseif not GameTypes.isCombatState(state) then
        CombatService.clearWindows()
    end
end

applyEvents = function(events: { any })
    for _, event in events do
        local kind = event.type
        if kind == "StateChanged" then
            onStateChanged(event)
        elseif kind == "ScoreChanged" then
            remotes.ScoreChanged:FireAllClients(event.matchId, event.scores, event.scorer)
            Logger.log("score", { matchId = event.matchId, scorer = event.scorer })
        elseif kind == "Result" then
            remotes.RoundResult:FireAllClients(event.winner, event.reason, event.finalScores)
            Logger.log("result", { matchId = event.matchId, winner = event.winner, reason = event.reason })
        elseif kind == "SpawnPlayer" then
            requestSpawn(event.userId, event.slot, event.delay, event.token)
        elseif kind == "FallResolved" then
            remotes.CombatEffect:FireAllClients(GameTypes.EffectType.FALL, nil, event.userId, nil)
            Logger.log(
                "fall",
                { matchId = model.matchId, userId = event.userId, lifeId = event.lifeId, scored = event.scored, reason = event.reason }
            )
        elseif kind == "ArenaWarning" then
            remotes.ArenaWarning:FireAllClients(event.nextSize, event.shrinkAt)
            Logger.log("arena_warning", { nextSize = event.nextSize, shrinkAt = event.shrinkAt })
        elseif kind == "ArenaChanged" then
            ArenaService.resize(event.size, event.duration)
            remotes.ArenaChanged:FireAllClients(event.size, event.duration)
            Logger.log("arena_changed", { size = event.size, duration = event.duration })
        end
    end
end

-- ---------------------------------------------------------------- the loop

-- Server-side fall detection: only the (at most two) live participants.
local function detectFalls(t: number)
    for _, userId in model.players do
        local lifeId = model:currentLifeId(userId)
        local player = lifeId and playerOf(userId)
        if player and lifeId then
            local _, root = CharacterService.getParts(player)
            if root and ArenaMath.isFallen(config.Arena, root.Position.Y) then
                applyEvents(model:reportFall(userId, lifeId, t))
            end
        end
    end
end

local function step()
    local t = now()
    detectFalls(t)
    applyEvents(model:tick(t))
end

local function updateLoop()
    local hasPlayers = #Players:GetPlayers() > 0
    if hasPlayers and not loopConnection then
        loopConnection = RunService.Heartbeat:Connect(step)
    elseif not hasPlayers and loopConnection then
        loopConnection:Disconnect()
        loopConnection = nil
    end
end

-- ------------------------------------------------------------ player events

local function sendSnapshot(player: Player)
    remotes.MatchSnapshot:FireClient(player, model:snapshot(now()))
    CombatService.sendSkillState(player)
end

local function onPlayerAdded(player: Player)
    Logger.log("player_added", { userId = player.UserId })
    applyEvents(model:addPlayer(player.UserId, now()))
    updateLoop()
    sendSnapshot(player)
end

local function onPlayerRemoving(player: Player)
    local userId = player.UserId
    Logger.log("player_removing", { userId = userId })
    spawnQueue[userId] = nil
    lastSnapshotAt[userId] = nil
    if lifeMaids[userId] then
        lifeMaids[userId]:cleanup()
        lifeMaids[userId] = nil
    end
    CombatService.removePlayer(player)
    applyEvents(model:removePlayer(userId, now()))
    -- PlayerRemoving fires before the player leaves the list.
    task.defer(updateLoop)
end

function MatchService.start(deps: Deps)
    config = deps.config
    remotes = deps.remotes
    local prefix = if game.JobId ~= "" then string.sub(game.JobId, 1, 6) .. "-" else "studio-"
    model = MatchModel.new(config, prefix)

    ArenaService.init(config)
    CharacterService.init(config)
    CombatService.init({ config = config, model = model, remotes = remotes })

    serviceMaid:give(Players.PlayerAdded:Connect(onPlayerAdded))
    serviceMaid:give(Players.PlayerRemoving:Connect(onPlayerRemoving))
    serviceMaid:give(remotes.RequestSnapshot.OnServerEvent:Connect(function(player: Player)
        local t = now()
        if t - (lastSnapshotAt[player.UserId] or -math.huge) < config.Net.SnapshotMinInterval then
            return
        end
        lastSnapshotAt[player.UserId] = t
        sendSnapshot(player)
    end))
    -- Players that joined before this script ran (Studio play solo).
    for _, player in Players:GetPlayers() do
        task.spawn(onPlayerAdded, player)
    end
end

function MatchService.stop()
    if loopConnection then
        loopConnection:Disconnect()
        loopConnection = nil
    end
    for _, lifeMaid in lifeMaids do
        lifeMaid:cleanup()
    end
    lifeMaids = {}
    spawnQueue = {}
    serviceMaid:cleanup()
    CombatService.destroy()
    ArenaService.destroy()
end

return MatchService
