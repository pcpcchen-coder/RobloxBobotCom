--!nocheck
-- Unit tests for src/server/Logic/MatchModel.lua (logic layer of T01, T02,
-- T05, T06, T07, T09, T13, T14, T19, T21). These do NOT replace Studio tests.

local GameConfig = shared("GameConfig")
local MatchModel = server("Logic/MatchModel")

local A, B, C = 101, 202, 303

local function ofType(events, kind)
    local list = {}
    for _, event in events do
        if event.type == kind then
            table.insert(list, event)
        end
    end
    return list
end

-- Simulates MatchService: performs every SpawnPlayer immediately (ignoring delay)
-- and records lifeIds.
local Harness = {}
Harness.__index = Harness

local function newHarness()
    local h = setmetatable({ model = MatchModel.new(GameConfig, "T"), now = 0, life = {}, log = {} }, Harness)
    return h
end

function Harness:apply(events)
    for _, event in events do
        table.insert(self.log, event)
        if event.type == "SpawnPlayer" then
            local lifeId = self.model:beginLife(event.userId, event.token, self.now)
            if lifeId then
                self.life[event.userId] = lifeId
            end
        end
    end
    return events
end

function Harness:add(userId)
    return self:apply(self.model:addPlayer(userId, self.now))
end

function Harness:remove(userId)
    return self:apply(self.model:removePlayer(userId, self.now))
end

function Harness:advance(seconds)
    self.now += seconds
    return self:apply(self.model:tick(self.now))
end

function Harness:fall(userId)
    return self:apply(self.model:reportFall(userId, self.life[userId], self.now))
end

function Harness:startRunning()
    self:add(A)
    self:add(B)
    self:advance(GameConfig.Match.Countdown)
    assert(self.model.state == "RUNNING", "expected RUNNING")
    self:advance(GameConfig.Match.SpawnProtection) -- move past spawn protection
end

local function scoreOf(h, userId)
    return h.model.scores[userId] or 0
end

