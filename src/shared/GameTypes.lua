--!strict
-- RoboPush Arena / GameTypes.lua
-- Shared enums and payload types. Pure module (no Roblox APIs) so it can be
-- unit tested outside Studio.

local GameTypes = {}

GameTypes.MatchState = table.freeze({
    WAITING = "WAITING",
    COUNTDOWN = "COUNTDOWN",
    RUNNING = "RUNNING",
    SUDDEN_DEATH = "SUDDEN_DEATH",
    RESULT = "RESULT",
})

GameTypes.ResultReason = table.freeze({
    SCORE = "score", -- someone reached ScoreToWin
    TIMEOUT = "timeout", -- regulation ended with different scores
    SUDDEN_DEATH = "sudden_death", -- first valid fall in sudden death
    DRAW = "draw", -- sudden death ended without a score
    FORFEIT = "forfeit", -- opponent left during RUNNING / SUDDEN_DEATH
})

GameTypes.EffectType = table.freeze({
    DASH = "dash",
    DASH_HIT = "dash_hit",
    ROCKET_POP = "rocket_pop",
    ROCKET_HIT = "rocket_hit",
    SIDE_BURST = "side_burst",
    SIDE_HIT = "side_hit",
    SHIELD_UP = "shield_up",
    SHIELD_REBOUND = "shield_rebound",
    SHIELD_BLOCK = "shield_block",
    FALL = "fall",
})

export type MatchState = string
export type UserId = number

export type Scores = { [string]: number } -- keyed by tostring(userId) for RemoteEvent safety

export type MatchSnapshot = {
    matchId: string,
    state: MatchState,
    serverTime: number,
    endsAt: number?,
    scores: Scores,
    arenaSize: number,
    players: { UserId },
}

export type MatchEvent = {
    type: string,
    [string]: any,
}

-- Returns true only for the states in which falls can score and skills work.
function GameTypes.isCombatState(state: string): boolean
    return state == GameTypes.MatchState.RUNNING or state == GameTypes.MatchState.SUDDEN_DEATH
end

-- Skill selection is allowed outside active combat (ARCHITECTURE 3).
function GameTypes.isSkillSelectState(state: string): boolean
    return state == GameTypes.MatchState.WAITING or state == GameTypes.MatchState.COUNTDOWN or state == GameTypes.MatchState.RESULT
end

return table.freeze(GameTypes)
