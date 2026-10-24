--!strict
-- RoboPush Arena / MatchModel.lua
-- Pure, deterministic 1v1 match state machine + score ledger (GDD 2, 7;
-- ARCHITECTURE 5). No Roblox APIs: time is injected as `now` (server seconds),
-- and every method returns a list of events that MatchService turns into
-- spawns, arena changes and RemoteEvents.
--
-- Responsibilities
--   * WAITING -> COUNTDOWN -> RUNNING -> (SUDDEN_DEATH) -> RESULT -> ...
--   * matchId per match, lifeId per spawned life (never reused)
--   * fall de-duplication, double-fall window, scoring, single finish path
--   * shrink schedule timing (ArenaService only animates)
--
-- Event types emitted (field names are part of the MatchService contract):
--   StateChanged { matchId, state, endsAt }
--   ScoreChanged { matchId, scores, scorer? }
--   Result       { matchId, winner?, reason, finalScores }
--   SpawnPlayer  { userId, slot, delay, token }
--   FallResolved { userId, lifeId, scored, reason }
--   ArenaWarning { nextSize, shrinkAt }
--   ArenaChanged { size, duration }

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameTypes = require(Shared:WaitForChild("GameTypes"))
local ArenaMath = require(Shared:WaitForChild("ArenaMath"))

local MatchState = GameTypes.MatchState
local ResultReason = GameTypes.ResultReason

type Event = GameTypes.MatchEvent

type Life = {
    lifeId: number,
    alive: boolean,
    protectedUntil: number,
}

type PendingFall = {
    userId: number,
    lifeId: number,
    at: number,
}

local MatchModel = {}
MatchModel.__index = MatchModel

export type MatchModel = typeof(setmetatable(
    {} :: {
        config: any,
        state: string,
        matchId: string,
        matchCounter: number,
        matchIdPrefix: string,
        roster: { number },
        players: { number },
        scores: { [number]: number },
        lives: { [number]: Life },
        lifeCounter: number,
        eliminated: { [string]: boolean },
        pendingFalls: { PendingFall },
        spawnToken: { [number]: number },
        spawnPending: { [number]: boolean },
        tokenCounter: number,
        phaseEndsAt: number?,
        runningStartedAt: number?,
        arenaSize: number,
        nextWarnIndex: number,
        nextShrinkIndex: number,
    },
    MatchModel
))

function MatchModel.new(config: any, matchIdPrefix: string?): MatchModel
    local self = setmetatable({
        config = config,
        state = MatchState.WAITING,
        matchId = "none",
        matchCounter = 0,
        matchIdPrefix = matchIdPrefix or "M",
        roster = {},
        players = {},
        scores = {},
        lives = {},
        lifeCounter = 0,
        eliminated = {},
        pendingFalls = {},
        spawnToken = {},
        spawnPending = {},
        tokenCounter = 0,
        phaseEndsAt = nil,
        runningStartedAt = nil,
        arenaSize = config.Arena.InitialSize,
        nextWarnIndex = 1,
        nextShrinkIndex = 1,
    }, MatchModel)
    return self
end

-- ---------------------------------------------------------------- queries

function MatchModel.slotOf(self: MatchModel, userId: number): number?
    return table.find(self.players, userId)
end

function MatchModel.isParticipant(self: MatchModel, userId: number): boolean
    return self:slotOf(userId) ~= nil
end

function MatchModel.opponentOf(self: MatchModel, userId: number): number?
    if not self:isParticipant(userId) then
        return nil
    end
    for _, other in self.players do
        if other ~= userId then
            return other
        end
    end
    return nil
end

function MatchModel.currentLifeId(self: MatchModel, userId: number): number?
    local life = self.lives[userId]
    return if life and life.alive then life.lifeId else nil
end

function MatchModel.isAlive(self: MatchModel, userId: number): boolean
    local life = self.lives[userId]
    return life ~= nil and life.alive
end

function MatchModel.isProtected(self: MatchModel, userId: number, now: number): boolean
    local life = self.lives[userId]
    return life ~= nil and life.alive and now < life.protectedUntil
end

-- Combat actions require a combat state, a participant and a live, current life.
function MatchModel.canAct(self: MatchModel, userId: number, now: number): (boolean, string?)
    if not GameTypes.isCombatState(self.state) then
        return false, "state"
    end
    if not self:isParticipant(userId) then
        return false, "not_participant"
    end
    if not self:isAlive(userId) then
        return false, "not_alive"
    end
    if self:isProtected(userId, now) then
        return false, "spawn_protected"
    end
    return true, nil
