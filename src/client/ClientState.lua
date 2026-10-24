--!strict
-- RoboPush Arena / ClientState.lua
-- Client-side mirror of server-authoritative state, for presentation only.
-- Controllers subscribe; nothing here is ever sent back as truth.

local ClientState = {}

export type State = {
    matchId: string,
    state: string,
    endsAt: number?,
    scores: { [string]: number },
    players: { number },
    arenaSize: number,
    selectedSkill: string,
    readyAt: { [string]: number },
    warning: { nextSize: number, shrinkAt: number }?,
    result: { winner: number?, reason: string, finalScores: { [string]: number } }?,
}

local state: State = {
    matchId = "none",
    state = "WAITING",
    endsAt = nil,
    scores = {},
    players = {},
    arenaSize = 0,
    selectedSkill = "",
    readyAt = {},
    warning = nil,
    result = nil,
}

local listeners: { (State, string) -> () } = {}

-- Sentinel for clearing a field in update() (nil values vanish from tables).
ClientState.None = table.freeze({})

function ClientState.get(): State
    return state
end

-- `reason` tells listeners what changed ("match", "score", "skill", ...).
function ClientState.update(reason: string, patch: { [string]: any })
    for key, value in patch do
        (state :: any)[key] = if value == ClientState.None then nil else value
    end
    for _, listener in listeners do
        task.spawn(listener, state, reason)
    end
end

function ClientState.subscribe(listener: (State, string) -> ()): () -> ()
    table.insert(listeners, listener)
    return function()
        local index = table.find(listeners, listener)
        if index then
            table.remove(listeners, index)
        end
    end
end

return ClientState
