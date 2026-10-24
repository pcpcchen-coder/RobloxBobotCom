--!strict
-- RoboPush Arena / InputController.lua
-- Maps PC / touch / gamepad to the same two commands (GDD 5):
--   Dash:    LeftShift | touch button | ButtonR2
--   Special: Q         | touch button | ButtonL1 (provisional)
-- Uses ContextActionService (GDD-approved fallback for the Input Action
-- System). Sends intent only; the server decides everything.
--
-- Interface: InputController.start(remotes) / InputController.stop()

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared:WaitForChild("GameConfig"))
local Maid = require(Shared:WaitForChild("Maid"))
local ClientState = require(script.Parent.Parent:WaitForChild("ClientState"))

local InputController = {}

local DASH_ACTION = "RoboPushDash"
local SPECIAL_ACTION = "RoboPushSpecial"

local maid = Maid.new()
local sequence = 0
local remotes: { [string]: RemoteEvent } = {}

local function currentHumanoid(): Humanoid?
    local character = Players.LocalPlayer.Character
    return character and character:FindFirstChildOfClass("Humanoid")
end

local function onDash(_name: string, inputState: Enum.UserInputState, _input: InputObject): Enum.ContextActionResult
    if inputState == Enum.UserInputState.Begin then
        sequence += 1
        remotes.RequestDash:FireServer(sequence)
    end
    return Enum.ContextActionResult.Sink
end

local function onSpecial(_name: string, inputState: Enum.UserInputState, _input: InputObject): Enum.ContextActionResult
    if inputState == Enum.UserInputState.Begin then
        local skillId = ClientState.get().selectedSkill
        if skillId == "" then
            skillId = GameConfig.Skills.DefaultSelection
        end
        -- Movement direction is only a hint (Side Burst side); server validates it.
        local humanoid = currentHumanoid()
        local hint = humanoid and humanoid.MoveDirection or nil
        remotes.RequestSpecial:FireServer(skillId, hint)
    end
    return Enum.ContextActionResult.Sink
end

-- Mirror the server's no-jump rule locally (Humanoid states are per-machine).
local function onCharacter(character: Model)
    local humanoid = character:WaitForChild("Humanoid") :: Humanoid
    if not GameConfig.Robot.JumpEnabled then
        humanoid:SetStateEnabled(Enum.HumanoidStateType.Jumping, false)
    end
end

local function layoutTouchButtons()
    -- Right side, above the default thumbstick area so they never overlap it.
    ContextActionService:SetTitle(DASH_ACTION, "DASH")
    ContextActionService:SetPosition(DASH_ACTION, UDim2.new(1, -150, 1, -150))
    ContextActionService:SetTitle(SPECIAL_ACTION, "SKILL")
    ContextActionService:SetPosition(SPECIAL_ACTION, UDim2.new(1, -230, 1, -100))
end

function InputController.start(remoteMap: { [string]: RemoteEvent })
    remotes = remoteMap
    ContextActionService:BindAction(DASH_ACTION, onDash, true, Enum.KeyCode.LeftShift, Enum.KeyCode.ButtonR2)
    ContextActionService:BindAction(SPECIAL_ACTION, onSpecial, true, Enum.KeyCode.Q, Enum.KeyCode.ButtonL1)
    layoutTouchButtons()
    maid:give(function()
        ContextActionService:UnbindAction(DASH_ACTION)
        ContextActionService:UnbindAction(SPECIAL_ACTION)
    end)

    local player = Players.LocalPlayer
    if player.Character then
        task.spawn(onCharacter, player.Character)
    end
    maid:give(player.CharacterAdded:Connect(onCharacter))
end

function InputController.stop()
    maid:cleanup()
end

return InputController