end

function MatchModel.scoresForWire(self: MatchModel): GameTypes.Scores
    local wire = {}
    for _, userId in self.players do
        wire[tostring(userId)] = self.scores[userId] or 0
    end
    return wire
end

function MatchModel.snapshot(self: MatchModel, now: number): GameTypes.MatchSnapshot
    return {
        matchId = self.matchId,
        state = self.state,
        serverTime = now,
        endsAt = self.phaseEndsAt,
        scores = self:scoresForWire(),
        arenaSize = self.arenaSize,
        players = table.clone(self.players),
    }
end

-- ---------------------------------------------------------------- internals

local function emit(events: { Event }, event: Event)
    table.insert(events, event)
end

function MatchModel._emitState(self: MatchModel, events: { Event })
    emit(events, { type = "StateChanged", matchId = self.matchId, state = self.state, endsAt = self.phaseEndsAt })
end

function MatchModel._emitScores(self: MatchModel, events: { Event }, scorer: number?)
    emit(events, { type = "ScoreChanged", matchId = self.matchId, scores = self:scoresForWire(), scorer = scorer })
end

function MatchModel._setArenaSize(self: MatchModel, events: { Event }, size: number, duration: number)
    self.arenaSize = size
    emit(events, { type = "ArenaChanged", size = size, duration = duration })
end

function MatchModel._requestSpawn(self: MatchModel, events: { Event }, userId: number, delay: number)
    local slot = self:slotOf(userId)
    if not slot or not table.find(self.roster, userId) then
        return -- never spawn someone who already left
    end
    self.tokenCounter += 1
    self.spawnToken[userId] = self.tokenCounter
    self.spawnPending[userId] = true
    emit(events, { type = "SpawnPlayer", userId = userId, slot = slot, delay = delay, token = self.tokenCounter })
end

-- Spawn every participant that is neither alive nor already waiting to spawn.
function MatchModel._spawnMissing(self: MatchModel, events: { Event }, delay: number)
    for _, userId in self.players do
        if not self:isAlive(userId) and not self.spawnPending[userId] then
            self:_requestSpawn(events, userId, delay)
        end
    end
end