return function(t)
    t.test("T01 one player waits; second player starts 3s countdown then RUNNING", function()
        local h = newHarness()
        h:add(A)
        expect.eq(h.model.state, "WAITING", "state after 1 player")
        expect.truthy(h.life[A], "lone player is spawned to walk around")
        local events = h:add(B)
        expect.eq(h.model.state, "COUNTDOWN", "state after 2 players")
        expect.eq(h.model.phaseEndsAt, GameConfig.Match.Countdown, "countdown end")
        expect.eq(#ofType(events, "SpawnPlayer"), 2, "both respawned symmetrically")
        h:advance(GameConfig.Match.Countdown - 0.01)
        expect.eq(h.model.state, "COUNTDOWN", "not yet running")
        h:advance(0.01)
        expect.eq(h.model.state, "RUNNING", "running after countdown")
        expect.eq(h.model.phaseEndsAt, h.now + GameConfig.Match.Duration, "120s regulation")
    end)

    t.test("T02 a fall gives the opponent exactly one point; duplicates ignored", function()
        local h = newHarness()
        h:startRunning()
        local lifeA = h.life[A]
        h:fall(A)
        h:apply(h.model:reportFall(A, lifeA, h.now)) -- duplicate report, same life
        h:advance(GameConfig.Match.DoubleFallWindow + 0.01)
        h:apply(h.model:reportFall(A, lifeA, h.now)) -- late duplicate
        h:advance(0.5)
        expect.eq(scoreOf(h, B), 1, "B score")
        expect.eq(scoreOf(h, A), 0, "A score")
        expect.eq(#ofType(h.log, "ScoreChanged") - 1, 1, "one ScoreChanged after the initial reset")
    end)

    t.test("falls are respawned after RespawnDelay with a new lifeId", function()
        local h = newHarness()
        h:startRunning()
        local before = h.life[A]
        h.log = {}
        h:fall(A)
        h:advance(GameConfig.Match.DoubleFallWindow + 0.01)
        local spawns = ofType(h.log, "SpawnPlayer")
        expect.eq(#spawns, 1, "one respawn")
        expect.eq(spawns[1].delay, GameConfig.Match.RespawnDelay, "respawn delay")
        expect.truthy(h.life[A] ~= before, "new lifeId")
    end)

    t.test("T05 third point ends the match immediately with no extra scoring", function()
        local h = newHarness()
        h:startRunning()
        for _ = 1, GameConfig.Match.ScoreToWin do
            h:fall(A)
            h:advance(GameConfig.Match.DoubleFallWindow + 0.01)
        end
        expect.eq(h.model.state, "RESULT", "RESULT after 3 points")
        local results = ofType(h.log, "Result")
        expect.eq(#results, 1, "exactly one Result")
        expect.eq(results[1].winner, B, "winner")
        expect.eq(results[1].reason, "score", "reason")
        -- Late fall after RESULT must not score.
        h:fall(A)
        h:advance(1)
        expect.eq(scoreOf(h, B), 3, "no score after RESULT")
        expect.eq(#ofType(h.log, "Result"), 1, "still one Result")
    end)

    t.test("timeout with different scores -> RESULT(timeout)", function()
        local h = newHarness()
        h:startRunning()
        h:fall(A)
        h:advance(GameConfig.Match.DoubleFallWindow + 0.01)
        h:advance(GameConfig.Match.Duration)
        expect.eq(h.model.state, "RESULT", "state")
        local result = ofType(h.log, "Result")[1]
        expect.eq(result.winner, B, "winner")
        expect.eq(result.reason, "timeout", "reason")
    end)

    t.test("T06 tie at 120s -> SUDDEN_DEATH 20s; first scorer wins", function()
        local h = newHarness()
        h:startRunning()
        h:advance(GameConfig.Match.Duration)
        expect.eq(h.model.state, "SUDDEN_DEATH", "sudden death")
        expect.eq(h.model.phaseEndsAt, h.now + GameConfig.Match.SuddenDeath, "20s")
        expect.eq(h.model.arenaSize, GameConfig.Arena.SuddenDeathSize, "18x18")
        h:advance(GameConfig.Match.SpawnProtection)
        h:fall(B)
        h:advance(GameConfig.Match.DoubleFallWindow + 0.01)
        local result = ofType(h.log, "Result")[1]
        expect.eq(h.model.state, "RESULT", "result")
        expect.eq(result.winner, A, "winner")
        expect.eq(result.reason, "sudden_death", "reason")
    end)

    t.test("T06 sudden death without a score -> draw", function()
        local h = newHarness()
        h:startRunning()
        h:advance(GameConfig.Match.Duration)
        h:advance(GameConfig.Match.SuddenDeath)
        local result = ofType(h.log, "Result")[1]
        expect.eq(result.winner, nil, "no winner")
        expect.eq(result.reason, "draw", "reason")
    end)

    t.test("T13 double fall inside window: no score, both respawn", function()
        local h = newHarness()
        h:startRunning()
        h.log = {}
        h:fall(A)
        h:advance(GameConfig.Match.DoubleFallWindow * 0.5)
        h:fall(B)
        h:advance(GameConfig.Match.DoubleFallWindow + 0.01)
        expect.eq(scoreOf(h, A) + scoreOf(h, B), 0, "no points")
        expect.eq(#ofType(h.log, "SpawnPlayer"), 2, "both respawn")
        for _, event in ofType(h.log, "FallResolved") do
            expect.eq(event.reason, "double_fall", "reason")
        end
    end)

    t.test("T13 double fall in sudden death also scores nothing and continues", function()
        local h = newHarness()
        h:startRunning()
        h:advance(GameConfig.Match.Duration)
        h:advance(GameConfig.Match.SpawnProtection)
        h:fall(A)
        h:fall(B)
        h:advance(GameConfig.Match.DoubleFallWindow + 0.01)
        expect.eq(h.model.state, "SUDDEN_DEATH", "continues")
    end)

    t.test("falls outside the window: first faller gives a point, second faller scores nothing while opponent respawns", function()
        local h = newHarness()
        h:startRunning()
        h:fall(A)
        h:advance(GameConfig.Match.DoubleFallWindow + 0.05)
        expect.eq(scoreOf(h, B), 1, "B scores")
        -- A is already respawned instantly by the harness; simulate opponent not alive:
        h.model.lives[A].alive = false
        h:fall(B)
        h:advance(GameConfig.Match.DoubleFallWindow + 0.05)
        expect.eq(scoreOf(h, A), 0, "no point while scorer is not alive")
    end)

    t.test("T09 disconnect during RUNNING -> remaining player wins by forfeit", function()
        local h = newHarness()
        h:startRunning()
        h:remove(B)
        local result = ofType(h.log, "Result")[1]
        expect.eq(h.model.state, "RESULT", "state")
        expect.eq(result.winner, A, "winner")
        expect.eq(result.reason, "forfeit", "reason")
        expect.eq(result.finalScores[tostring(A)], 0, "score not forced to 3")
        h:advance(GameConfig.Match.ResultDuration)
        expect.eq(h.model.state, "WAITING", "back to WAITING with one player")
    end)

    t.test("T14 disconnect during COUNTDOWN returns to WAITING", function()
        local h = newHarness()
        h:add(A)
        h:add(B)
        h:remove(B)
        expect.eq(h.model.state, "WAITING", "state")
        h:advance(GameConfig.Match.Countdown + 1)
        expect.eq(h.model.state, "WAITING", "no solo match")
    end)

    t.test("queued third player takes the empty slot", function()
        local h = newHarness()
        h:add(A)
        h:add(B)
        h:add(C)
        expect.falsy(h.model:isParticipant(C), "C is queued")
        h:remove(B)
        expect.eq(h.model.state, "COUNTDOWN", "new countdown with A and C")
        expect.truthy(h.model:isParticipant(C), "C participates")
    end)

    t.test("RESULT -> next COUNTDOWN with new matchId and reset scores", function()
        local h = newHarness()
        h:startRunning()
        local firstMatch = h.model.matchId
        h:fall(A)
        h:advance(GameConfig.Match.DoubleFallWindow + 0.01)
        h:advance(GameConfig.Match.Duration)
        h:advance(GameConfig.Match.ResultDuration)
        expect.eq(h.model.state, "COUNTDOWN", "next match")
        expect.truthy(h.model.matchId ~= firstMatch, "new matchId")
        expect.eq(scoreOf(h, B), 0, "scores reset")
        expect.eq(h.model.arenaSize, GameConfig.Arena.InitialSize, "arena reset")
    end)

    t.test("T21 stale lifeId from a previous match is ignored", function()
        local h = newHarness()
        h:startRunning()
        local oldLife = h.life[A]
        h:remove(B)
        h:add(B)
        h:advance(GameConfig.Match.ResultDuration)
        h:advance(GameConfig.Match.Countdown + GameConfig.Match.SpawnProtection)
        expect.eq(h.model.state, "RUNNING", "new match running")
        local events = h.model:reportFall(A, oldLife, h.now)
        expect.eq(#events, 0, "stale life ignored")
        h:advance(1)
        expect.eq(scoreOf(h, B), 0, "no score from stale life")
    end)

    t.test("stale SpawnPlayer token is rejected after a newer spawn request", function()
        local h = newHarness()
        h:startRunning()
        local model = h.model
        local deferred = model:reportFall(A, h.life[A], h.now)
        expect.eq(#deferred, 0, "fall during RUNNING is deferred to the double-fall window")
        h.now += GameConfig.Match.DoubleFallWindow + 0.01
        local oldSpawn = ofType(model:tick(h.now), "SpawnPlayer")[1]
        -- Respawn is still pending when the match ends and a new one starts.
        model:removePlayer(B, h.now)
        model:addPlayer(B, h.now)
        h.now += GameConfig.Match.ResultDuration
        local newSpawns = ofType(model:tick(h.now), "SpawnPlayer")
        expect.eq(#newSpawns, 2, "countdown respawns both")
        expect.eq(model:beginLife(A, oldSpawn.token, h.now), nil, "old token rejected")
        expect.truthy(model:beginLife(A, newSpawns[1].token, h.now), "new token accepted")
    end)

    t.test("falls in WAITING/COUNTDOWN never score but respawn", function()
        local h = newHarness()
        h:add(A)
        h.log = {}
        h:fall(A)
        expect.eq(#ofType(h.log, "SpawnPlayer"), 1, "respawn in WAITING")
        h:add(B)
        h:fall(B)
        expect.eq(scoreOf(h, A), 0, "no score in COUNTDOWN")
    end)

    t.test("spawn protection blocks acting; canAct only in combat states", function()
        local h = newHarness()
        h:add(A)
        h:add(B)
        expect.falsy(h.model:canAct(A, h.now), "COUNTDOWN blocks actions")
        h:advance(GameConfig.Match.Countdown)
        -- spawned at t=0 with 1.5s protection, countdown is 3s -> no longer protected
        expect.truthy(h.model:canAct(A, h.now), "running and unprotected")
        h:fall(A)
        h:advance(GameConfig.Match.DoubleFallWindow + 0.01)
        expect.truthy(h.model:isProtected(A, h.now), "protected right after respawn")
        local ok, reason = h.model:canAct(A, h.now)
        expect.falsy(ok, "protected cannot act")
        expect.eq(reason, "spawn_protected", "reason")
    end)

    t.test("T07/T19 shrink schedule: warnings 5s before, 36 at 45s, 24 at 90s", function()
        local h = newHarness()
        h:startRunning()
        local start = h.model.runningStartedAt
        h.log = {}
        -- step the clock in 0.5s increments like a coarse heartbeat
        while h.now < start + 100 do
            h:advance(0.5)
        end
        local warnings = ofType(h.log, "ArenaWarning")
        local changes = ofType(h.log, "ArenaChanged")
        expect.eq(#warnings, 2, "two warnings")
        expect.eq(warnings[1].nextSize, 36, "first warning size")
        expect.near(warnings[1].shrinkAt, start + 45, 1e-9, "first shrinkAt")
        expect.eq(warnings[2].nextSize, 24, "second warning size")
        expect.eq(#changes, 2, "two shrinks")
        expect.eq(changes[1].size, 36, "first shrink")
        expect.eq(changes[1].duration, GameConfig.Arena.ShrinkDuration, "shrink duration")
        expect.eq(changes[2].size, 24, "second shrink")
        expect.eq(h.model.arenaSize, 24, "current size")
    end)

    t.test("no shrink after an early win", function()
        local h = newHarness()
        h:startRunning()
        for _ = 1, 3 do
            h:fall(A)
            h:advance(GameConfig.Match.DoubleFallWindow + 0.01)
        end
        h.log = {}
        h:advance(50)
        expect.eq(#ofType(h.log, "ArenaWarning"), 0, "no warnings in RESULT")
    end)

    t.test("snapshot uses string keys for scores", function()
        local h = newHarness()
        h:startRunning()
        local snap = h.model:snapshot(h.now)
        expect.eq(snap.scores, { [tostring(A)] = 0, [tostring(B)] = 0 }, "scores")
        expect.eq(snap.state, "RUNNING", "state")
        expect.eq(snap.players, { A, B }, "players")
    end)
end
