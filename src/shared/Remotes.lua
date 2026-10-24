--!strict
-- RoboPush Arena / Remotes.lua
-- RemoteEvent contract (ARCHITECTURE 3). The server creates the folder; clients
-- only wait for it. Direction is documented per event; the server never trusts
-- any Server -> Client event fired by a client (Roblox prevents that anyway).

local Remotes = {}

Remotes.FolderName = "RoboPushRemotes"

-- Client -> Server (intent only; validated by CombatService / MatchService).
Remotes.ClientToServer = table.freeze({
    RequestDash = "RequestDash", -- (clientSequence: number?)
    RequestSpecial = "RequestSpecial", -- (skillId: string, directionHint: Vector3?)
    SelectSkill = "SelectSkill", -- (skillId: string)
    RequestSnapshot = "RequestSnapshot", -- () resync after the client finished loading
})

-- Server -> Client (authoritative results / presentation).
Remotes.ServerToClient = table.freeze({
    MatchSnapshot = "MatchSnapshot", -- (snapshot: MatchSnapshot)
    MatchChanged = "MatchChanged", -- (matchId, state, endsAt)
    ScoreChanged = "ScoreChanged", -- (matchId, scores, scorerUserId?)
    SkillState = "SkillState", -- (key: "dash" | skillId, availableAt: number, selectedSkill: string)
    CombatEffect = "CombatEffect", -- (effectType, sourceUserId?, targetUserId?, position: Vector3?, direction: Vector3?)
    ArenaWarning = "ArenaWarning", -- (nextSize, shrinkAt)
    ArenaChanged = "ArenaChanged", -- (size, shrinkDuration)
    RoundResult = "RoundResult", -- (winnerUserId?, reason, finalScores)
})

function Remotes.allNames(): { string }
    local names = {}
    for _, name in Remotes.ClientToServer do
        table.insert(names, name)
    end
    for _, name in Remotes.ServerToClient do
        table.insert(names, name)
    end
    table.sort(names)
    return names
end

-- Server only: create (or reuse) the folder and every RemoteEvent.
function Remotes.createAll(parent: Instance): { [string]: RemoteEvent }
    local folder = parent:FindFirstChild(Remotes.FolderName)
    if not folder then
        folder = Instance.new("Folder")
        folder.Name = Remotes.FolderName
        folder.Parent = parent
    end
    local map = {}
    for _, name in Remotes.allNames() do
        local remote = folder:FindFirstChild(name)
        if not remote then
            remote = Instance.new("RemoteEvent")
            remote.Name = name
            remote.Parent = folder
        end
        map[name] = remote :: RemoteEvent
    end
    return map
end

-- Client only: wait for the server-created remotes.
function Remotes.waitAll(parent: Instance): { [string]: RemoteEvent }
    local folder = parent:WaitForChild(Remotes.FolderName)
    local map = {}
    for _, name in Remotes.allNames() do
        map[name] = folder:WaitForChild(name) :: RemoteEvent
    end
    return map
end

return Remotes
