--!strict
-- RoboPush Arena / Bootstrap.server.lua
-- Entry point: create RemoteEvents, start MatchService, clean up on close.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared:WaitForChild("GameConfig"))
local Remotes = require(Shared:WaitForChild("Remotes"))

local MatchService = require(script.Parent:WaitForChild("Services"):WaitForChild("MatchService"))

local remotes = Remotes.createAll(ReplicatedStorage)
MatchService.start({ config = GameConfig, remotes = remotes })

game:BindToClose(function()
    MatchService.stop()
end)