-- Participants are the first MaxPlayers roster entries (join order).
function MatchModel._refreshParticipants(self: MatchModel)
    local players = {}
    for i = 1, math.min(#self.roster, self.config.Match.MaxPlayers) do
        players[i] = self.roster[i]
    end
    self.players = players
end

function MatchModel._startCountdown(self: MatchModel, events: { Event }, now: number)
    self.matchCounter += 1
    self.matchId = string.format("%s%d", self.matchIdPrefix, self.matchCounter)
    self.state = MatchState.COUNTDOWN
    self.phaseEndsAt = now + self.config.Match.Countdown
    self.runningStartedAt = nil
    self.pendingFalls = {}
    self.scores = {}
    for _, userId in self.players do
        self.scores[userId] = 0
    end
    self.nextWarnIndex = 1
    self.nextShrinkIndex = 1
    self:_setArenaSize(events, self.config.Arena.InitialSize, 0)
    self:_emitState(events)
    self:_emitScores(events, nil)
    -- Fresh, symmetric spawns for both robots at match start.
    for _, userId in self.players do
        self:_requestSpawn(events, userId, 0)
    end
end

function MatchModel._enterWaiting(self: MatchModel, events: { Event })
    self.state = MatchState.WAITING
    self.phaseEndsAt = nil
    self.runningStartedAt = nil
    self.pendingFalls = {}
    if self.arenaSize ~= self.config.Arena.InitialSize then
        self:_setArenaSize(events, self.config.Arena.InitialSize, 0)
    end
    self:_emitState(events)
end

-- The single path into RESULT (prevents double settlement, ARCHITECTURE 5).
function MatchModel._finish(self: MatchModel, events: { Event }, now: number, winner: number?, reason: string)
    if self.state == MatchState.RESULT then
        return
    end
    self.state = MatchState.RESULT
    self.phaseEndsAt = now + self.config.Match.ResultDuration
    self.pendingFalls = {}
    self:_emitState(events)
    emit(events, {
        type = "Result",
        matchId = self.matchId,
        winner = winner,
        reason = reason,
        finalScores = self:scoresForWire(),
    })
    -- Anyone whose fall was discarded by the finish still needs a body.
    self:_spawnMissing(events, self.config.Match.RespawnDelay)
end

function MatchModel._afterResult(self: MatchModel, events: { Event }, now: number)
    self:_refreshParticipants()
    if #self.players >= self.config.Match.MaxPlayers then
        self:_startCountdown(events, now)
    else
        self:_enterWaiting(events)
        self:_spawnMissing(events, 0)
    end
end

-- Resolve pending falls whose double-fall window has closed (or all, if forced).
function MatchModel._resolveFalls(self: MatchModel, events: { Event }, now: number, force: boolean)
    local window = self.config.Match.DoubleFallWindow
    table.sort(self.pendingFalls, function(a, b)
        return a.at < b.at
    end)
    while #self.pendingFalls > 0 and GameTypes.isCombatState(self.state) do
        local first = self.pendingFalls[1]
        local windowEnd = first.at + window
        if now < windowEnd and not force then
            break
        end
        local group: { PendingFall } = {}
        local rest: { PendingFall } = {}
        for _, fall in self.pendingFalls do
            if fall.at <= windowEnd then
                table.insert(group, fall)
            else
                table.insert(rest, fall)
            end
        end
        self.pendingFalls = rest

        local distinct: { [number]: boolean } = {}
        local count = 0
        for _, fall in group do
            if not distinct[fall.userId] then
                distinct[fall.userId] = true
                count += 1
            end
        end

        if count >= 2 then
            -- Double fall: nobody scores, both respawn (GDD 2).
            for _, fall in group do
                emit(events, { type = "FallResolved", userId = fall.userId, lifeId = fall.lifeId, scored = false, reason = "double_fall" })
                self:_requestSpawn(events, fall.userId, self.config.Match.RespawnDelay)
            end
        else
            local fall = group[1]
            local opponent = self:opponentOf(fall.userId)
            local opponentAlive = false
            if opponent then
                opponentAlive = self:isAlive(opponent)
                -- Opponent fell only after this window closed: still alive at resolution time.
                for _, later in rest do
                    if later.userId == opponent then
                        opponentAlive = true
                    end
                end
            end
            local scored = opponent ~= nil and opponentAlive
            emit(events, {
                type = "FallResolved",
                userId = fall.userId,
                lifeId = fall.lifeId,
                scored = scored,
                reason = if scored then "scored" else "opponent_not_alive",
            })
            self:_requestSpawn(events, fall.userId, self.config.Match.RespawnDelay)
            if scored and opponent then
                self.scores[opponent] = (self.scores[opponent] or 0) + 1
                self:_emitScores(events, opponent)
                if self.state == MatchState.SUDDEN_DEATH then
                    self:_finish(events, now, opponent, ResultReason.SUDDEN_DEATH)
                elseif self.scores[opponent] >= self.config.Match.ScoreToWin then
                    self:_finish(events, now, opponent, ResultReason.SCORE)
                end
            end
        end
    end
end

function MatchModel._tickShrink(self: MatchModel, events: { Event }, now: number)
    local arena = self.config.Arena
    local startedAt = self.runningStartedAt :: number
    local elapsed = now - startedAt
    local steps = arena.ShrinkSteps
    while self.nextWarnIndex <= #steps and elapsed >= steps[self.nextWarnIndex].Time - arena.ShrinkWarning do
        local step = steps[self.nextWarnIndex]
        emit(events, { type = "ArenaWarning", nextSize = step.Size, shrinkAt = startedAt + step.Time })
        self.nextWarnIndex += 1
    end
    while self.nextShrinkIndex <= #steps and elapsed >= steps[self.nextShrinkIndex].Time do
        self:_setArenaSize(events, ArenaMath.sizeAtElapsed(arena, steps[self.nextShrinkIndex].Time), arena.ShrinkDuration)
        self.nextShrinkIndex += 1
    end
end

function MatchModel._compareScores(self: MatchModel): number?
    local a, b = self.players[1], self.players[2]
    if not a or not b then
        return a or b
    end
    local sa, sb = self.scores[a] or 0, self.scores[b] or 0
    if sa > sb then
        return a
    elseif sb > sa then
        return b
    end
    return nil
end

-- ---------------------------------------------------------------- commands

function MatchModel.addPlayer(self: MatchModel, userId: number, now: number): { Event }
    local events = {}
    if table.find(self.roster, userId) then
        return events
    end
    table.insert(self.roster, userId)
    if self.state == MatchState.WAITING then
        self:_refreshParticipants()
        if #self.players >= self.config.Match.MaxPlayers then
            self:_startCountdown(events, now)
        else
            self:_spawnMissing(events, 0)
        end
    end
    return events
end

function MatchModel.removePlayer(self: MatchModel, userId: number, now: number): { Event }
    local events = {}
    local index = table.find(self.roster, userId)
    if not index then
        return events
    end
    table.remove(self.roster, index)
    self.lives[userId] = nil
    self.spawnToken[userId] = nil
    self.spawnPending[userId] = nil
    local wasParticipant = self:isParticipant(userId)

    if not wasParticipant then
        return events
    end

    if self.state == MatchState.WAITING or self.state == MatchState.COUNTDOWN then
        -- Countdown cancelled by a leaver returns to WAITING (T14).
        if self.state == MatchState.COUNTDOWN then
            self:_enterWaiting(events)
        end
        self:_refreshParticipants()
        if #self.players >= self.config.Match.MaxPlayers then
            self:_startCountdown(events, now)
        else
            self:_spawnMissing(events, 0)
        end
    elseif GameTypes.isCombatState(self.state) then
        -- Forfeit (T09): remaining participant wins, score is not forced to 3.
        local winner = nil
        for _, other in self.players do
            if other ~= userId then
                winner = other
            end
        end
        self:_finish(events, now, winner, ResultReason.FORFEIT)
    end
    -- RESULT: participants are refreshed when RESULT ends.
    return events
end

-- Called by MatchService once the character for a SpawnPlayer event exists.
-- Returns the new lifeId, or nil when the token is stale.
function MatchModel.beginLife(self: MatchModel, userId: number, token: number, now: number): number?
    if self.spawnToken[userId] ~= token or not self:isParticipant(userId) then
        return nil
    end
    self.spawnPending[userId] = nil
    self.lifeCounter += 1
    self.lives[userId] = {
        lifeId = self.lifeCounter,
        alive = true,
        protectedUntil = now + self.config.Match.SpawnProtection,
    }
    return self.lifeCounter
end

-- Server-detected fall (root below FallHeight or Humanoid died).
function MatchModel.reportFall(self: MatchModel, userId: number, lifeId: number, now: number): { Event }
    local events = {}
    local life = self.lives[userId]
    local key = string.format("%d:%d", userId, lifeId)
    if not life or life.lifeId ~= lifeId or not life.alive or self.eliminated[key] then
        return events -- stale or duplicate (T02, T21)
    end
    life.alive = false
    self.eliminated[key] = true
    if GameTypes.isCombatState(self.state) then
        table.insert(self.pendingFalls, { userId = userId, lifeId = lifeId, at = now })
    else
        emit(events, { type = "FallResolved", userId = userId, lifeId = lifeId, scored = false, reason = "not_scoring_state" })
        self:_requestSpawn(events, userId, self.config.Match.RespawnDelay)
    end
    return events
end

function MatchModel.tick(self: MatchModel, now: number): { Event }
    local events = {}
    local endsAt = self.phaseEndsAt

    if self.state == MatchState.COUNTDOWN and endsAt and now >= endsAt then
        self.state = MatchState.RUNNING
        self.runningStartedAt = now
        self.phaseEndsAt = now + self.config.Match.Duration
        self:_emitState(events)
    end

    if GameTypes.isCombatState(self.state) then
        self:_resolveFalls(events, now, false)
    end

    if self.state == MatchState.RUNNING then
        self:_tickShrink(events, now)
        if now >= (self.phaseEndsAt :: number) then
            self:_resolveFalls(events, now, true)
            if self.state == MatchState.RUNNING then
                local leader = self:_compareScores()
                if leader then
                    self:_finish(events, now, leader, ResultReason.TIMEOUT)
                else
                    self.state = MatchState.SUDDEN_DEATH
                    self.phaseEndsAt = now + self.config.Match.SuddenDeath
                    self:_setArenaSize(events, self.config.Arena.SuddenDeathSize, self.config.Arena.ShrinkDuration)
                    self:_emitState(events)
                end
            end
        end
    elseif self.state == MatchState.SUDDEN_DEATH then
        if now >= (self.phaseEndsAt :: number) then
            self:_resolveFalls(events, now, true)
            if self.state == MatchState.SUDDEN_DEATH then
                self:_finish(events, now, nil, ResultReason.DRAW)
            end
        end
    elseif self.state == MatchState.RESULT then
        if now >= (self.phaseEndsAt :: number) then
            self:_afterResult(events, now)
        end
    end

    return events
end

return MatchModel
