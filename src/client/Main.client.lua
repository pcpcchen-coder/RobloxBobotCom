--!strict
-- RoboPush Arena / Main.client.lua
-- Client entry: wire server events into ClientState, then start controllers.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared:WaitForChild("Remotes"))

local ClientState = require(script.Parent:WaitForChild("ClientState"))
local Controllers = script.Parent:WaitForChild("Controllers")
local InputController = require(Controllers:WaitForChild("InputController"))
local UIController = require(Controllers:WaitForChild("UIController"))
local EffectController = require(Controllers:WaitForChild("EffectController"))

local remotes = Remotes.waitAll(ReplicatedStorage)

remotes.MatchSnapshot.OnClientEvent:Connect(function(snapshot)
    ClientState.update("snapshot", {
        matchId = snapshot.matchId,
        state = snapshot.state,
        endsAt = snapshot.endsAt,
        scores = snapshot.scores,
        players = snapshot.players,
        arenaSize = snapshot.arenaSize,
    })
end)

remotes.MatchChanged.OnClientEvent:Connect(function(matchId, state, endsAt)
    local patch: { [string]: any } = { matchId = matchId, state = state, endsAt = endsAt }
    if state ~= "RESULT" then
        patch.result = ClientState.None
    end
    if state ~= "RUNNING" then
        patch.warning = ClientState.None
    end
    ClientState.update("match", patch)
end)

remotes.ScoreChanged.OnClientEvent:Connect(function(_matchId, scores, _scorer)
    ClientState.update("score", { scores = scores })
end)

remotes.SkillState.OnClientEvent:Connect(function(key, availableAt, selectedSkill)
    local readyAt = table.clone(ClientState.get().readyAt)
    readyAt[key] = availableAt
    ClientState.update("skill", { readyAt = readyAt, selectedSkill = selectedSkill })
end)

remotes.ArenaWarning.OnClientEvent:Connect(function(nextSize, shrinkAt)
    ClientState.update("warning", { warning = { nextSize = nextSize, shrinkAt = shrinkAt } })
end)

remotes.ArenaChanged.OnClientEvent:Connect(function(size, _duration)
    ClientState.update("arena", { arenaSize = size, warning = ClientState.None })
end)

remotes.RoundResult.OnClientEvent:Connect(function(winner, reason, finalScores)
    ClientState.update("result", { result = { winner = winner, reason = reason, finalScores = finalScores }, scores = finalScores })
end)

UIController.start(remotes)
InputController.start(remotes)
EffectController.start(remotes)

-- Listeners are connected; resync in case events fired before we loaded.
remotes.RequestSnapshot:FireServer()
